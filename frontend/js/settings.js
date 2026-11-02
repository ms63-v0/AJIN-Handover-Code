/**
 * 화면 설정 (Figma '화면 설정'): 이 브라우저(localStorage)에만 저장되고 다른 접속자에게는 영향 없음.
 *  - 화면 테마: 라이트 / 다크 / 시스템
 *  - 기본 보기(용접 현황·비전 검사): 그래프 / 표(이미지)
 *  - 시간 간격 기본값(용접 현황 표): 5분 / 10분 구간
 *  - 필터 선택 기억: 다음 접속 때 마지막 필터 유지 (날짜는 항상 오늘)
 */
import { openModal } from "./components/modal.js";
import { toast } from "./components/toast.js";

const KEY = "qms.settings";
const DEFAULTS = { theme: "light", defaultView: "chart", interval: 5, rememberFilters: true };

const read = (k, d) => { try { return { ...d, ...JSON.parse(localStorage.getItem(k) || "{}") }; } catch { return { ...d }; } };
const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* 저장 불가(사생활 모드 등) */ } };

export const settings = read(KEY, DEFAULTS);

/** 테마 적용: html[data-theme] 로 tokens.css / theme.css 의 색 변수가 바뀐다 */
export function applyTheme() {
  const sys = window.matchMedia?.("(prefers-color-scheme: dark)").matches;
  document.documentElement.dataset.theme = settings.theme === "dark" || (settings.theme === "system" && sys) ? "dark" : "light";
}
window.matchMedia?.("(prefers-color-scheme: dark)").addEventListener?.("change", applyTheme);

/** 필터 기억: 화면별 마지막 필터 읽기/저장 */
export const loadFilters = (page, defaults) => (settings.rememberFilters ? read(`qms.filters.${page}`, defaults) : { ...defaults });
export const saveFilters = (page, obj) => { if (settings.rememberFilters) write(`qms.filters.${page}`, obj); };

const seg = (key, opts) => `<div class="segctl" data-key="${key}">${opts.map(([v, l]) =>
  `<button type="button" class="${String(settings[key]) === String(v) ? "is-on" : ""}" data-v="${v}">${l}</button>`).join("")}</div>`;

export function openSettings() {
  const m = openModal({ title: "화면 설정", subtitle: "설정", width: 440, className: "modal--settings" });
  const draw = () => m.setBody(`
    <div class="note-box"><b>ⓘ 이 기기에만 적용됩니다</b><p>하나의 계정을 함께 쓰기 때문에 설정은 이 브라우저에만 저장되고, 다른 접속자에게는 영향이 없어요.</p></div>
    <div class="set-row"><div class="set-row__head"><b>화면 테마</b></div>${seg("theme", [["light", "라이트"], ["dark", "다크"], ["system", "시스템"]])}</div>
    <div class="set-row"><div class="set-row__head"><b>기본 보기</b><small>용접 현황 · 비전 검사</small></div>${seg("defaultView", [["chart", "그래프"], ["table", "표"]])}</div>
    <div class="set-row"><div class="set-row__head"><b>시간 간격 기본값</b><small>용접 현황 표</small></div>${seg("interval", [[5, "5분"], [10, "10분"]])}</div>
    <div class="set-row set-row--toggle"><div><b>필터 선택 기억</b><small>다음 접속 때 마지막 필터를 유지합니다</small></div>
      <button class="switch ${settings.rememberFilters ? "is-on" : ""}" data-toggle="rememberFilters" role="switch" aria-checked="${settings.rememberFilters}"><i></i></button></div>
    <button class="btn--ghost btn--block" data-reset>기본값으로 되돌리기</button>
    <p class="set-foot">변경 즉시 이 기기에 저장됩니다</p>`);
  const changed = () => { write(KEY, settings); applyTheme(); draw(); window.dispatchEvent(new window.Event("qms:reload")); window.dispatchEvent(new window.Event("qms:theme")); };
  m.body.addEventListener("click", (e) => {
    const b = e.target.closest(".segctl button"), t = e.target.closest("[data-toggle]");
    if (b) { const k = b.parentElement.dataset.key; settings[k] = k === "interval" ? Number(b.dataset.v) : b.dataset.v; changed(); }
    else if (t) {
      settings.rememberFilters = !settings.rememberFilters;
      if (!settings.rememberFilters) Object.keys(localStorage).filter((k) => k.startsWith("qms.filters.")).forEach((k) => localStorage.removeItem(k));
      changed();
    } else if (e.target.closest("[data-reset]")) { Object.assign(settings, DEFAULTS); changed(); toast("기본값으로 되돌렸습니다.", "ok"); }
  });
  draw();
}