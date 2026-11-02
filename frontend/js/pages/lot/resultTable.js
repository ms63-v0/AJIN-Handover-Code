/**
 * Lot 조회 결과 표 (날짜 · LOT번호 · 용접(파트별) · 비전(파트별) · 종합판정) + 페이지네이션.
 * idle 상태 = 아직 조회 안 함 (초기 화면).
 */
import { API_BASE } from "../../config.js";
import { pill, overallBadge } from "../../components/badge.js";
import { paginationHtml } from "../../components/pagination.js";
import { esc, fmtDateTime } from "../../utils.js";

const msg = (text, cls = "") =>
  `<div class="msg ${cls}">${esc(text)}</div>`;

function row(r, { partNos, selectedId, newIds }) {
  const cls = [
    r.lot_id === selectedId ? "is-selected" : "",
    r.final_result === "NG" ? "is-ng" : "",
    newIds.has(r.lot_id) ? "is-new" : "",
  ].filter(Boolean).join(" ");

  return `<tr class="${cls}" data-id="${r.lot_id}">
    <td class="td-date">${fmtDateTime(r.lot_end_time)}</td>
    <td class="td-lot">${esc(r.lot_no)}</td>
    ${partNos.map((n) => `<td>${pill(r.parts[n])}</td>`).join("")}
    ${partNos.map((n) => `<td>${pill(r.visionParts?.[n])}</td>`).join("")}
    <td>${overallBadge(r.final_result)}</td>
  </tr>`;
}

export function renderResultTable(root, { status, items, total, page, perPage, selectedId, partNos, newIds }) {
  const scrollTop = root.querySelector(".table-wrap")?.scrollTop ?? 0;
  const n = partNos.length;
  const subTh = partNos.map((p) => `<th class="th-sub">${p}번</th>`).join("");

  let body;
  if (status === "idle") {
    body = msg("조회 버튼을 눌러 검색하세요.");
  } else if (status === "loading") {
    body = msg("조회 중…");
  } else if (status === "error") {
    body = msg(`서버에 연결할 수 없습니다. API 서버(${API_BASE}) 실행 여부를 확인하세요.`, "msg--error");
  } else if (!items.length) {
    body = msg("조회 결과가 없습니다.");
  } else {
    body = `<div class="table-wrap">
      <table class="tbl tbl--lot">
        <thead>
          <tr>
            <th rowspan="2" class="th-l">날짜</th>
            <th rowspan="2" class="th-l">LOT 번호</th>
            <th colspan="${n}" class="th-grp">용접</th>
            <th colspan="${n}" class="th-grp">비전</th>
            <th rowspan="2">종합판정</th>
          </tr>
          <tr>${subTh}${subTh}</tr>
        </thead>
        <tbody>${items.map((r) => row(r, { partNos, selectedId, newIds })).join("")}</tbody>
      </table>
    </div>
    ${paginationHtml({ total, page, perPage })}`;
  }

  root.innerHTML = `
    <div class="result-head">
      <span>결과</span>
      <span class="result-head__count">
        ${status === "ok" ? `총 ${total.toLocaleString("ko-KR")}건` : ""}
      </span>
      <span class="live"></span>
    </div>
    ${body}`;

  const wrap = root.querySelector(".table-wrap");
  if (wrap) wrap.scrollTop = scrollTop;
}