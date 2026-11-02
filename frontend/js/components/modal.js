/**
 * 공통 모달 / 확인 대화상자.
 * - 여러 창이 겹쳐도 맨 위 창만 Esc·바깥 클릭에 반응한다.
 * - 열린 동안 배경 스크롤을 잠그고, 닫으면 열기 전 포커스로 돌아간다.
 */
const stack = [];
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && stack.length) stack.at(-1).close(); });

export function openModal({ title = "", subtitle = "", body = "", footer = "", width = 480, className = "", onClose } = {}) {
  const prev = document.activeElement;
  const el = document.createElement("div");
  el.className = `modal ${className}`;
  el.innerHTML = `
    <div class="modal__box" role="dialog" aria-modal="true" aria-label="${title}" tabindex="-1" style="width:${width}px">
      <div class="modal__head"><div>${subtitle ? `<small>${subtitle}</small>` : ""}<h3>${title}</h3></div>
        <button class="modal__x" data-modal-close aria-label="닫기">×</button></div>
      <div class="modal__body">${body}</div>
      <div class="modal__foot" ${footer ? "" : "hidden"}>${footer}</div>
    </div>`;
  document.body.appendChild(el);
  document.body.classList.add("modal-open");
  requestAnimationFrame(() => el.classList.add("is-open"));

  const m = {
    el,
    body: el.querySelector(".modal__body"),
    foot: el.querySelector(".modal__foot"),
    setBody(html) { m.body.innerHTML = html; },
    setFoot(html) { m.foot.innerHTML = html; m.foot.hidden = !html; },
    close() {
      const i = stack.indexOf(m);
      if (i < 0) return;
      stack.splice(i, 1);
      el.remove();
      if (!stack.length) document.body.classList.remove("modal-open");
      prev?.focus?.();
      onClose?.();
    },
  };
  el.addEventListener("click", (e) => { if (e.target === el || e.target.closest("[data-modal-close]")) m.close(); });
  stack.push(m);
  el.querySelector(".modal__box").focus();
  return m;
}

/** 확인 대화상자 (window.confirm 대체). → Promise<boolean> */
export function confirmDialog({ title, message, confirmText = "확인", danger = false }) {
  return new Promise((resolve) => {
    let ok = false;
    const m = openModal({
      title, width: 400, className: "modal--confirm",
      body: `<p class="confirm__msg">${message}</p>`,
      footer: `<button class="btn--ghost" data-modal-close>취소</button><button class="${danger ? "btn--danger" : "btn--gold"} btn--grow" data-ok>${confirmText}</button>`,
      onClose: () => resolve(ok),
    });
    m.el.querySelector("[data-ok]").addEventListener("click", () => { ok = true; m.close(); });
  });
}
