<!--
  Anchor — README (中文版优先)
  English version below ↓
-->

<p align="center">
  <img src="Assets/Brand/anchor-logo.svg" alt="Anchor" width="120" />
</p>

<h1 align="center">Anchor</h1>

<p align="center">
  <b>桅杆上的瞭望员，不是狱卒。</b><br/>
  一根隐形的橡皮筋，系在你和你的任务之间。
</p>

<p align="center">
  <a href="#中文">中文</a> ·
  <a href="#english">English</a> ·
  <a href="docs/product-philosophy.md">产品哲学</a> ·
  <a href="docs/dynamic-island-spec.md">灵动岛规范</a> ·
  <a href="docs/daily-recap-spec.md">每日复盘规范</a> ·
  <a href="docs/technical-architecture.md">技术架构</a> ·
  <a href="docs/mvp-roadmap.md">v1 路线图</a>
</p>

<hr/>

<p align="center">
  <img src="Assets/demo/drift-demo.gif" alt="漂移 → 灵动岛倒计时 → 拉回绿区" width="600" />
  <br/><sub>绿区休眠点 → 切到灰区 app 开始漂移倒计时 → 回到绿区收起</sub>
</p>

<a id="中文"></a>

## 一句话

**Anchor 是一个 macOS 上的开源专注力工具，用灵动岛形态做"温和牵引"——不屏蔽，不审判，只是在你漂走时轻轻拽一下。**

## 它解决什么

现有专注力软件分两个极端：

- 一极是 **Cold Turkey / Freedom 这类"硬屏蔽"**——把你锁在牢里，用户敌意大、易反弹。
- 另一极是 **Rize / RescueTime 这类"被动统计"**——只看报表，不干预，对实际行为改变约等于零。

中间地带几乎没人做。**Anchor 占据的就是这个中间地带：渐进 friction + 黑白灰三态 + 灵动岛形态 + 每日叙事化复盘。**

## 它和别人不一样的地方

| | Cold Turkey | One Sec | Rize | Opal | **Anchor** |
|---|---|---|---|---|---|
| 黑名单 | ✅ 硬屏蔽 | ✅ | ❌ | ✅ | ✅ 渐进式 |
| 白名单 | ❌ | ❌ | ❌ | ❌ | ✅ |
| 灰区计时 | ❌ | ❌ | ✅ 仅统计 | ❌ | ✅ + 漂移衰减 |
| Tab 级粒度 | 仅 domain | ❌ | ❌ | ❌ | ✅ URL pattern |
| 灵动岛形态 | ❌ | ❌ | ❌ | ❌ | ✅ |
| 渐进 friction | ❌ | ✅ 单次 | ❌ | ❌ | ✅ 时间曲线 |
| 一键拉回 | ❌ | ❌ | ❌ | ❌ | ✅ |
| 叙事化复盘 | ❌ | ❌ | ❌ | ❌ | ✅ |
| Local-first 开源 | ❌ | ❌ | ❌ | ❌ | ✅ |

## 核心机制

**三态空间**：

- **绿区** = 白名单 app / tab（用户当前任务允许的）。灵动岛几乎隐形。
- **灰区** = 未分类。默认放行但计时。
- **红区** = 黑名单（Twitter feed、小红书、抖音等）。立即 friction。

**漂移衰减**：离开绿区后，灵动岛会从静默呼吸 → 倒计时圆环 → 橙色拉回按钮 → 红色屏幕模糊，**friction 是连续曲线，不是开关**。

**三个手势，一辈子只学三个**：

- **单击灵动岛** → 一键拉回最近的绿区 app（< 200ms）
- **长按 3 秒** → 承认"我就是要摸鱼"，合法休息 5 分钟
- **向上划走** → 暂停 session（需打字 10 字理由）

**每日复盘**：每天 22:00 灵动岛轻敲一下，打开是一段像朋友写给你的复盘信，加上时间线、漂移热力图、今日罪人榜、漂移链。周日 21:00 自动生成"周回顾 + 1 条可一键 apply 的 preset 建议"，形成 *统计 → 建议 → 优化 → 下周更好* 的闭环。

详细规范见 [docs/dynamic-island-spec.md](docs/dynamic-island-spec.md) 和 [docs/daily-recap-spec.md](docs/daily-recap-spec.md)。

## 不做什么（重要）

- **不做硬屏蔽**——Anchor 永远保留逃生通道（长按摸鱼）。
- **不做 team mode**——自律工具和社交压力工具是两种不同产品。
- **不上云**——所有数据本地 SQLite，零账号，零遥测。
- **不做反作弊**（v1）——Anchor 是"温柔的橡皮筋"，不是"系统监狱"。
- **不做跨平台**（v1）——macOS only，吃尽 Dynamic Island / Notch 的硬件红利。

## 状态

**v0.1 功能完备，作者 dogfood 中** —— [v1 路线图](docs/mvp-roadmap.md) 28 项全部落地，149 个单元测试；灵动岛对刘海 / 无刘海机型分别适配（真刘海侧点 / 菜单栏嵌入胶囊）。

## 安装

**方式一：下载 dmg（推荐）**

1. 到 [Releases](../../releases) 下载最新 `Anchor-x.y.z.dmg`，拖入「应用程序」
2. 首次打开若被 Gatekeeper 拦截：右键 → 打开（公证完成后的版本无此步骤）
3. **tab 级判定需要浏览器扩展**：Chrome 打开 `chrome://extensions` → 开发者模式 → 「加载已解压的扩展程序」→ 选 app 内的扩展目录（设置 → 通用 → 浏览器扩展 → 「安装指南」可直达）

**方式二：源码构建**

```bash
swift build -c release
zsh scripts/package-app.sh   # → output/Anchor.app + dmg
open output/Anchor.app
```

需求：macOS 14+，Swift 6.0+，Xcode 16+。开发循环：`open Package.swift`，测试：`swift test`。

发版流程（签名 / 公证 / Sparkle）见 [RELEASING.md](RELEASING.md)。

## License

GPL-3.0。本项目精神继承 [open-vibe-island](https://github.com/Octane0411/open-vibe-island)：**你不应该为监控自己的注意力付订阅费。**

---

<a id="english"></a>

## English (Short Version)

**Anchor** is an open-source macOS focus tool that uses the Dynamic Island as a *gentle tether*, not a jailer.

- **Three-state space**: green (whitelist) / gray (unclassified) / red (blacklist).
- **Drift decay**: when you leave the green zone, friction grows along a smooth curve — not an on/off switch.
- **Three gestures**: tap to snap back · long-press to admit you're slacking (5min legal break) · swipe to pause.
- **Daily recap**: every 22:00 a narrative reflection — not a dashboard wall.
- **Local-first, no account, no telemetry, no subscription. GPL-3.0.**

Full docs (Chinese-first) under [`docs/`](docs/). English translation: work in progress.

> "You shouldn't need to pay a subscription to monitor your own attention." — inspired by [open-vibe-island](https://github.com/Octane0411/open-vibe-island).
