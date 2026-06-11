// Anchor Chrome 扩展 service worker。
// 监听 active tab 变化 → 推给 daemon；接收 daemon 指令 → navigate / friction overlay。

import { AnchorSocket, HEARTBEAT_ALARM } from "./socket_client.js";

const socket = new AnchorSocket({
  onCommand: handleCommand,
  onStatus: (status) => chrome.storage.local.set({ anchorStatus: status }),
});

init();

async function init() {
  await socket.loadPort();
  socket.connect();
  // MV3 service worker 会被回收；用 alarms（最小 30s）做心跳 + 重连兜底。
  chrome.alarms.create(HEARTBEAT_ALARM, { periodInMinutes: 0.5 });
}

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

async function reportActiveTab() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (!tab || !tab.url) return;
    socket.send({
      type: "tab_active",
      browser: "chrome",
      url: tab.url,
      window_id: tab.windowId,
      tab_id: tab.id,
      timestamp: nowSeconds(),
    });
  } catch (_) {
    // tab 不可读（如 chrome:// 受限页面）：忽略
  }
}

chrome.tabs.onActivated.addListener(reportActiveTab);

chrome.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
  if ((changeInfo.status === "complete" || changeInfo.url) && tab && tab.active) {
    reportActiveTab();
  }
});

chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    socket.send({ type: "browser_blurred", browser: "chrome", timestamp: nowSeconds() });
  } else {
    reportActiveTab();
  }
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== HEARTBEAT_ALARM) return;
  if (socket.connected) {
    socket.send({ type: "heartbeat", browser: "chrome" });
  } else {
    socket.connect();
  }
});

chrome.runtime.onStartup.addListener(() => socket.connect());
chrome.runtime.onInstalled.addListener(() => socket.connect());

async function handleCommand(message) {
  if (!message || typeof message.type !== "string") return;
  switch (message.type) {
    case "navigate":
      if (message.url) {
        const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
        if (tab) chrome.tabs.update(tab.id, { url: message.url });
      }
      break;
    case "friction_overlay":
      sendToActiveTab({ kind: "overlay", level: typeof message.level === "number" ? message.level : 0.5 });
      break;
    case "friction_clear":
      sendToActiveTab({ kind: "clear" });
      break;
    default:
      break; // 未知指令：向后兼容，忽略
  }
}

async function sendToActiveTab(payload) {
  try {
    const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (tab) chrome.tabs.sendMessage(tab.id, payload).catch(() => {});
  } catch (_) {
    // 无活跃 tab：忽略
  }
}
