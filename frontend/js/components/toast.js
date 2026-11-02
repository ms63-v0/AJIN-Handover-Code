/** 화면 오른쪽 아래 알림 메시지 (window.alert 대체). type: info / ok / warn / error */
let box;
export function toast(message, type = "info", ms = 3000) {
  if (!box || !box.isConnected) {
    box = document.createElement("div");
    box.className = "toasts";
    box.setAttribute("aria-live", "polite");
    document.body.appendChild(box);
  }
  const t = document.createElement("div");
  t.className = `toast toast--${type}`;
  t.textContent = message;
  box.appendChild(t);
  setTimeout(() => { t.classList.add("is-out"); setTimeout(() => t.remove(), 300); }, ms);
}
