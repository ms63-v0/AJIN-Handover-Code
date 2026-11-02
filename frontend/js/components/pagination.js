/**
 * 페이지네이션 컴포넌트 (서버사이드 오프셋 방식).
 * 대기업 MES/QMS 표준: 페이지당 건수 선택(20·50·100) + 번호 윈도우(5개) + 처음/끝 이동.
 */

export const PER_PAGE_OPTIONS = [20, 50, 100];

/**
 * 페이지네이션 HTML 반환.
 * @param {{ total: number, page: number, perPage: number }} p
 */
export function paginationHtml({ total, page, perPage }) {
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  if (total === 0) return "";

  const btn = (p, label, active = false, disabled = false) =>
    `<button class="pg__btn${active ? " is-active" : ""}${disabled ? " is-disabled" : ""}" data-pg-page="${p}" ${disabled ? "disabled" : ""}>${label}</button>`;

  // 번호 윈도우 (최대 5개, 양쪽 말줄임 포함)
  const WIN = 5;
  let s = Math.max(1, page - Math.floor(WIN / 2));
  let e = Math.min(totalPages, s + WIN - 1);
  if (e - s < WIN - 1) s = Math.max(1, e - WIN + 1);

  const nums = [];
  if (s > 1) { nums.push(btn(1, "1")); if (s > 2) nums.push(`<span class="pg__gap">…</span>`); }
  for (let i = s; i <= e; i++) nums.push(btn(i, i, i === page));
  if (e < totalPages) { if (e < totalPages - 1) nums.push(`<span class="pg__gap">…</span>`); nums.push(btn(totalPages, totalPages)); }

  const perSel = `<select class="pg__per" data-pg-per aria-label="페이지당 건수">
    ${PER_PAGE_OPTIONS.map((n) => `<option value="${n}"${n === perPage ? " selected" : ""}>${n}건</option>`).join("")}
  </select>`;

  return `<div class="pg" role="navigation" aria-label="페이지 탐색">
    <span class="pg__info">총 <b>${total.toLocaleString("ko-KR")}</b>건</span>
    ${perSel}
    <div class="pg__nav">
      ${btn(1, "◀◀", false, page === 1)}
      ${btn(page - 1, "◀", false, page === 1)}
      ${nums.join("")}
      ${btn(page + 1, "▶", false, page === totalPages)}
      ${btn(totalPages, "▶▶", false, page === totalPages)}
    </div>
  </div>`;
}

/**
 * 페이지네이션 이벤트 바인딩 (이벤트 위임).
 * @param {Element} root  이벤트를 붙일 상위 요소
 * @param {{ onPage: (n: number) => void, onPerPage: (n: number) => void }} handlers
 */
export function bindPagination(root, { onPage, onPerPage }) {
  root.addEventListener("click", (e) => {
    const b = e.target.closest("[data-pg-page]");
    if (b && !b.disabled) onPage(Number(b.dataset.pgPage));
  });
  root.addEventListener("change", (e) => {
    const sel = e.target.closest("[data-pg-per]");
    if (sel) onPerPage(Number(sel.value));
  });
}
