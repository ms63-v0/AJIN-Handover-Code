/** 좌측 사이드바: 메뉴(config.NAV_ITEMS) + 공정 연결 상태(용접부위별 최근 실적 수신 여부, 주기 갱신). */
import { api } from "../api.js";
import { NAV_ITEMS, REFRESH_MS } from "../config.js";
import { icon } from "./icons.js";

export function mountSidebar(root, user) {
  const isAdmin = user?.role === "ADMIN";
  const items = NAV_ITEMS.filter((n) => !n.adminOnly || isAdmin);
  root.innerHTML = `
    <div class="logo"><span class="logo__mark">A</span>AJIN<small>QMS</small></div>
    <nav class="nav-list">
      ${items.map((n) => `<a class="nav" href="#/${n.id}" data-nav="${n.id}" title="${n.label}">${icon(n.icon)}<span>${n.label}</span></a>`).join("")}
    </nav>
    <div class="sidebar__spacer">
      <div class="dbtest">
        <p class="dbtest__title">POP DB</p>
        <p class="dbtest__pending">DB 연결 대기 중</p>
      </div>
    </div>
    <div class="sidebar__bottom">
      <div class="conn"><div class="conn__title"><span class="conn__dot"></span>공정 연결 상태</div><p class="conn__text">확인 중…</p></div>
      <p class="version">AJIN QMS v1.1.0</p>
    </div>`;

  const dot = root.querySelector(".conn__dot"), text = root.querySelector(".conn__text");
  const load = async () => {
    if (document.hidden || root.closest("[hidden]")) return;
    try {
      const { parts } = await api.status();
      const on = parts.filter((p) => p.connected).map((p) => `${p.partNo}번`), off = parts.filter((p) => !p.connected).map((p) => `${p.partNo}번`);
      dot.className = `conn__dot ${!on.length ? "is-off" : off.length ? "is-warn" : "is-on"}`;
      text.textContent = !parts.length ? "등록된 용접부위 없음" : !on.length ? "최근 수집 데이터 없음 (수집기 확인)"
        : `${on.join(", ")} 파트 연결 됨${off.length ? ` / ${off.join(", ")} 대기` : ""}`;
    } catch { dot.className = "conn__dot is-err"; text.textContent = "서버 연결 끊김"; }
  };
    const showDb = async () => {
    const el = root.querySelector(".dbtest__pending");
    try {
      const rows = await api.lines();
      const row = rows.find((r) => r.line_code === "TEST_1st");
      el.textContent = row ? `DB 값: ${row.line_name}` : "DB 연결됨 (테스트 행 없음)";
    } catch {
      el.textContent = "DB 연결 실패";
    }
  };
  showDb();
  load();
  setInterval(load, REFRESH_MS);
  window.addEventListener("qms:reload", load);
}

export function setActiveNav(root, id) {
  root.querySelectorAll("[data-nav]").forEach((a) => a.classList.toggle("is-active", a.dataset.nav === id));
}