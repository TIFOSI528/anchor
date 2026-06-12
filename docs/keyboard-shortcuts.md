# 键盘快捷键

> 三个手势都有键盘等效（dynamic-island-spec §七）。全局快捷键由 `HotkeyMonitor`
> 监听；未授予辅助功能权限时全局监听静默退化，菜单栏内的等效菜单项仍可用。

## 全局（任何 app 前台时）

| 快捷键 | 等效手势 | 行为 |
|---|---|---|
| `⌃⌥⌘A` | 单击灵动岛 | 立即拉回最近的绿区 app |
| `⌃⌥⌘B` | 长按灵动岛 3s | 进入 5 分钟合法摸鱼（日上限：前 3 次软、第 4 次起硬） |
| `⌃⌥⌘P` | 上划灵动岛 | 暂停看护（≥10 字理由）；已暂停时再按 = 恢复 |
| `⌃⌥⌘L` | —（仅菜单/热键） | Focus Lock 开关：未锁 → 锁到最具体目标（页面 > app）；已锁 → 解除 |

## 菜单栏（菜单展开时）

| 快捷键 | 菜单项 |
|---|---|
| `R` | 今日复盘 |
| `,` | 设置... |
| `Q` | 退出 Anchor |

## 复盘 / 设置窗口

| 快捷键 | 行为 |
|---|---|
| `⌘W` | 关闭窗口（系统默认） |
| `↩`（Preset 编辑器内） | 保存 |

## 实现位置

- 全局监听：`Sources/AnchorApp/HotkeyMonitor.swift`
- 菜单等效：`Sources/AnchorApp/AppDelegate.swift`（`makeItem` 带 `.control+.option+.command`）
- VoiceOver：灵动岛各形态的 label 见 `IslandViews.swift` 的 `accessibilityLabel`
