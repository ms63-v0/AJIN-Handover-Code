/** 전역 설정. 주소/메뉴/센서 항목 표시 규칙은 여기서만 바꾼다. */

// 백엔드 API 주소
// · 로컬(Windows): 같은 PC 의 8000 포트 (기존과 동일)
// · Codespaces(*.app.github.dev): UI 서버가 /api 를 백엔드로 넘겨주므로(serve_ui.py UI_API_PROXY) 현재 주소를 그대로 사용
export const API_BASE = location.hostname.endsWith(".app.github.dev")
  ? location.origin
  : `${location.protocol}//${location.hostname}:8000`;

export const LIVE_POLL_MS = 3000;    // Lot 조회: 실시간 피드 폴링 주기(ms)
export const REFRESH_MS = 10000;     // 대시보드/용접/비전/알람: 자동 갱신 주기(ms) (정의서 '주기 갱신')

// 사이드바 메뉴: id는 URL(#/id)과 pages/index.js 의 키로 사용된다.
export const NAV_ITEMS = [
  { id: "dashboard", label: "대시보드", icon: "monitor" },
  { id: "weld", label: "용접 현황", icon: "pulse" },
  { id: "vision", label: "비전 검사 현황", icon: "camera" },
  { id: "lot", label: "Lot 조회", icon: "fileSearch" },
  { id: "alarm", label: "알람 이력 조회", icon: "bell" },
  { id: "admin", label: "기준정보 관리", icon: "settings", adminOnly: true },
];
export const DEFAULT_PAGE = "dashboard";

// 파라미터 표시 규칙 (키 = m_parameter.parameter_code). dec = 소수 자리(단위별로 다르면 함수)
export const PARAM_VIEW = {
  WELD_CURRENT: { label: "전류값", dec: (u) => (u === "kA" ? 2 : 0) },
  WELD_PRESS: { label: "공압", dec: () => 2 },
  COOLANT_TEMP: { label: "냉각수", dec: () => 1 },
  WELD_TIME: { label: "통전시간", dec: () => 2 },
};
export const fmtParam = (code, v, unit) => (v == null ? "-" : Number(v).toFixed(PARAM_VIEW[code]?.dec(unit) ?? 2));

// DB 단위 → 화면 표시 단위
export const unitLabel = (u) => ({ C: "°C" }[u] ?? u ?? "");

// Lot 상세 패널에 표시할 센서 항목 (표시 순서 = 아래 순서: 전류·공압 / 냉각수·통전시간)
const row = (code, label) => ({ label, fmt: (v, u) => `${fmtParam(code, v, u)}${unitLabel(u)}` });
export const PARAMS = {
  WELD_CURRENT: row("WELD_CURRENT", "전류"),
  WELD_PRESS: row("WELD_PRESS", "공압"),
  COOLANT_TEMP: row("COOLANT_TEMP", "냉각수"),
  WELD_TIME: row("WELD_TIME", "통전시간"),
};

// 파트별 선 색상 (1번파트부터)
// 파트 구분색 (ISA-101: 정상 라인은 차분한 색). 실제 값은 css/system.css 의 --part-N (라이트/다크 별도)
export const PART_COLORS = ["var(--part-1)", "var(--part-2)", "var(--part-3)", "var(--part-4)", "var(--part-5)"];