# Anchor v1 MVP 路线图

> 6–8 周交付第一个能 ship 的版本。28 个独立 PR 任务，按周组织。

## 总体节奏

| 周次 | 主题 | 关键里程碑 |
|---|---|---|
| Week 1 | **地基** | Swift Package 跑通，前台 app 监控可用 |
| Week 2 | **状态机** | 三态 reducer + Preset 引擎，可命令行测试 |
| Week 3 | **灵动岛** | Notch 浮窗显示 4 种形态，3 手势工作 |
| Week 4 | **Friction** | FrictionFog 全屏 blur，渐进升级曲线工作 |
| Week 5 | **浏览器扩展** | Chrome 扩展 + Daemon socket，tab 级粒度可用 |
| Week 6 | **复盘** | SQLite 持久化 + 24h 时间线 + Deep Score |
| Week 7 | **打磨 + 周回顾** | 罪人榜 + 漂移链 + 周回顾建议引擎 |
| Week 8 | **发布** | 打包、签名、Sparkle、README 完善、首发 |

每周末跑一次 dogfood（作者自己用），不通过不进入下周。

---

## Week 1 · 地基（PR 1–4）

### PR #1：初始化 Swift Package
- [ ] Package.swift 含 5 个 target（App / Core / Daemon / Hooks / Extension）
- [ ] AnchorCore 引入 SQLite.swift 依赖
- [ ] AnchorApp 引入 DynamicNotchKit 依赖
- [ ] `swift build` 全 target 编译通过

### PR #2：基础 App 壳
- [ ] AppDelegate + NSStatusItem（menu bar 图标）
- [ ] 启动时启动 Daemon 子模块
- [ ] 退出时清理 socket 文件
- [ ] menu bar 显示当前状态文字（"绿区" / "漂移 0:30" / "红区"）

### PR #3：前台 app 监控
- [ ] NSWorkspace 通知订阅
- [ ] AnchorCore.AppMonitor 模块，每个事件附加 bundleId + 时间戳
- [ ] AnchorCoreTests：用 mock 事件流测试 monitor 行为
- [ ] Acceptance：切到 5 个不同 app，menu bar 文字正确变化

### PR #4：项目脚手架
- [ ] scripts/package-app.sh
- [ ] .github/workflows/ci.yml（build + test）
- [ ] .editorconfig + SwiftFormat 配置
- [ ] CONTRIBUTING.md 跑通的本地开发指南

---

## Week 2 · 状态机（PR 5–8）

### PR #5：Preset 数据模型
- [ ] AnchorCore.Preset 结构（id / name / green rules / red rules / drift threshold）
- [ ] PresetEngine：给一个 (app, url) 返回 .green / .gray / .red
- [ ] URL pattern matching（支持 * 通配符 + 子路径）
- [ ] 单元测试覆盖：精确匹配、通配符、混合规则、优先级

### PR #6：StateReducer
- [ ] AnchorState 枚举（green / drifting / red / slacking / paused / offline）
- [ ] AnchorEvent 枚举
- [ ] StateReducer.reduce 纯函数实现
- [ ] SideEffect 枚举（renderFriction / playHaptic / writeLog / ...）
- [ ] 单元测试：每条状态迁移路径

### PR #7：DriftTracker（倒计时）
- [ ] Tick driver（CADisplayLink-equivalent，1Hz）
- [ ] 漂移计时从 0 开始递增
- [ ] friction level 计算（0–30s / 30s–1min / 1–3min / 3min+）
- [ ] 单元测试：时间推进时状态正确升级

### PR #8：内置 default presets
- [ ] "写代码" preset（VS Code + GitHub + SO + 终端）
- [ ] "读资料" preset（Reader Mode 主导）
- [ ] "随便看看" preset（无限制，仅做统计）
- [ ] 首次启动自动安装

---

## Week 3 · 灵动岛（PR 9–13）

### PR #9：灵动岛 NSWindow 框架
- [ ] DynamicNotchKit 集成
- [ ] 探测当前 Mac 是否有 notch，分流到 notch 模式 / top-center 模式
- [ ] 多屏支持（每屏一个 island）
- [ ] 窗口层级 + 鼠标 hover 检测

### PR #10：四种视觉形态
- [ ] 形态 0：休眠（绿点呼吸）
- [ ] 形态 1：漂移 0–30s（圆环 + 时间）
- [ ] 形态 2：漂移加深（橙色 + 拉回按钮）
- [ ] 形态 3：红区（红色 + 警示）
- [ ] 形态 4：合法摸鱼（5min 倒计时）
- [ ] 200ms 过渡动画

### PR #11：三个手势
- [ ] 单击 → SideEffect.snapBackToGreen
- [ ] 长按 3s → SideEffect.enterSlacking(5min)
- [ ] 向上 swipe → SideEffect.pauseSession + 弹输入框
- [ ] 触感反馈（NSHapticFeedbackPerformer）
- [ ] 键盘快捷键等效（⌃⌥⌘A / B / L / P）

### PR #12：snap back 实现
- [ ] LastGreenAppTracker：维护一个"最近 5 个绿区 app"栈
- [ ] 单击拉回时切到栈顶 app（NSRunningApplication.activate）
- [ ] 响应时间 < 200ms 性能测试
- [ ] Edge case：栈空时显示一个 hint，不报错

### PR #13：合法摸鱼模式
- [ ] 5min 倒计时器
- [ ] 摸鱼期间灵动岛切到形态 4
- [ ] 到时自动 snap back + haptic
- [ ] 软上限/硬上限切换（前 3 次软、第 4 次起硬，日计数）

---

## Week 4 · Friction（PR 14–16）

### PR #14：FrictionFog 全屏模糊
- [ ] CGShieldingWindow 创建
- [ ] Metal shader / Core Image Gaussian blur
- [ ] 多屏独立 window
- [ ] blur 半径连续可调（0–16px）
- [ ] 性能测试：CPU < 5%、稳定 60fps

### PR #15：渐进 friction 编排
- [ ] 时间曲线驱动 blur 半径
- [ ] 灰区 + 红区不同曲线
- [ ] 红区 5 秒缓冲
- [ ] 拉回时 fog 立即清除（200ms ease-out）

### PR #16：输入延迟 + 滚动锁
- [ ] CGEventTap 实现可选输入延迟
- [ ] 顶层 friction 时禁用滚动事件
- [ ] Accessibility settings 提供"减少 friction"开关
- [ ] 默认 OFF，仅在用户启用时介入

---

## Week 5 · 浏览器扩展（PR 17–21）

### PR #17：Chrome 扩展骨架（Manifest v3）
- [ ] manifest.json + service worker
- [ ] active tab 监听（tabs.onActivated + tabs.onUpdated）
- [ ] WebSocket client 连接 daemon
- [ ] 心跳 30s

### PR #18：Daemon SocketServer
- [ ] Unix Domain Socket 监听 ~/.anchor/anchor.sock
- [ ] line-delimited JSON 解析
- [ ] 多扩展连接管理（Map<browserId, Connection>）
- [ ] 优雅断连处理

### PR #19：BrowserBridge 业务接入
- [ ] 接收 tab_active 事件 → 调用 StateReducer
- [ ] tabs 状态合并：以"前台浏览器的 active tab"为准
- [ ] 浏览器失焦时清除其 tab 状态

### PR #20：扩展安装引导
- [ ] App 首启检测：未安装扩展则弹引导
- [ ] 一键打开 Chrome Web Store / 本地 unpacked load 指南
- [ ] Settings 显示扩展连接状态

### PR #21：扩展 → 拉回 / overlay
- [ ] 单击 island 拉回时若目标是 URL，让扩展 navigate
- [ ] 顶层 friction 时让扩展 inject grey overlay
- [ ] 扩展端的 ContentScript 注入 / 移除

---

## Week 6 · 复盘（PR 22–24）

### PR #22：SQLite 数据层
- [ ] schema 初始化 + migration framework
- [ ] sessions / drifts / presets / daily_recaps 四张表
- [ ] WAL 模式
- [ ] DataAccessor 抽象 + 测试

### PR #23：Session 持久化
- [ ] 每个 session 开始 / 结束写入 DB
- [ ] 每个 drift event 写入 DB（异步队列）
- [ ] DriftEndReason 完整记录
- [ ] CrashSafety：app crash 后能恢复"进行中 session"

### PR #24：今日复盘 UI（基础版）
- [ ] Recap window（SwiftUI）
- [ ] Section 1：Score + 叙事段落（模板生成）
- [ ] Section 2：24h 时间线（横向 bar）
- [ ] 22:00 灵动岛敲门触发

---

## Week 7 · 打磨 + 周回顾（PR 25–27）

### PR #25：复盘 UI 补全
- [ ] Section 3：本周漂移热力图（5x7 网格）
- [ ] Section 4：今日罪人榜（含自嘲文案库 + 严肃模式）
- [ ] Section 5：漂移链（Top 2 路径）
- [ ] 整页可截图分享（命令导出 PNG）

### PR #26：周回顾建议引擎
- [ ] 三类规则（黑名单建议 / preset 调整 / 节律建议）
- [ ] 每周只推一条，必须可解释
- [ ] 一键 apply + 一周内可撤销
- [ ] 周日 21:00 自动触发

### PR #27：Settings 页面
- [ ] General：开机启动 / 灵动岛位置 / 触感
- [ ] Presets：创建、编辑、删除 preset
- [ ] Friction：曲线开关、严肃模式、Accessibility
- [ ] About：版本、许可、致谢

---

## Week 8 · 发布（PR 28）

### PR #28：发布管线
- [ ] scripts/package-app.sh 完善（签名、公证）
- [ ] Sparkle 接入 + appcast.xml
- [ ] GitHub Actions release workflow
- [ ] README.md 双语化（中英）
- [ ] Demo GIF（必须！）
- [ ] v0.1.0 tag + DMG 上传

---

## v1.0 验收清单

发布前必须全部勾掉：

**功能**
- [ ] 三个内置 preset 开箱可用
- [ ] tab 级粒度在 Chrome 上 work
- [ ] 三个手势全部 work，响应时间达标
- [ ] FrictionFog 平滑、可关闭
- [ ] 每日复盘 22:00 准时
- [ ] 周回顾建议至少跑通一周

**性能**
- [ ] 空闲 CPU < 1%
- [ ] FrictionFog 时 CPU < 5%
- [ ] 内存 < 80MB
- [ ] tap 拉回 < 200ms

**质量**
- [ ] AnchorCore 单元测试覆盖率 > 70%
- [ ] 主流程手测脚本通过（写一个）
- [ ] dogfood 满 5 天无 crash

**文档**
- [ ] README.md 完整、双语
- [ ] 4 份 docs/ spec 与代码一致
- [ ] CONTRIBUTING.md
- [ ] LICENSE (GPL-3.0)
- [ ] Demo GIF 至少 1 个

---

## v1.1+ 候选（不进 v1）

按优先级：

1. Safari 扩展（macOS Safari Web Extension）
2. Firefox 扩展
3. 智能 preset 推荐（基于数据反向建议）
4. Apple Foundation Models 叙事升级
5. 简易 i18n（先中英）
6. iCloud Drive 跨设备同步

---

> 每个 PR 不超过 400 行代码改动，超过的拆分。Review 优先级：哲学是否对齐 > 是否有测试 > 代码质量。
