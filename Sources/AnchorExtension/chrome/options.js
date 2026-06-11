const DEFAULT_PORT = 17604;

const portInput = document.getElementById("port");
const statusEl = document.getElementById("status");
const saveButton = document.getElementById("save");

async function load() {
  const { anchorPort, anchorStatus } = await chrome.storage.local.get(["anchorPort", "anchorStatus"]);
  portInput.value = anchorPort || DEFAULT_PORT;
  renderStatus(anchorStatus);
}

function renderStatus(status) {
  const connected = status === "connected";
  statusEl.textContent = connected ? "已连接" : "未连接";
  statusEl.className = connected ? "ok" : "off";
}

saveButton.addEventListener("click", async () => {
  const port = parseInt(portInput.value, 10);
  if (port >= 1 && port <= 65535) {
    await chrome.storage.local.set({ anchorPort: port });
    saveButton.textContent = "已保存 ✓";
    setTimeout(() => { saveButton.textContent = "保存"; }, 1500);
  }
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.anchorStatus) renderStatus(changes.anchorStatus.newValue);
});

load();
