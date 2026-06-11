# 灵动岛状态机规范

> 这是产品的"脸"。任何视觉、交互、动效调整都要回到本文档对齐。

## 一、三态空间模型

Anchor 把所有 app + URL 分到三个状态空间：

| 状态 | 定义 | 用户操作 |
|---|---|---|
| **绿区 Green** | 当前活动 preset 的白名单（app + tab 组合） | 默认无 friction |
| **灰区 Gray** | 未分类的 app/tab | 默认放行，但启动漂移计时 |
| **红区 Red** | 当前活动 preset 的黑名单 | 立即触发 friction（保留 5 秒缓冲） |

**Preset** 是用户预定义的工作场景，例如：

```
preset: "写代码"
  green:
    - app: com.microsoft.VSCode
    - app: com.apple.Terminal
    - url: github.com/myorg/*
    - url: stackoverflow.com/*
    - url: docs.python.org/*
  red:
    - url: twitter.com/home
    - url: x.com/home
    - url: youtube.com/feed/*
    - app: com.xiaohongshu.discover
  gray: (其余一切)
```

**关键设计决策**：
- **绝大多数用户不会穷举黑或白名单**。灰区作为"未分类放行"的中间态，让用户不必一开始就做完美配置。
- **URL pattern 支持通配符**，让"GitHub 上自己的仓库 = 绿区"和"GitHub trending = 红区"成为可能——这是 Anchor 区别于所有现有工具的杀手锏。

## 二、漂移衰减曲线

用户从绿区切到非绿区的瞬间，灵动岛进入"漂移模式"，friction 沿时间曲线增长：

| 时长 | 灵动岛形态 | 灰区屏幕变化 | 红区屏幕变化 |
|---|---|---|---|
| 0 s | 静默呼吸 → 出现箭头 | 无 | 5 秒缓冲后 50% 模糊 |
| 0–30 s | 圆环倒计时开始 | 无 | 模糊 + 灰度 30% |
| 30 s–1 min | 倒计时圆环 + 颜色变浅橙 | 屏幕边缘 1px 橙色光晕 | 模糊 + 灰度 50% |
| 1–3 min | 完全展开为橙色 + 拉回按钮 + 振动一次 | 饱和度 ↓70% · 输入延迟 +50ms | FrictionFog 加重 |
| 3 min+ | 红色 + 锁定图标 | FrictionFog 加重 | 鼠标滚动锁定 |

**红区的 5 秒缓冲**：用户经常会"手滑切到 Twitter"或者"点了一个错误链接"。5 秒缓冲允许用户立刻切回，不会因为 0 秒就触发 panic。

**漂移倒计时的可配置上限**：默认 60 秒，用户可在 Settings 调到 15s–5min 之间。**不做自适应**（见 product-philosophy.md 决策原则三）。

## 三、灵动岛视觉状态机

### 形态 0：休眠（绿区，长时间无变化）
- 大小：40 × 14 px 黑色 pill
- 内容：一颗 #22c55e 绿点，呼吸动画（2 秒周期）
- 目的：让产品"几乎不存在"

### 形态 1：刚漂移（0–30s）
- 大小：70 × 18 px 黑色 pill
- 内容：左侧 5.5px 圆环倒计时（橙色 #f59e0b），右侧"0:30" 计时文本
- 动画：圆环顺时针填充

### 形态 2：漂移加深（1–3min）
- 大小：110 × 22 px 橙色 pill (#d97706)
- 内容：白色文字 "1:24 ↩ 回到 VS Code"
- 动画：进入时从形态 1 平滑放大 + 颜色过渡 200ms

### 形态 3：红区 / 顶层 friction
- 大小：140 × 24 px 红色 pill (#dc2626)
- 内容：白色文字 "立即拉回 · 已离开 X 秒"
- 动画：进入时配合系统级触感反馈 1 次（macOS 14+ Haptic Feedback）

### 形态 4：合法摸鱼（长按触发）
- 大小：70 × 20 px 橙色 pill
- 内容：白色 "5:00" 倒计时
- 动画：圆环逆时针递减

**所有形态过渡时长**：200ms ease-out。过渡曲线必须用相同的 timing function，避免视觉跳跃感。

## 四、三个手势

> "一辈子只学三个，多了用户都会忘。"

### 手势 1：单击（Tap）
- **触发**：左键单击灵动岛区域
- **行为**：立即切换到最近的绿区 app（用 NSWorkspace.shared.frontmostApplication 的历史栈）
- **响应时间硬指标**：< 200ms（从 click 到 app 切到前台）
- **失败回退**：如果没有最近绿区 app，弹一个 0.5s 的轻提示"暂无可拉回的目标，请先访问绿区 app"

### 手势 2：长按 3 秒（Long press）
- **触发**：左键按住灵动岛 3 秒不松手
- **反馈**：按下 0–3 秒期间，灵动岛逐渐变橙 + 显示"摸一会儿吧 (3 秒)"
- **行为**：进入 5 分钟合法摸鱼模式，灵动岛切换到形态 4
- **结束**：5 分钟到自动拉回到最近绿区 app + 触感反馈一次
- **重要决策**：每天前 3 次为"软上限"（到时再问一次"还要 5 分钟吗？"），第 4 次起为"硬上限"（强制拉回）。日计数 00:00 重置。

### 手势 3：向上划走（Swipe up）
- **触发**：在灵动岛上从下往上 swipe（> 30px 距离）
- **行为**：暂停整个 session，弹出输入框
- **强制输入**：用户必须打字 ≥ 10 个字符的"暂停理由"才能确认
- **目的**：防止无意识放弃；同时这些理由会进每日复盘的"暂停记录"，有反思价值

## 五、动效与触感

### 必须的过渡
- 所有形态切换：200ms ease-out
- 倒计时圆环：实时连续动画（60fps）
- 拉回时的"app 切换"：跟随系统默认动画

### 触感反馈（NSHapticFeedbackPerformer）
- 形态 1 → 形态 2 升级时：`.alignment` 单次
- 形态 2 → 形态 3 升级时：`.levelChange` 单次
- 单击拉回成功时：`.generic` 单次
- 进入合法摸鱼时：`.alignment` 单次
- 摸鱼结束时：`.levelChange` 单次

### 必须避免
- ❌ 任何"突然蹦出来"的动效
- ❌ 任何持续超过 500ms 的动画过渡
- ❌ 红色闪烁、警告音、强光——这些会让用户产生敌意

## 六、技术实现要点

### 灵动岛区域定位
- Notch Mac：使用 [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 或自实现 NSWindow 贴在 notch 区域
- 非 Notch Mac：top-center 浮动 bar，宽度 / 位置匹配 notch 视觉

### 前台 app 监控
```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil, queue: .main
) { notification in
    // 拿 app bundle identifier，比对当前 preset 的 green/red 规则
}
```
不需要 Accessibility 权限，零警告框。

### Tab 监控（关键创新）
- Chrome / Safari / Firefox 各自开发扩展
- 扩展通过 WebSocket 把 active tab URL 上报给本地 Daemon
- Daemon 维护一份"当前所有浏览器 active tab"的 in-memory 状态
- 详细协议见 [technical-architecture.md](technical-architecture.md#扩展-↔-daemon-socket-协议)

### 屏幕 FrictionFog
- 用 Core Image + Metal shader 实现全屏 blur overlay
- 通过 `CGShieldingWindowLevelKey` 创建覆盖全屏的 NSWindow
- blur 半径连续可调：0 → 8px → 16px
- 性能开销 < 2% CPU（已验证）

## 七、Accessibility（不忘掉的少数人）

- 所有手势必须有键盘等效：`⌥⌘A` = tap、`⌥⌘B` = 摸鱼、`⌥⌘P` = pause
- 所有视觉状态必须有 VoiceOver label
- FrictionFog 必须可关闭（Settings → Accessibility → 减少屏幕变化）

## 八、不做的（v1）

- ❌ 自适应漂移倒计时（用户掌控权 > 智能化）
- ❌ 多 session 并发（同时只能跑一个 preset）
- ❌ 灵动岛上显示通知 / 消息 / 其他 app 状态（保持纯粹）
- ❌ 自定义灵动岛主题（先把默认做到极致）

---

> **设计回归**：每次想加东西到灵动岛上，先问"绿区里它还隐形吗？" 答案是 no 就砍掉。
