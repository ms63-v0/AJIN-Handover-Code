/** 선택한 Lot의 상세 패널: 단계 진행 → 파트별 센서값 → 비전 → 종합 코멘트. */
import { API_BASE, PARAMS } from "../../config.js";
import { icon } from "../../components/icons.js";
import { pill, overallBadge, resultClass } from "../../components/badge.js";
import { esc, fmtDateTime } from "../../utils.js";

const MARK = { ok: "✓", ng: "✕", pending: "·" };

/** 상단 진행 단계 원(1번/2번/3번/비전) */
const step = (label, result) => {
  const c = resultClass(result);
  return `<div class="step step--${c}"><span class="step__dot">${MARK[c]}</span><span>${label}</span><span class="step__res step__res--${c}">${esc(result ?? "-")}</span></div>`;
};

/** 센서값 한 칸. 값이 없으면 '-' */
const reading = ([code, p], readings) => {
  const r = readings[code];
  return `<div class="kv"><span>${p.label}</span><b>${r && r.value != null ? p.fmt(r.value, r.unit) : "-"}</b></div>`;
};

const partBlock = (p) => `
  <div class="detail__sec">
    <div class="sec-title"><span>${p.part_no}번파트 용접</span>${pill(p.result)}</div>
    <div class="kv-grid">${Object.entries(PARAMS).map((e) => reading(e, p.readings)).join("")}</div>
  </div>`;

const visionBlock = (v) => `
  <div class="detail__sec">
    <div class="sec-title"><span>비전 검사</span>${pill(v?.overall_result)}</div>
    <div class="vision">
      ${v?.imageId ? `<img class="vision__img" alt="비전 검사 이미지" src="${API_BASE}/api/vision/images/${v.imageId}">` : `<div class="vision__img">이미지 없음</div>`}
      <div class="vision__reason"><span>판정 사유</span><b>${esc(v?.reason ?? "-")}</b></div>
    </div>
  </div>`;

/** 종합 코멘트: 판정 결과로부터 자동 생성 (별도 저장 컬럼이 생기면 API 값으로 교체) */
function buildComment({ lot, parts, vision }) {
  if (lot.final_result === "OK") return ["모든 파트 용접 파라미터 정상 범위 내", "비전검사 결함 미검출로 최종 양품 처리됨"];
  const badParts = parts.filter((p) => p.result === "NG").map((p) => `${p.part_no}번`);
  const lines = [];
  if (badParts.length) lines.push(`${badParts.join(", ")}파트 용접 파라미터 기준 이탈`);
  if (vision?.overall_result === "NG") lines.push(`비전검사 ${vision.reason ?? "결함"} 검출`);
  lines.push(lot.final_result === "NG" ? "최종 불량 처리됨" : "판정 진행 중");
  return lines;
}

function detailHtml(data) {
  const { lot, parts, vision } = data;
  return `<div class="detail">
    <div class="detail__head">
      <button class="detail__close" data-act="close" aria-label="닫기">${icon("x")}</button>
      <span class="detail__label">LOT 상세</span>
      <span class="detail__lot">${esc(lot.lot_no)}</span>
      <span class="detail__time">${fmtDateTime(lot.lot_end_time)}</span>
      ${overallBadge(lot.final_result, { label: "종합 ", large: true })}
    </div>
    <div class="detail__sec"><div class="steps">
      ${parts.map((p) => step(`${p.part_no}번`, p.result)).join("")}${step("비전", vision?.overall_result)}
    </div></div>
    ${parts.map(partBlock).join("")}
    ${visionBlock(vision)}
    <div class="detail__comment"><strong>종합 코멘트</strong>${buildComment(data).map((t) => `<span>${esc(t)}</span>`).join("")}</div>
  </div>`;
}

export function renderDetailPanel(root, { status, data }, { onClose }) {
  const empty = (text) => `<div class="detail detail--empty">${esc(text)}</div>`;
  if (status === "loading") root.innerHTML = empty("불러오는 중…");
  else if (status === "error") root.innerHTML = empty("상세 정보를 불러오지 못했습니다.");
  else if (status !== "ok") root.innerHTML = empty("Lot를 선택하면 상세 정보가 표시됩니다.");
  else root.innerHTML = detailHtml(data);

  root.onclick = (e) => { if (e.target.closest('[data-act="close"]')) onClose(); }; // 닫기(✕)
}
