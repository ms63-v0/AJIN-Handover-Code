/**
 * Lot 조회 검색 필터 (Figma: 날짜 · Lot번호 · 파트 · 판정 · 조회 버튼 · PDF · Excel).
 * 이 컴포넌트는 HTML만 그린다. 입력 이벤트는 index.js 에서 위임 방식으로 처리한다.
 */
import { icon } from "../../components/icons.js";
import { rangeChip } from "../../components/rangePicker.js";
import { esc } from "../../utils.js";

/** partNos: DB의 use_yn='Y' 용접부위 번호 목록 (동적 로딩) */
export function renderSearchBar(root, filters, { partNos = [] }) {
  const partOpts  = [["", "전체"], ...partNos.map((n) => [String(n), String(n)])];
  const resultOpts = [["", "전체"], ["OK", "OK"], ["NG", "NG"]];

  const segBtns = (opts, name, current) =>
    opts.map(([v, l]) =>
      `<button class="seg__opt ${v === current ? "is-active" : ""}" data-name="${name}" data-value="${v}">${l}</button>`
    ).join("");

  root.innerHTML = `
    <h2 class="section-title" style="margin-bottom:20px">검색</h2>
    <div class="filter-bar">
      <div class="filter-bar__group">
        ${rangeChip(filters.range)}
        <label class="chip chip--lot">
          <input type="text" name="lot_no" inputmode="numeric" placeholder="Lot 번호"
                 maxlength="50" value="${esc(filters.lot_no)}">
          ${icon("search")}
        </label>
        <div class="chip">
          <span class="chip__label">파트</span>
          <div class="seg">${segBtns(partOpts, "part", filters.part)}</div>
        </div>
        <div class="chip">
          <span class="chip__label">판정</span>
          <div class="seg">${segBtns(resultOpts, "result", filters.result)}</div>
        </div>
      </div>
      <button class="btn--gold" data-act="search">조회</button>
      <div class="export">
        <button data-act="pdf"   title="PDF 보고서 (결재·증빙용)">${icon("pdf")}</button>
        <button data-act="excel" title="Excel (요약 + 상세 시트 · 분석용)">${icon("excel")}</button>
        <button data-act="csv" class="export__csv" title="CSV 원본 데이터 (UTF-8 · 대용량/통계 툴용)">CSV</button>
      </div>
    </div>`;
}
