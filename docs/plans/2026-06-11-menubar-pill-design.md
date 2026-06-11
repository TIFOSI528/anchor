# 菜单栏嵌入模式（无刘海屏的遮挡修复）· 设计稿

> 2026-06-11 定稿。问题（用户在 Mac mini 实测）：强制假刘海时，DynamicNotchKit 画的
> **固定 300pt 黑块**盖住菜单栏中段的系统状态图标——看不见也点不到（左键查看、
> 右键操作全失效）。浮窗模式则悬在窗口内容上方，同样遮挡。

## 硬约束（先承认做不到的）

- **无法让系统把状态图标排到假刘海两边**：真刘海的菜单栏避让是 macOS 基于硬件级
  unsafe area（`auxiliaryTopLeft/RightArea`）的私有布局，第三方注册不了假的不可用区域。
- 无法隐藏/移动其它 app 的状态图标。
- 真刘海屏上系统对放不下的图标的处理就是**直接不显示**（Sonoma+），所以"展开期间
  暂时占用"不违背平台惯例；问题只在常驻 300pt 黑块太霸道。

## 方案：自研 MenuBarPillRenderer（用户选定 ①）

唯一能动的杠杆是让我们这层覆盖物变小、变透明、不挡点击：

| 状态 | 行为 |
|---|---|
| 休眠（绿区） | ~16pt 呼吸点嵌在菜单栏中段，`ignoresMouseEvents = true`——**图标照常可点** |
| 漂移/红区/摸鱼 | 展开成宽度=内容的胶囊（黑底），接收三手势；只在此期间临时占位 |
| 暂停/离线 | 隐藏 |

## 实现要点（与 open-vibe-island 对齐）

读了参考仓库 `open-vibe-island` 的 `OverlayPanelController`，它对同一问题的做法：

- 单个 borderless `NSPanel`，`level = .statusBar`，clear 背景，
  `[.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]`
- **默认 `ignoresMouseEvents = true`**，自己跟踪指针、只在悬停岛区/展开时翻成可交互
- 无刘海屏的假岛只有 190×38（对比 DynamicNotchKit 的 300pt），刘海几何用
  `safeAreaInsets` + auxiliary area 实算

我们采纳：窗口配置照搬；交互比它更简——休眠点**永远**穿透（圆点无手势需求，
拉回/摸鱼有热键和菜单），免去指针跟踪。指针悬停动态翻转留作后续可选优化。

## 后端选择

`IslandPosition` 增加 `.menuBar`；`auto` 在无刘海机型从 DynamicNotchKit-floating
改为 menuBar（默认体验即修复）。强制「刘海」（人造刘海，标签注明会盖图标）和
「顶部居中浮窗」保留为显式选项。窗口在 init 创建，更改后重启生效。

## 边界

- 展开态盖住中段图标的交互——与真刘海行为一致，且仅漂移期间
- hint 气泡内嵌在 pill 布局里（notch 后端仍悬挂在刘海下方）
- 多屏：主屏；与既有约定一致（每屏一岛 v1.1）

## 修订（同日，真刘海屏实测反馈）

用户在 MacBook 上确认绿区黑壳"下沿超出硬件刘海范围"。源码定位：DynamicNotchKit
compact 高度虽 = `safeAreaInsets.top`，但①底角半径写死 14pt（硬件 ~8pt），底部轮廓
更肥；②hover 时高度切到 `menubarHeight`，部分缩放模式比刘海高 1–2pt。均不 fork 不可改。

选定方案：**真刘海屏的 compact 也不画黑壳**——`MenuBarPillRenderer` 加 `besideNotch`
摆位（贴硬件刘海左缘 −6pt，`auxiliaryTopLeftArea` 实算，零覆盖 = 定义上绝对对齐；
保持可点击作菜单入口），expanded 仍由 DynamicNotchKit 从刘海长出。几何全部来自
`safeAreaInsets` / `auxiliaryTopLeftArea` 并监听 `didChangeScreenParametersNotification`，
跨机型/缩放/外接自动适配。

## 验证

布局/穿透是窗口行为，无法单测；手测清单：①休眠点不挡相邻图标点击 ②漂移展开
出现胶囊、三手势可用 ③hint 显示不裁剪 ④四个位置选项各自生效（重启后）。
