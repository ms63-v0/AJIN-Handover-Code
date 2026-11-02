/** 판정(OK/NG) 표시 컴포넌트. 목록/상세에서 공용으로 사용한다. */
import { esc } from "../utils.js";

const LABEL = { OK: "OK", NG: "NG", PENDING: "대기" };

// 판정값 → CSS 클래스 접미사 ('ok' | 'ng' | 'pending')
export const resultClass = (r) => (r === "OK" ? "ok" : r === "NG" ? "ng" : "pending");

// 작은 알약: 파트별/비전 판정
export const pill = (r) => `<span class="pill pill--${resultClass(r)}">${esc(LABEL[r] ?? "-")}</span>`;

// 종합판정 배지. label 예: '종합 ' → '✓ 종합 OK'
export function overallBadge(r, { label = "", large = false } = {}) {
  const c = resultClass(r);
  const mark = c === "ok" ? "✓ " : c === "ng" ? "✕ " : "";
  return `<span class="badge badge--${c} ${large ? "badge--lg" : ""}">${mark}${esc(label)}${esc(LABEL[r] ?? "-")}</span>`;
}
