/**
 * DOM 갱신 유틸 — 값이 바뀐 부분만 건드려서 깜빡임·스크롤 초기화·이미지 재로딩을 막는다.
 *  setHtml  : 이전과 같은 HTML이면 아무것도 하지 않음. 다르면 스크롤 위치를 보존하며 교체.
 *  syncList : 키(LOT·검사 ID·알람 ID 등)로 항목을 맞춤. 바뀐 항목만 교체, 새 항목만 추가, 없어진 항목만 제거.
 *             화면이 이미 한 번 그려진 뒤에 새로 생긴 항목에만 data-fresh 를 붙인다 (알람 강조 애니메이션용).
 *             첫 로딩 때 이미 있던 항목은 강조하지 않는다.
 */
const SCROLL_SEL = ".wtable, .table-wrap, .stack, .vgrid";

function keepScroll(el, fn) {
  const selfTop = el.scrollTop;
  const before = [...el.querySelectorAll(SCROLL_SEL)].map((n) => n.scrollTop);
  fn();
  el.scrollTop = selfTop;
  [...el.querySelectorAll(SCROLL_SEL)].forEach((n, i) => { if (before[i]) n.scrollTop = before[i]; });
}

export function setHtml(el, html) {
  if (!el || el.dataset.sig === html) return;
  el.dataset.sig = html;
  keepScroll(el, () => { el.innerHTML = html; });
}

export function syncList(parent, items, keyOf, render, emptyHtml = "") {
  const tmpl = document.createElement("template");
  const make = (html) => { tmpl.innerHTML = html.trim(); return tmpl.content.firstElementChild; };
  const ready = parent.dataset.ready === "1";

  const keyed = new Map(), stray = [];
  for (const c of [...parent.children]) {
    if (c.dataset.key == null || keyed.has(c.dataset.key)) stray.push(c);
    else keyed.set(c.dataset.key, c);
  }
  stray.forEach((c) => c.remove());
  parent.dataset.ready = "1";

  if (!items.length) {
    keyed.forEach((c) => c.remove());
    if (emptyHtml && parent.dataset.sig !== emptyHtml) {
      parent.dataset.sig = emptyHtml;
      parent.append(make(emptyHtml));
    }
    return;
  }
  parent.dataset.sig = "";

  let prev = null;
  const seen = new Set();
  for (const it of items) {
    const k = String(keyOf(it)), html = render(it);
    seen.add(k);
    let el = keyed.get(k);
    if (!el || el.dataset.sig !== html) {
      const isNewKey = !el;
      const next = make(html);
      next.dataset.key = k;
      next.dataset.sig = html;
      if (isNewKey && ready) next.dataset.fresh = "1";   // 새로 생긴 항목만 강조
      if (el) el.replaceWith(next);
      el = next;
      keyed.set(k, el);
    }
    const expected = prev ? prev.nextElementSibling : parent.firstElementChild;
    if (expected !== el) parent.insertBefore(el, expected);
    prev = el;
  }
  keyed.forEach((c, k) => { if (!seen.has(k)) c.remove(); });
}