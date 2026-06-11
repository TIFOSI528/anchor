// WebSocket 客户端：连接本机 Anchor daemon，带指数退避重连。
//
// 注意（设计说明）：technical-architecture §IV 写的是 Unix Domain Socket，但 Chrome MV3
// 扩展拿不到 raw socket API，只能用 WebSocket。所以浏览器这一端走 ws://127.0.0.1:<port>，
// daemon 需要监听一个本机 WebSocket（见 PR #18 runtime 任务）。消息体 JSON 格式不变。

export const DEFAULT_PORT = 17604;
export const HEARTBEAT_ALARM = "anchor-heartbeat";

export class AnchorSocket {
  constructor({ onCommand, onStatus } = {}) {
    this.ws = null;
    this.port = DEFAULT_PORT;
    this.backoff = 1000;
    this.maxBackoff = 30000;
    this.connected = false;
    this.onCommand = onCommand || (() => {});
    this.onStatus = onStatus || (() => {});
  }

  async loadPort() {
    try {
      const { anchorPort } = await chrome.storage.local.get("anchorPort");
      if (anchorPort) this.port = anchorPort;
    } catch (_) {
      // storage 不可用时用默认端口
    }
  }

  connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    try {
      this.ws = new WebSocket(`ws://127.0.0.1:${this.port}`);
    } catch (_) {
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.connected = true;
      this.backoff = 1000;
      this.onStatus("connected");
      this.send({ type: "hello", browser: "chrome", version: chrome.runtime.getManifest().version });
    };

    this.ws.onmessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch (_) {
        return; // 非法 JSON：静默忽略
      }
      this.onCommand(message);
    };

    this.ws.onclose = () => {
      this.connected = false;
      this.onStatus("disconnected");
      this.scheduleReconnect();
    };

    // daemon 不可用时不能让浏览器卡顿——出错就关掉，靠重连兜底。
    this.ws.onerror = () => {
      try { this.ws.close(); } catch (_) {}
    };
  }

  scheduleReconnect() {
    const delay = this.backoff;
    this.backoff = Math.min(this.backoff * 2, this.maxBackoff);
    setTimeout(() => this.connect(), delay);
  }

  send(object) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try {
        this.ws.send(JSON.stringify(object));
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
