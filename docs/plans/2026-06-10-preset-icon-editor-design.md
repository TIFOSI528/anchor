# Preset 图标化编辑器 · 设计稿

> 2026-06-10 定稿（用户已确认范围与语义）。背景：preset 的 app 规则此前只能手写
> `app:bundle.id` 文本行，没人记得住 bundleId；同时漂移当下想拉黑一个 app 要绕进设置。

## 范围（已确认）

1. **chips 展示**：app 规则渲染成 真实应用图标 + 显示名 的 chip，可点 × 删除
2. **运行中 app 选择器**：列出正在运行的 `.regular` 应用，点选入绿/红区
3. **菜单栏一键收编**：「把当前 app 加入绿区 / 红区」，动态显示当前 app 名
4. URL 规则保持文本行（URL 无系统图标；favicon 需联网，违反 local-first）

不做（v1.1 候选）：/Applications 全量扫描选择器、拖拽 .app 添加、灵动岛上的收编入口。

## 核心决策

- **图标纯展示层**：`NSWorkspace.urlForApplication(withBundleIdentifier:)` → `icon(forFile:)`，
  渲染时解析 + NSCache 缓存。`ZoneRule` / DB schema / `PresetSerialization` **零改动**。
- **互斥语义**：加入红区自动从绿区移除（反之亦然）；只作用于 `.app` 精确规则，不碰 url 规则。
  以 `.gray` 收编 = 从两边移除（"放回灰区"），用于选择器里的取消操作。
- **立即重判**：规则变更后立刻对当前前台 app 重新分类（绕过 AppMonitor 去重）——
  漂移中拉黑立刻变红、FrictionFog 起（红区 5s 缓冲照旧）。反馈闭环最直观。

## 组件

| 件 | 位置 | 职责 |
|---|---|---|
| `Preset.capturing(bundleId:as:)` | AnchorCore（纯函数） | 互斥语义的唯一实现，单测覆盖 |
| `PresetLibrary.capture(...)` | AnchorApp | 调上者 + 持久化 + 触发 onActivePresetChange |
| `AppIconProvider` | AnchorApp | bundleId → (NSImage, 显示名)，NSCache；未安装 → 通用图标 + 裸 bundleId |
| `AppChipsView` / `RunningAppPicker` | AnchorApp | LazyVGrid 自适应 chips；运行中 app 列表（排除 Anchor 自己），绿/红切换按钮 |
| `AppCoordinator.captureCurrent(as:)` + `reclassifyFrontmost()` | AnchorApp | 收编目标取 `AppMonitor.current`（避免菜单点击时 frontmost 变成 Anchor 自己）；重判走 `monitor.reset()` + 重新分类 |
| AppDelegate 菜单两项 + `NSMenuDelegate` | AnchorApp | 菜单展开时刷新「把「X」加入绿区」标题；无目标时置灰 |

## 数据流

收编：菜单/选择器 → `capture` → `Preset.capturing`（互斥）→ `PresetLibrary.upsert`（DB 异步写）
→ `onActivePresetChange` → `rebuildReducer` → `reclassifyFrontmost` → 状态机 → 岛/雾/菜单栏即时反馈。

## 边界

- 前台是 Anchor 自己：菜单项置灰（收编目标用 monitor.current，本就排除自身）
- 收编浏览器 = 整个应用进名单（工作 tab 一起变色）：菜单标题附"（整个应用）"，
  编辑器 footer 提示 tab 级控制用 url 规则
- 未安装 app 的 chip：通用图标 + bundleId 文本，仍可删除

## 测试

- AnchorCoreTests `PresetCaptureTests`：加绿/加红/互斥/灰区移除/幂等/url 规则不受影响
- 手测清单：①漂移中菜单拉黑 → 立即红+雾 ②选择器点选 → chips 即时更新 ③编辑器保存后
  切 app 验证分类 ④收编浏览器时提示文案 ⑤未安装 app chip 显示

## 修订（同日，用户首测反馈）

实测发现两件事，已落地：

1. **菜单读取当前归属**：展开菜单时查 `Preset.membership(...)` —— 已在绿区的对象
   「加入绿区」打钩 ✓ 并置灰，红区同理；新增第三项「把「X」移回灰区」（已列入时可点）。
2. **浏览器收编对象改为站点**：前台是浏览器且扩展已上报 tab 时，收编
   `host/*` url 规则（标题显示「把「github.com」加入红区」）；拿不到 tab 才退回
   整个应用模式（保留"（整个应用）"提示）。根因：用户对浏览器的收编预期天然是
   tab 级（"github 理论上是绿区"），整 app 收编会让 app 级规则盖过所有 url 规则
   （引擎红 > 绿 > 灰，app 规则与 URL 无关）。
3. 顺带澄清一个易混淆点：**灰区漂移 ≥3min 的灵动岛形态就是红色**（spec §三 形态 3
   覆盖"红区 / 顶层 friction"两者）——视觉上像红区但菜单栏文字是「漂移 m:ss」。
