/** 여러 화면이 공유하는 작은 UI 조각 (HTML 문자열). 이벤트는 각 화면에서 위임 방식으로 처리한다. */
import { icon } from "./icons.js";
import { esc } from "../utils.js";

export const dateChip = (value) =>
  `<label class="chip chip--date"><input type="date" name="date" value="${esc(value)}">${icon("calendar")}</label>`;

// 알약형 선택 버튼: items = [[값, 라벨], ...]
export const tabs = (items, current, name) =>
  items.map(([v, l]) => `<button type="button" class="tab ${String(v) === String(current) ? "is-active" : ""}" data-tab="${name}" data-value="${v}">${l}</button>`).join("");

export const partItems = (partNos) => [["", "전체"], ...partNos.map((n) => [n, `${n}번 파트`])];

// 보기 전환(아이콘 2개) / 내보내기(PDF·엑셀)
export const viewToggle = (view, a, b) =>
  `<div class="view-toggle"><button data-view="${a[0]}" class="${view === a[0] ? "is-active" : ""}" title="${a[2]}">${icon(a[1])}</button><button data-view="${b[0]}" class="${view === b[0] ? "is-active" : ""}" title="${b[2]}">${icon(b[1])}</button></div>`;
export const exportButtons = () =>
  `<div class="export"><button data-act="pdf" title="PDF 보고서 (결재·증빙용)">${icon("pdf")}</button><button data-act="excel" title="Excel (요약 + 상세 시트 · 분석용)">${icon("excel")}</button><button data-act="csv" class="export__csv" title="CSV 원본 데이터 (UTF-8 · 대용량/통계 툴용)">CSV</button></div>`;

// 상태 칩 (발생/해제/미해결/조치중/해결됨 …)
const CHIP = { 발생: "red", 해제: "green", "오류 발생 후 복귀": "green", 미해결: "red-soft", 조치중: "yellow", 해결됨: "green-soft" };
export const statusChip = (s) => `<span class="schip schip--${CHIP[s] ?? "gray"}">${esc(s)}</span>`;

// 알람 우선순위 배지 (ISA-18.2 / ISA-101: 색과 도형을 함께 → 색약 작업자도 구분). 1 긴급 ◆ / 2 경고 ▲ / 3 주의 ■
const PRIO = { 1: ["긴급", "crit", "◆"], 2: ["경고", "warn", "▲"], 3: ["주의", "adv", "■"] };
export const prioBadge = (p, { blink = false } = {}) => {
  const [label, cls, glyph] = PRIO[p] ?? PRIO[2];
  return `<span class="prio prio--${cls}${blink ? " prio--blink" : ""}" title="${label} 알람"><i aria-hidden="true">${glyph}</i>${label}</span>`;
};
// 알람 상태 (색 블록 대신 기호 + 글자): 미해결 ● / 조치중 ◐ / 해결됨 ✓
export const stateTag = (s) => {
  const [cls, glyph] = { 미해결: ["open", "●"], 조치중: ["prog", "◐"], 해결됨: ["done", "✓"] }[s] ?? ["open", "●"];
  return `<span class="st st--${cls}"><i aria-hidden="true">${glyph}</i>${esc(s)}</span>`;
};

// 판정 칩 OK/NG
export const verdict = (v) => (v ? `<span class="pill pill--${v === "OK" ? "ok" : v === "NG" ? "ng" : "pending"}">${esc(v)}</span>` : "");

// 실시간 표시: ● LIVE · 14:32:08 갱신 / ● 연결 끊김
export const liveTag = (online, at, label = "LIVE") =>
  online ? `<i class="dot dot--ok dot--pulse"></i>${label}${at ? `<span class="live-at">${at} 갱신</span>` : ""}` : `<i class="dot dot--ng"></i>연결 끊김`;
export const nowHms = () => new Date().toTimeString().slice(0, 8);

// 로딩 자리표시(스켈레톤)
export const skeleton = (n = 3, cls = "skel--card") => Array.from({ length: n }, () => `<div class="skel ${cls}"></div>`).join("");
