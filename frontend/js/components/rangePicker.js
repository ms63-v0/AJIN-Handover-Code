/**
 * 조회 기간 선택 (시작 일시 ~ 종료 일시)
 *
 * range 값 형태
 *   · 빠른 선택: { preset: "today" | "1h" | "8h" | "24h" | "yesterday" | "7d" }
 *       → 조회할 때마다 현재 시각 기준으로 다시 계산 (예: '오늘'은 00:00이 지나면 자동으로 새 날짜)
 *   · 직접 입력: { from: "YYYY-MM-DDTHH:MM", to: "YYYY-MM-DDTHH:MM" | null, live: boolean }
 *       → live = true 이면 종료는 '현재 시각까지'(실시간 갱신)
 *
 * API 로는 rangeParams(range) = { from: "YYYY-MM-DD HH:MM", to?: "YYYY-MM-DD HH:MM" } 를 보낸다(to 생략 = 현재까지).
 */
import { icon } from "./icons.js";
import { esc } from "../utils.js";

const pad = (n) => String(n).padStart(2, "0");
const local = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
const apiFmt = (d) => local(d).replace("T", " ");
const short = (d) => `${pad(d.getMonth() + 1)}.${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
const day0 = (offset = 0) => { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + offset); return d; };
const ago = (ms) => new Date(Date.now() - ms);

export const PRESETS = {
  today: { label: "오늘", live: true, calc: () => ({ from: day0() }) },
  "1h": { label: "최근 1시간", live: true, calc: () => ({ from: ago(3600e3) }) },
  "8h": { label: "최근 8시간", live: true, calc: () => ({ from: ago(8 * 3600e3) }) },
  "24h": { label: "최근 24시간", live: true, calc: () => ({ from: ago(24 * 3600e3) }) },
  yesterday: { label: "어제", live: false, calc: () => ({ from: day0(-1), to: new Date(day0().getTime() - 60e3) }) },
  "7d": { label: "최근 7일", live: true, calc: () => ({ from: day0(-6) }) },   // 오늘 포함 7일 (00:00 기준)
};

export const defaultRange = () => ({ preset: "today" });

/** range → { from: Date, to: Date | null, live } */
export function resolveRange(r) {
  if (r?.preset && PRESETS[r.preset]) {
    const p = PRESETS[r.preset], v = p.calc();
    return { from: v.from, to: v.to ?? null, live: p.live };
  }
  return { from: new Date(r.from), to: r.live ? null : new Date(r.to), live: !!r.live };
}

export const isLiveRange = (r) => resolveRange(r).live;

export function rangeParams(r) {
  const v = resolveRange(r);
  return { from: apiFmt(v.from), to: v.to ? apiFmt(v.to) : undefined };
}

export function rangeLabel(r) {
  const v = resolveRange(r), body = `${short(v.from)} ~ ${v.live ? "현재" : short(v.to)}`;
  return r?.preset ? `${PRESETS[r.preset].label} · ${body}` : body;
}

/** 필터 바에 들어가는 기간 칩 (누르면 openRangePicker) */
export const rangeChip = (r) =>
  `<button type="button" class="chip chip--range" data-range title="조회 기간 변경">${icon("calendar")}<span class="chip--range__txt">${esc(rangeLabel(r))}</span><span class="chip--range__caret">▾</span></button>`;

let openPop = null;

/** 기간 선택 팝오버. onApply(newRange) 는 '적용' 또는 빠른 선택 시 호출 */
export function openRangePicker(anchor, r, onApply, { maxDays = 31, title = "조회 기간" } = {}) {
  openPop?.close();
  const cur = resolveRange(r);
  const el = document.createElement("div");
  el.className = "rpop";
  el.setAttribute("role", "dialog");
  el.innerHTML = `
    <div class="rpop__head"><b>${esc(title)}</b><small>최대 ${maxDays}일</small></div>
    <div class="rpop__presets">${Object.entries(PRESETS).map(([k, p]) =>
      `<button type="button" class="rpop__preset ${r?.preset === k ? "is-on" : ""}" data-preset="${k}">${p.label}</button>`).join("")}</div>
    <div class="rpop__custom">
      <label>시작 일시<input type="datetime-local" name="rp-from" step="60" value="${local(cur.from)}" max="${local(new Date())}"></label>
      <label>종료 일시<input type="datetime-local" name="rp-to" step="60" value="${local(cur.to ?? new Date())}" ${cur.live ? "disabled" : ""}></label>
      <label class="rpop__live"><input type="checkbox" name="rp-live" ${cur.live ? "checked" : ""}>종료 = 현재 시각까지 (실시간 갱신)</label>
      <p class="rpop__err" role="alert"></p>
    </div>
    <div class="rpop__foot"><button type="button" class="btn--ghost" data-rp="cancel">취소</button><button type="button" class="btn--gold" data-rp="apply">적용</button></div>`;
  document.body.appendChild(el);

  // 위치: 칩 바로 아래 (화면 밖으로 나가지 않게)
  const a = anchor.getBoundingClientRect(), w = 340;
  el.style.top = `${Math.round(a.bottom + 6)}px`;
  el.style.left = `${Math.round(Math.max(8, Math.min(a.left, window.innerWidth - w - 8)))}px`;

  const $ = (n) => el.querySelector(`[name="${n}"]`), err = el.querySelector(".rpop__err");
  const close = () => { el.remove(); document.removeEventListener("mousedown", outside, true); document.removeEventListener("keydown", onKey); openPop = null; };
  const outside = (e) => { if (!el.contains(e.target) && !anchor.contains(e.target)) close(); };
  const onKey = (e) => { if (e.key === "Escape") close(); };
  document.addEventListener("mousedown", outside, true);
  document.addEventListener("keydown", onKey);
  openPop = { close };

  const apply = () => {
    const from = $("rp-from").value, live = $("rp-live").checked, to = $("rp-to").value;
    const f = new Date(from), t = live ? new Date() : new Date(to);
    if (!from || isNaN(f)) return (err.textContent = "시작 일시를 입력하세요.");
    if (!live && (!to || isNaN(t))) return (err.textContent = "종료 일시를 입력하세요.");
    if (f > new Date()) return (err.textContent = "시작 일시가 현재보다 늦습니다.");
    if (t <= f) return (err.textContent = "종료 일시는 시작 일시보다 뒤여야 합니다.");
    if (t - f > maxDays * 86400e3 + 60e3) return (err.textContent = `조회 기간은 최대 ${maxDays}일까지 가능합니다.`);
    close();
    onApply({ from, to: live ? null : to, live });
  };
  el.addEventListener("click", (e) => {
    const p = e.target.closest("[data-preset]"), act = e.target.closest("[data-rp]")?.dataset.rp;
    if (p) { close(); onApply({ preset: p.dataset.preset }); }
    else if (act === "cancel") close();
    else if (act === "apply") apply();
  });
  el.addEventListener("change", (e) => {
    if (e.target.name === "rp-live") $("rp-to").disabled = e.target.checked;
    err.textContent = "";
  });
  el.addEventListener("keydown", (e) => { if (e.key === "Enter") apply(); });
  $("rp-from").focus();
  return { close };
}
