// 接收 service worker 指令，在页面上叠加 / 移除灰色遮罩，与系统级 FrictionFog 协同。
// 遮罩 pointerEvents:none，不拦截点击——friction 是"让你注意到"，不是"锁死页面"。

let overlay = null;

function ensureOverlay() {
  if (overlay) return overlay;
  overlay = document.createElement("div");
  overlay.id = "__anchor_friction_overlay__";
  Object.assign(overlay.style, {
    position: "fixed",
    inset: "0",
    zIndex: "2147483647",
    background: "rgba(120, 120, 120, 0)",
    backdropFilter: "blur(0px)",
    webkitBackdropFilter: "blur(0px)",
    pointerEvents: "none",
    transition: "background 200ms ease, backdrop-filter 200ms ease",
  });
  document.documentElement.appendChild(overlay);
  return overlay;
}

chrome.runtime.onMessage.addListener((message) => {
  if (!message || !message.kind) return;

  if (message.kind === "overlay") {
    const element = ensureOverlay();
    const level = Math.max(0, Math.min(1, Number(message.level) || 0));
    element.style.background = `rgba(120, 120, 120, ${0.35 * level})`;
    const blur = `blur(${Math.round(16 * level)}px)`;
    element.style.backdropFilter = blur;
    element.style.webkitBackdropFilter = blur;
  } else if (message.kind === "clear" && overlay) {
    overlay.style.background = "rgba(120, 120, 120, 0)";
    overlay.style.backdropFilter = "blur(0px)";
    overlay.style.webkitBackdropFilter = "blur(0px)";
  }
});
