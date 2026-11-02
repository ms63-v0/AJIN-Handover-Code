/** 상단 헤더: 화면 제목 · (화면별 추가 영역) · 시계 · 화면 설정 · 알림(미해결 알람) · 사용자 메뉴(Figma '사용자 메뉴'). */
import { api } from "../api.js";
import { REFRESH_MS } from "../config.js";
import { icon } from "./icons.js";
import { esc, fmtDateTime } from "../utils.js";
import { openModal, confirmDialog } from "./modal.js";
import { toast } from "./toast.js";
import { openAlarmPopup, ALARM_CHANGED } from "./alarmPopup.js";
import { openSettings } from "../settings.js";
import { session } from "../session.js";

const DAYS = ["일", "월", "화", "수", "목", "금", "토"];
const pad = (n) => String(n).padStart(2, "0");
const nowText = () => {
  const d = new Date();
  return `${d.getFullYear()}. ${pad(d.getMonth() + 1)}. ${pad(d.getDate())} (${DAYS[d.getDay()]}) ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
};
let online = 1;

export function mountHeader(root, { onLogout }) {
  root.innerHTML = `
    <h1 class="header__title"></h1>
    <div class="header__extra"></div>
    <span class="header__spacer"></span>
    <span class="header__date"></span>
    <div class="header__actions">
      <button class="icon-btn" data-act="settings" aria-label="화면 설정" title="화면 설정">${icon("settings")}</button>
      <div class="pop-wrap">
        <button class="icon-btn" data-act="bell" aria-label="알람 (미확인)" title="미확인 알람">${icon("bell")}<span class="bell-badge" hidden></span></button>
        <div class="pop bell-pop" hidden></div>
      </div>
      <span class="header__divider"></span>
      <div class="pop-wrap">
        <button class="user" data-act="user" aria-haspopup="true">
          <span class="user__info"><span class="user__name"></span><span class="user__meta"></span></span>
          <span class="user__avatar">${icon("user")}</span><span class="user__caret">▾</span>
        </button>
        <div class="pop umenu" hidden></div>
      </div>
    </div>`;
  const clock = root.querySelector(".header__date");
  setInterval(() => (clock.textContent = nowText()), 1000);
  clock.textContent = nowText();

  const bellPop = root.querySelector(".bell-pop"), menu = root.querySelector(".umenu"), badge = root.querySelector(".bell-badge");
  const closeAll = () => { bellPop.hidden = true; menu.hidden = true; };

  // ── 알림: 조치가 등록되지 않은 알람 수 + 최근 목록 (주기 갱신)
  let bell = { count: 0, unacked: 0, items: [] };
  const drawBell = () => {
    badge.hidden = !bell.unacked;
    badge.textContent = bell.unacked > 99 ? "99+" : bell.unacked;
    bellPop.innerHTML = `<div class="pop__head"><b>알람</b><span>미확인 ${bell.unacked ?? 0}건 · 미해결 ${bell.count}건</span></div>`
      + (bell.items.length ? bell.items.map((a) => `<button class="bell-item${a.acked ? "" : " is-unacked"}" data-alarm="${a.alarmId}" data-part="${a.partNo ?? ""}">
          <span class="bell-item__cat bell-item__cat--${a.category === "비전" ? "v" : "w"}">${a.category}</span>
          <span class="bell-item__msg">${esc(a.message)}</span><span class="bell-item__time">${fmtDateTime(a.time).slice(5, 16)}</span></button>`).join("")
        : `<div class="pop__empty">${icon("check")} 처리할 알람이 없습니다</div>`)
      + `<a class="pop__more" href="#/alarm" data-close>알람 이력 전체 보기 →</a>`;
  };
  const loadBell = async () => { try { bell = await api.unresolved(); drawBell(); } catch { /* 다음 주기 */ } };
  setInterval(() => { if (!document.hidden && session.user) loadBell(); }, REFRESH_MS);
  window.addEventListener(ALARM_CHANGED, loadBell);
  window.addEventListener("qms:reload", loadBell);

  // ── 사용자 메뉴 (Figma)
  const drawMenu = () => {
    const u = session.user ?? {};
    menu.innerHTML = `
      <div class="umenu__head"><span class="umenu__avatar">${esc((u.name || "?").slice(0, 1))}</span><div><b>${esc(u.name || "")}</b><small>${esc(u.dept || u.role || "")}</small></div></div>
      <div class="umenu__online"><i class="dot dot--ok"></i>현재 ${online}명 접속 중</div>
      <div class="umenu__list">
        <button class="umenu__item" data-act="settings">화면 설정<span class="umenu__hint">이 기기 전용</span></button>
        <button class="umenu__item" data-act="sessions">접속 현황<span class="umenu__badge">${online}</span></button>
        ${u.role === "ADMIN" ? `<button class="umenu__item umenu__item--danger" data-act="reset">LOT 데이터 초기화<span class="umenu__hint">관리자</span></button>` : ""}
      </div>
      <button class="umenu__logout" data-act="logout"><b>로그아웃</b><small>이 기기에서만 로그아웃됩니다</small></button>`;
  };

  const openSessions = async () => {
    const m = openModal({ title: "접속 현황", subtitle: "최근 30분", width: 420, body: `<div class="skel skel--line"></div>` });
    try {
      const r = await api.sessions();
      m.setBody(r.items.length ? `<ul class="sess">${r.items.map((s) => `<li><span class="umenu__avatar umenu__avatar--sm">${esc(s.name.slice(0, 1))}</span>
        <div><b>${esc(s.name)}</b><small>${esc(s.dept || s.role)} · ${esc(s.ip || "-")}</small></div><span class="t-sub">${fmtDateTime(s.time).slice(11, 16)} 로그인</span></li>`).join("")}</ul>`
        : `<div class="msg">최근 30분 안에 로그인한 사용자가 없습니다.</div>`);
    } catch (e) { m.setBody(`<div class="msg msg--error">${esc(e.message)}</div>`); }
  };

  const resetData = async () => {
    const ok = await confirmDialog({ title: "LOT 데이터 초기화", danger: true, confirmText: "초기화",
      message: "LOT·용접·센서·비전·알람·조치 실적 데이터를 모두 삭제합니다.<br>기준정보(라인·설비·레시피·사용자)는 유지됩니다.<br><b>되돌릴 수 없습니다.</b>" });
    if (!ok) return;
    try {
      const r = await api.resetDb();
      toast(`초기화 완료: LOT ${r.deleted.t_lot}건, 알람 ${r.deleted.t_alarm_event}건 삭제`, "ok", 4000);
      window.dispatchEvent(new window.Event("qms:reload"));
    } catch (e) { toast(`초기화 실패: ${e.message}`, "error"); }
  };

  root.addEventListener("click", (e) => {
    const act = e.target.closest("[data-act]")?.dataset.act, al = e.target.closest("[data-alarm]");
    if (al) { closeAll(); return openAlarmPopup(al.dataset.alarm, al.dataset.part || null); }
    if (e.target.closest("[data-close]")) return closeAll();
    if (act === "bell") { const open = bellPop.hidden; closeAll(); bellPop.hidden = !open; if (open) loadBell(); }
    else if (act === "user") { const open = menu.hidden; closeAll(); if (open) { drawMenu(); menu.hidden = false; } }
    else if (act === "settings") { closeAll(); openSettings(); }
    else if (act === "sessions") { closeAll(); openSessions(); }
    else if (act === "reset") { closeAll(); resetData(); }
    else if (act === "logout") { closeAll(); onLogout(); }
  });
  document.addEventListener("click", (e) => { if (!e.target.closest(".pop-wrap")) closeAll(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeAll(); });
  return { loadBell };
}

/** 로그인한 사용자 표시: 이름 / 소속 · 접속 중 N명 */
export function setHeaderUser(root, user, n) {
  online = n;
  root.querySelector(".user__name").textContent = user.name;
  root.querySelector(".user__meta").textContent = `${user.dept || user.role} · 접속 중 ${n}명`;
}

/** 화면 이동 시 제목 교체 + 추가 영역(파트 탭 등)을 새 요소로 교체 (이전 화면 리스너 제거) */
export function setHeaderTitle(root, title) {
  root.querySelector(".header__title").textContent = title;
  const old = root.querySelector(".header__extra");
  old.replaceWith(old.cloneNode(false));
  document.title = `${title} · AJIN QMS`;
}

export const headerExtra = () => document.querySelector(".header__extra");