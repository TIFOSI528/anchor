# 技术架构

## 一、整体拓扑

```
┌─────────────────────────────────────────────────────────────┐
│                  Anchor.app (SwiftUI + AppKit)              │
│  ┌────────────────────┐     ┌────────────────────────────┐  │
│  │  Dynamic Island UI │     │  Settings / Recap Window   │  │
│  │  (NSWindow @ notch)│     │  (SwiftUI)                 │  │
│  └─────────┬──────────┘     └────────────┬───────────────┘  │
│            │                              │                 │
│            └──────────┬───────────────────┘                 │
│                       │ in-process call                     │
│  ┌────────────────────┴───────────────────────────────────┐ │
│  │              AnchorCore (Swift library)                │ │
│  │  - StateReducer (绿/灰/红 状态机)                       │ │
│  │  - PresetEngine (规则匹配)                              │ │
│  │  - DriftTracker (倒计时 + friction 升级)               │ │
│  │  - SessionStore (SQLite + 持久化)                       │ │
│  │  - RecapGenerator (叙事模板 + score 计算)              │ │
│  │  - FrictionRenderer (CGShieldingWindow + Metal blur)   │ │
│  └────────────────────┬───────────────────────────────────┘ │
└───────────────────────┼─────────────────────────────────────┘
                        │ Unix Domain Socket
                        │ (~/.anchor/anchor.sock)
        ┌───────────────┼───────────────────────────┐
        │               │                           │
┌───────┴────────┐  ┌───┴────────────┐  ┌──────────┴────────┐
│ Chrome Ext     │  │ Safari Ext      │  │ Firefox Ext       │
│ (Manifest v3)  │  │ (App Ext)       │  │ (WebExt)          │
│ active tab URL │  │ active tab URL  │  │ active tab URL    │
└────────────────┘  └─────────────────┘  └───────────────────┘

非 app 内部前台监控：NSWorkspace 通知 → AnchorCore（无需 socket）
```

**关键设计决策**：
- **单进程 macOS app**（Anchor.app）承担 UI + Core + Daemon 三重职责。原本想做 daemon 分离（参考 open-vibe-island 的 four-target 架构），但 v1 没必要——专注力工具只需要 app 在用户登录后启动并保持运行，没有"hooks 进程"那种需要独立寿命的组件。
- **浏览器扩展是唯一外部进程**，因为 macOS native 拿不到浏览器 active tab URL（除非 hack Accessibility 读地址栏，脆弱）。

## 二、Swift Package 结构

```
Package.swift
Sources/
├── AnchorApp/          # SwiftUI + AppKit 应用壳
│   ├── AnchorApp.swift
│   ├── AppDelegate.swift
│   ├── DynamicIsland/
│   ├── Recap/
│   └── Settings/
├── AnchorCore/         # 核心逻辑库（无 UI 依赖）
│   ├── State/
│   ├── Preset/
│   ├── Drift/
│   ├── Session/
│   └── Recap/
├── AnchorDaemon/       # Socket 服务 + 浏览器扩展通信
│   ├── SocketServer.swift
│   └── BrowserBridge.swift
├── AnchorHooks/        # 预留：未来如果要接 AI agent hook（v3+）
└── AnchorExtension/    # 浏览器扩展共享代码（manifest 生成器等）
Tests/
└── AnchorCoreTests/    # 业务逻辑单元测试
```

**target 依赖关系**：
```
AnchorApp     → AnchorCore + AnchorDaemon
AnchorDaemon  → AnchorCore
AnchorHooks   → AnchorCore
AnchorCore    → (无外部依赖，只标准库 + SQLite.swift)
```

AnchorCore **故意零 UI 依赖**，保证业务逻辑可独立测试，未来也可以被 CLI 或其他壳调用。

## 三、关键 API 选型

### 前台 app 监控
```swift
import AppKit

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication,
        let bundleId = app.bundleIdentifier else { return }
    AnchorCore.stateReducer.onAppActivated(bundleId: bundleId)
}
```
- **不需要 Accessibility 权限**，零授权弹窗
- 延迟 < 50ms

### 灵动岛 NSWindow
- 使用 [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 作为外部依赖（MIT 协议）
- Fallback：非 notch Mac 用 top-center 浮动 NSWindow
- 窗口层级：`NSWindow.Level.statusBar` 之上、`screensSaver` 之下

### FrictionFog 实现
- 创建覆盖全屏的 NSWindow，level = `CGShieldingWindowLevel()`
- 内部 NSView 用 CALayer + Core Image `CIFilter.gaussianBlur`
- 对每个 Display 独立 window（多屏支持）
- 性能：blur 半径 8px 时 GPU < 3%，零卡顿

### SQLite
- 使用 [SQLite.swift](https://github.com/stephencelis/SQLite.swift)（MIT 协议）
- 数据库路径：`~/Library/Application Support/Anchor/anchor.sqlite`
- WAL 模式开启，避免读写锁竞争

### Foundation Models（v2 预留）
- macOS 15.2+ Apple Foundation Models framework
- 用于叙事生成（叙事模板作为 fallback）
- 推断 100% 本地

## 四、扩展 ↔ Daemon Socket 协议

### 连接
- **WebSocket：`ws://127.0.0.1:17604`（只绑定 loopback）**
- 协议：每条 WS 消息一个 JSON 对象（兼容 line-delimited 拼包）

> **修订（v0.1 实现时）**：最初设计是 Unix Domain Socket（`~/.anchor/anchor.sock`），
> 但 Chrome MV3 扩展拿不到 raw socket API，只能用 WebSocket（dynamic-island-spec §六
> 也写明 WebSocket）。消息体 JSON 不变；端口可在扩展 options 页调整。

### 消息类型

**扩展 → Daemon**：
```json
// 浏览器扩展启动时
{"type": "hello", "browser": "chrome", "version": "1.0.0"}

// active tab 变化
{"type": "tab_active", "browser": "chrome", "url": "https://twitter.com/home",
 "window_id": 1, "tab_id": 42, "timestamp": 1717545600}

// 浏览器退出前台（用户切到其他 app）
{"type": "browser_blurred", "browser": "chrome", "timestamp": 1717545610}

// 心跳（每 30 秒）
{"type": "heartbeat", "browser": "chrome"}
```

**Daemon → 扩展**：
```json
// 要求扩展把当前 tab 跳转到某个工作 URL（一键拉回时）
{"type": "navigate", "url": "https://github.com/myorg/repo"}

// 通知扩展进入 FrictionFog 模式（让扩展 grey out 页面，与系统级 fog 协同）
{"type": "friction_overlay", "level": 0.5}

// 清除 friction
{"type": "friction_clear"}
```

### 失败处理
- 心跳每 30s 一次（MV3 alarms 最小粒度）；**75s**（2.5 个周期）无任何消息视为僵尸连接踢掉
  （原文写 5s，与 30s 心跳矛盾，按实现修订）
- daemon 不可用：扩展静默不报错（不能因为 daemon 挂了导致浏览器卡顿）
- daemon 重启：扩展自动重连（指数 backoff，1s 起步、30s 封顶）

## 五、状态机核心（AnchorCore.StateReducer）

```swift
public enum AnchorState: Equatable {
    case green                          // 在白名单中
    case drifting(elapsed: TimeInterval) // 漂移中
    case red                            // 在黑名单中
    case slacking(remaining: TimeInterval) // 合法摸鱼中
    case paused(reason: String)          // 用户暂停
    case offline                         // 无活跃 session
}

public enum AnchorEvent {
    case appActivated(bundleId: String)
    case tabChanged(browser: String, url: URL)
    case tick(deltaSeconds: TimeInterval)
    case islandTapped
    case islandLongPressed
    case islandSwipedUp(reason: String)
    case presetSwitched(presetId: String)
}

public protocol StateReducer {
    func reduce(_ state: AnchorState, event: AnchorEvent) -> (AnchorState, [SideEffect])
}
```

**单一信息源**：所有 UI 都从 StateReducer 订阅状态变化，禁止任何组件持有自己的"本地状态"副本。

**SideEffect 模式**：状态变化产生的副作用（拉起 friction、播放触感、写日志）通过 SideEffect 枚举显式声明，不在 reducer 里直接执行——保证 reducer 纯函数性、可测试。

## 六、性能预算

| 项目 | 上限 |
|---|---|
| 空闲时 CPU | < 1% |
| FrictionFog 激活时 CPU | < 5% |
| 内存常驻 | < 80 MB |
| 启动耗时 | < 500 ms |
| Tap 拉回响应 | < 200 ms |
| 灵动岛动效 | 稳定 60fps |
| SQLite 单次写 | < 5 ms |

每个数字都进 CI 性能测试（v0.3+），超标 PR 不准合。

## 七、构建与发布

### 本地构建
```bash
# Swift Package
swift build -c release

# 打包成 .app
zsh scripts/package-app.sh

# 输出
output/Anchor.app
output/Anchor.dmg
```

### Code signing & 公证
- v0.1–v0.5：未签名 dev 版（用户需要在 Gatekeeper 手动放行）
- v1.0：Developer ID 签名 + notarization（需要 Apple Developer 账号 $99/年）
- 自动化通过 GitHub Actions workflow

### Auto-update
- 使用 [Sparkle 2](https://sparkle-project.org)（MIT 协议）
- appcast.xml 托管在 GitHub Pages
- 用户可在 Settings 关闭自动更新

## 八、跨组件不变量

> 这些是"无论如何不能违反"的硬约束，写在这里给所有 PR review。

1. **绿区里不能有任何后台 work** 触发 UI 重绘——节能 + 心理上"产品不存在"
2. **SQLite 写永远异步**——主线程绝对不 block 在 I/O
3. **任何外部依赖都要支持离线降级**——飞机上必须能用
4. **Socket 协议向后兼容**——扩展和 app 可能版本不一致，扩展端必须能处理未知 type
5. **所有 friction 都可在 Settings 关掉**——Accessibility 是底线

## 九、未来扩展点

留好接口，避免未来重写：

- **多 session 并发**（v2）：StateReducer 改造成"每个 preset 一个独立 reducer"
- **跨设备同步**（v2）：SQLite 文件挪到 iCloud Drive，加 conflict resolver
- **LLM 叙事**（v2）：RecapGenerator 内嵌 strategy 模式，模板/LLM 双实现
- **Team mode**（如果将来要做）：fork 出独立项目，不污染主仓库

## 十、参考实现

学习路径上的关键 repo：

- [open-vibe-island](https://github.com/Octane0411/open-vibe-island)：灵动岛 + hook 通信
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)：notch 浮窗
- [Sparkle](https://sparkle-project.org)：auto-update
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift)：本地 DB
- [Rectangle](https://github.com/rxhanson/Rectangle)：menu bar app 工程范式

---

> 任何技术选择都要回答："这个选择能让产品更 local-first / 更可审计 / 更可逆吗？" 答案是 no 就重新想。
