# AnchorExtension

浏览器扩展源代码目录。**不是 Swift target**，由 npm/web 工具链构建。

## 计划支持

- v1: Chrome（Manifest v3，PR #17）
- v1.1: Safari（macOS App Extension）
- v1.1: Firefox（WebExtension API）

## 结构

```
chrome/
  manifest.json        Manifest v3
  service_worker.js    tabs/windows 监听 + 心跳 + 指令分发（ES module）
  socket_client.js     WebSocket 连接管理 + 指数退避重连
  content_script.js    页面灰色遮罩（friction overlay）
  options.html/js      端口配置 + 连接状态
safari/  (v1.1)
firefox/ (v1.1)
shared/  共享 JS 工具
```

## 安装（开发态，load unpacked）

1. Chrome 打开 `chrome://extensions`
2. 右上角打开「开发者模式」
3. 「加载已解压的扩展程序」→ 选 `Sources/AnchorExtension/chrome/`
4. Anchor app 运行后会自动连上；连接状态见扩展的「选项」页

## 协议（与 §IV 的差异说明）

`docs/technical-architecture.md` §IV 描述的是 Unix Domain Socket。但 **Chrome MV3 扩展拿不到
raw socket API**，只能用 WebSocket，所以浏览器这一端实际走 `ws://127.0.0.1:<port>`（默认 17604），
daemon 需要监听一个本机 WebSocket（见 PR #18 runtime 任务）。**消息体 JSON 格式与 §IV 完全一致**，
且与 `AnchorDaemon.BrowserProtocol` 的编解码对齐（已单测）。未知 type 一律忽略，保持向后兼容。
