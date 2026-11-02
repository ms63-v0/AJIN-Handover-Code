/** 공용 유틸 */

// HTML 이스케이프: 서버에서 받은 문자열을 innerHTML에 넣을 때 반드시 사용 (XSS 방지)
export const esc = (v) =>
  String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// '2026-09-14 14:32:08' → '2026.09.14 14:32:08'
export const fmtDateTime = (s) => (s ? s.replace(/^(\d{4})-(\d{2})-(\d{2})/, "$1.$2.$3") : "-");

// CSV 다운로드 (엑셀에서 한글이 깨지지 않도록 BOM 포함)
export function downloadCsv(filename, rows) {
  const csv = "\ufeff" + rows.map((r) => r.map((c) => `"${String(c ?? "").replace(/"/g, '""')}"`).join(",")).join("\r\n");
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

// 오늘 날짜 'YYYY-MM-DD' (날짜 입력 기본값)
export const today = () => { const d = new Date(), p = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };

// 'YYYY-MM-DD HH:mm:ss' → 밀리초(로컬 시각) / HH:mm
export const parseTs = (s) => new Date(s.replace(" ", "T")).getTime();
export const hm = (s) => (s ? s.slice(11, 16) : "-");

// 숫자 문자열 (천 단위 구분 없이 소수 자리 고정)
export const num = (v, d = 0) => (v == null ? "-" : Number(v).toFixed(d));
