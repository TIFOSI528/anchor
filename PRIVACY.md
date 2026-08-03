# Anchor 隐私说明

> 一句话：**Anchor 记录的一切都留在你自己的电脑上。** 没有账号，没有服务器，没有遥测。
> 下面是逐项的实话——包括唯一一次会联网的情况。

中文 · [English](#english)

## 记录了什么

| 数据 | 内容 | 存在哪 |
|---|---|---|
| 应用切换 | 时间点、应用 bundle id、应用名 | 本机 SQLite |
| 网址 | **仅** scheme + 域名 + 路径 | 本机 SQLite |
| 每日统计 | 绿/灰/红区秒数、漂移次数、Deep Score | 本机 SQLite |
| 场景规则 | 你自己配的绿区/红区名单 | 本机 SQLite |
| 暂停理由 | 你输入的文字 | 仅内存，不落盘 |

数据库位置：`~/Library/Application Support/Anchor/anchor.sqlite`（权限 `0600`，仅你本人可读；所在目录 `0700`）。

## 明确**不**记录什么

- **网址的 `?` 之后与 `#` 之后一律丢弃**，在写入磁盘**之前**就被切掉。
  搜索关键词、分享令牌、会话参数、重置密码链接都不会落盘。
  （从旧版本升级时，数据库里已有的记录会被就地清理并 `VACUUM`。）
- `data:` / `blob:` / `file:` / `view-source:` 地址不上报、不记录。
- 不记录页面标题、页面内容、截图、按键、剪贴板。
- 不记录你的姓名、邮箱、设备标识符——因为压根没有账号系统。

## 网络行为

Anchor 只有**一处**会联网，且默认关闭：

| 行为 | 何时发生 | 发出了什么 | 默认 |
|---|---|---|---|
| 检查更新（Sparkle） | 你点「检查更新」，或开启「自动检查更新」后 | 向 `raw.githubusercontent.com` 发一个 HTTPS 请求，附带 `Anchor/<版本> Sparkle/<版本>` 的 User-Agent。这会让 GitHub 得知你的 **IP 地址、Anchor 版本与访问时间** | **关** |

除此之外没有任何出网请求：没有分析 SDK，没有崩溃上报，没有「匿名统计」。
系统配置信息（Sparkle 的 system profiling）**未启用**。

不想让它联网：把设置里的「自动检查更新」保持关闭，不点「检查更新」即可；
或者用防火墙拦掉 Anchor。功能完全不受影响——Anchor 在飞机上可以正常工作。

## 浏览器扩展

扩展只做一件事：把**当前活动标签页的地址**发给本机的 Anchor。

- 只连 `ws://127.0.0.1:17604`（回环地址，不出本机，也不进局域网）。
- 只在**浏览器扩展来源**（`chrome-extension://…`）才被接受：
  普通网页即使利用「浏览器信任 localhost」的规则来连，握手阶段就会被拒。
- 扩展不读页面内容、不注入脚本到页面数据流，只在深度漂移时叠一层不拦点击的半透明遮罩。

## 你对数据的控制权

设置 → **隐私与数据**：

- **导出**：一键导出全部数据为 JSON（可以自己检查到底记了什么，也可用于换机迁移）。
- **清除全部历史**：永久删除所有时段、漂移与复盘记录；你配好的场景规则会保留。
- **保留时长**：默认自动删除 90 天前的记录，可改 30 / 365 天或「永久保留」。

想彻底移除：把 Anchor 拖进废纸篓，然后删除
`~/Library/Application Support/Anchor/` 与 `~/Library/Preferences/com.anchor.app.plist`。

## 怎么核实以上说法

代码是 GPL-3.0 开源的，这些声明都可以自己验证：

- URL 脱敏：`Sources/AnchorCore/Session/SessionStore.swift` 的 `sanitizeURLForStorage`
  （测试见 `Tests/AnchorCoreTests/PolishRegressionTests.swift`）
- 数据库权限：同文件的 `restrictPermissions`
- 握手来源校验：`Sources/AnchorDaemon/SocketServer.swift` 的 `isAcceptableOrigin`
- 全仓库搜一遍 `URLSession` / `http`：除 Sparkle 外没有任何网络代码

发现与本文不一致的地方，请开 issue——这属于 bug。

---

<a name="english"></a>

# Anchor Privacy Statement

> In one line: **everything Anchor records stays on your own Mac.** No account, no server,
> no telemetry. Below is the itemised truth — including the one case where it does touch the network.

## What is recorded

| Data | Content | Stored where |
|---|---|---|
| App switches | Timestamp, bundle id, app name | Local SQLite |
| URLs | **Only** scheme + host + path | Local SQLite |
| Daily stats | Green/gray/red seconds, drift count, Deep Score | Local SQLite |
| Scene rules | The allow/block lists you configure | Local SQLite |
| Pause reason | The text you type | Memory only, never written |

Database: `~/Library/Application Support/Anchor/anchor.sqlite`, mode `0600` (owner-only),
in a `0700` directory.

## What is explicitly **not** recorded

- **Everything after `?` and `#` in a URL is discarded** — stripped *before* it reaches disk.
  Search terms, share tokens, session parameters and password-reset links never land in the database.
  (Upgrading from an older version cleans existing rows in place and runs `VACUUM`.)
- `data:` / `blob:` / `file:` / `view-source:` URLs are neither reported nor stored.
- No page titles, page content, screenshots, keystrokes or clipboard.
- No name, email or device identifier — there is no account system at all.

## Network behaviour

Anchor makes exactly **one** kind of network request, and it is off by default:

| Action | When | What it discloses | Default |
|---|---|---|---|
| Update check (Sparkle) | You click "Check for Updates", or enable automatic checks | An HTTPS request to `raw.githubusercontent.com` with a `Anchor/<version> Sparkle/<version>` User-Agent. GitHub therefore learns your **IP address, Anchor version and the time** | **Off** |

Nothing else leaves the machine: no analytics SDK, no crash reporting, no "anonymous stats".
Sparkle's system profiling is **not** enabled.

To keep it fully offline, leave automatic update checks off and don't click "Check for Updates",
or block Anchor in your firewall. Functionality is unaffected — Anchor works on a plane.

## Browser extension

The extension does one thing: send the **active tab's address** to Anchor on your machine.

- It only connects to `ws://127.0.0.1:17604` (loopback — never leaves the machine, never the LAN).
- Only **browser-extension origins** (`chrome-extension://…`) are accepted. An ordinary web page
  that tries to exploit the browser's "localhost is trustworthy" rule is rejected at the handshake.
- It does not read page content and does not inject anything into the page's data flow — only a
  click-through translucent overlay during deep drift.

## Your control over the data

Settings → **Privacy & Data**:

- **Export** all data as JSON (inspect exactly what was recorded, or migrate machines).
- **Erase all history** — permanently deletes sessions, drifts and recaps. Your scene rules are kept.
- **Retention** — deletes records older than 90 days by default; choose 30/365 days or "keep forever".

To remove Anchor completely: move the app to the Trash, then delete
`~/Library/Application Support/Anchor/` and `~/Library/Preferences/com.anchor.app.plist`.

## How to verify the above

The code is GPL-3.0, so every claim here is checkable:

- URL sanitisation: `sanitizeURLForStorage` in `Sources/AnchorCore/Session/SessionStore.swift`
  (tests in `Tests/AnchorCoreTests/PolishRegressionTests.swift`)
- File permissions: `restrictPermissions` in the same file
- Handshake origin check: `isAcceptableOrigin` in `Sources/AnchorDaemon/SocketServer.swift`
- Grep the repo for `URLSession` / `http`: there is no network code outside Sparkle

If you find anything that contradicts this document, please open an issue — that is a bug.
