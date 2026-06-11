# Focus Lock（"只看这个"临时锁定）· 设计稿

> 2026-06-10 定稿。场景：在读一篇技术 blog / 一篇论文，跳出这个唯一限定以外的
> 一切都算漂移。与 preset 的区别：preset 是可复用的场景档案，锁是**一次性的
> 单目标会话**，用完即弃，不进 preset 列表、不持久化。

## 语义

```
命中锁定目标            → 绿区
preset 红名单命中        → 红区（已知时间黑洞照常拦）
其余一切（含平时的绿区） → 灰区漂移
```

优先级：**锁 > 红 > 灰**——锁是用户当下明确声明的意图，盖过一切。

## 粒度（用户确认的关键点）

扩展上报完整 URL，匹配引擎按 host+path 通配——粒度不受限于域名级：

| 档 | pattern | 场景 |
|---|---|---|
| **页面锁** | `host/path*` | 一篇文章 / 一篇论文；同站其它页面也算漂移 |
| **站点锁** | `host/*` | 整个博客站 / 文档站 |
| **app 锁** | bundleId | PDF 阅读器等本地 app（锁到具体文档需 AX 权限，v1.1） |

边界（诚实声明）：query/fragment 不破锁（匹配只看 host+path）；arxiv `/abs/`↔`/pdf/`
路径不同会破页锁（重锁或用站点锁）；个别 SPA 的 pushState 可能漏报；
浏览器无扩展时只能 app 锁（菜单标注"（整个应用）"）。

## 实现

- **Core `FocusLock`**（纯函数，可测）：`Target = .app(bundleId) | .urlPrefix(pattern)`；
  `allows(ctx)`；`classify(ctx, preset:engine:)` 实现 锁>红>灰。
  顺带把 `PresetEngine` 私有的通配匹配提为 `URLPatternMatcher`（两处共用，不复制）。
- **Coordinator**：`focusLock: FocusLock?` 作为 classifier overlay——reducer/preset/持久化
  零改动；加锁/解锁后 `reclassifyFrontmost()` 立即生效。
- **入口**：菜单栏「只看这个页面 / 只看这个站点 / 只看这个 app」（按当前上下文显隐），
  锁定后变「解除锁定（label）」；热键 ⌥⌘L 切换（加锁时取最具体目标）。
  不上灵动岛手势（"一辈子只学三个"是规格红线）。
- **状态可见性**：灵动岛休眠绿点在锁定时变蓝 + VoiceOver "已锁定"；解锁一键。
- **不带计时**（v1）：手动解锁；25/45min 倒计时列 v1.1 候选。
- **不持久化**：锁随解锁/退出消失；漂移记录照常入库（无特殊标记）。

## 测试

Core 单测：app 锁命中/未命中；页面锁前缀匹配（query 不破锁）；站点锁；
红名单保留；平时绿区被压成灰；锁优先于红。UI 入口手测。
