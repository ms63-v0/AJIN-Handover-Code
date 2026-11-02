/** 알람 상세 내용 (알람 이력 화면 오른쪽 패널 + 모든 화면의 알람 팝업이 공유).
 *  구성 (ISA-18.2): 등급·상태 → 알람 내용(제목) → 생애주기(발생 → 현장 복구 → 조치 완료)
 *                   → 상세 내용(무엇이 어디서 어떻게) → 표준 조치 가이드 → 알람 정보 → 조치 이력
 */
import { icon } from "../../components/icons.js";
import { prioBadge, stateTag } from "../../components/ui.js";
import { PARAM_VIEW, fmtParam, unitLabel } from "../../config.js";
import { esc, fmtDateTime } from "../../utils.js";

const hms = (s) => (s ? String(s).slice(11, 19) : "");

/** 기준 이탈 알람: 측정값 / 위반 기준값 / 레시피 범위 / 복귀값 */
function limitBox(l) {
  if (!l || l.measured == null) return "";
  const f = (v) => (v == null ? "-" : `${fmtParam(l.param, v, l.unit)}${unitLabel(l.unit)}`);
  const label = PARAM_VIEW[l.param]?.label ?? "측정값";
  const high = l.isHigh ?? (l.limitUpper != null && l.measured > l.limitUpper);
  const diff = l.threshold != null ? Math.abs(l.measured - l.threshold) : null;
  return `<div class="lim">
    <div class="lim__row"><span>${label}</span><b class="t-ng">${f(l.measured)}</b><span class="lim__dir">${high ? "↑ 상한 초과" : "↓ 하한 미만"}${diff != null ? ` (${fmtParam(l.param, diff, l.unit)}${unitLabel(l.unit)})` : ""}</span></div>
    <div class="lim__row"><span>레시피 기준</span><b>${f(l.limitLower)} ~ ${f(l.limitUpper)}</b></div>
    ${l.recovered != null ? `<div class="lim__row"><span>복귀값</span><b class="t-ok">${f(l.recovered)}</b>${l.recoveredAt ? `<span class="t-sub">${hms(l.recoveredAt)}</span>` : ""}</div>` : ""}
  </div>`;
}

/** 상세 본문 (닫기 버튼·하단 버튼 제외) — 팝업과 패널 공용 */
export function detailContent(d) {
  const steps = (d.steps ?? []).map((s) => `<li class="lc__s ${s.done ? "is-done" : ""} ${s.na ? "is-na" : ""}">
      <i aria-hidden="true">${s.done ? "✓" : ""}</i><b>${esc(s.name)}</b><small>${s.na ? "신호 없음" : s.done ? hms(s.time) : "대기"}</small></li>`).join("");
  const facts = (d.facts ?? []).map((f) => `<div><dt>${esc(f.label)}</dt><dd>${esc(f.value)}</dd></div>`).join("");
  const guide = (d.guide ?? []).length
    ? `<ol class="ad-guide">${d.guide.map((g) => `<li>${esc(g)}</li>`).join("")}</ol>`   // .guide 는 대시보드 차트 안내선 클래스라 이름을 분리
    : `<div class="dempty">등록된 조치 가이드가 없습니다</div>`;
  const cleared = d.clearedAt ? fmtDateTime(d.clearedAt) : d.kind === "EQUIP" ? "신호 없음" : "미복구";
  const info = [["설비", d.machine], ["관련 LOT", d.lotNo || "-"], ["발생 시각", fmtDateTime(d.occurredAt)],
    ["현장 복구", cleared], ["조치 완료", d.resolvedAt ? fmtDateTime(d.resolvedAt) : "-"], ["지속 시간", d.duration]];
  const actions = d.actions.length ? d.actions.map((a) => `
      <div class="act"><div class="act__top"><span class="act__avatar">${esc((a.worker || "?").slice(0, 1))}</span>
        <div><b>${esc(a.worker)}</b><small>${esc(a.department || "-")}${a.employeeNo ? ` · 사번 ${esc(a.employeeNo)}` : ""}</small></div>
        <span class="act__cat">${esc(a.category)}</span></div>
        <div class="act__time"><span>조치 일시</span><span>${fmtDateTime(a.time)}</span></div><p>${esc(a.content)}</p></div>`).join("")
    : `<div class="dempty">${icon("check")} 아직 등록된 조치가 없습니다</div>`;
  return `
    <div class="ad2">
      <div class="ad2__badges">${prioBadge(d.priority ?? 2, { blink: d.priority === 1 && d.status === "미해결" })}${stateTag(d.status)}<span class="cat cat--${d.category === "비전" ? "v" : "w"}">${esc(d.category)}</span></div>
      <h3 class="ad2__title">${esc(d.message)}</h3>
      <div class="ad2__meta">ALM-${d.alarmId} · ${fmtDateTime(d.occurredAt)} · <span class="${d.resolvedAt ? "" : "t-gold"}">${esc(d.duration)}</span></div>
      <ol class="lc">${steps}</ol>
    </div>
    <div class="detail__sec"><div class="sec-title"><span>상세 내용</span></div>
      <dl class="facts">${facts}</dl>${limitBox(d.limit)}
      <p class="ad2__raw">시스템 기록 · ${esc(d.description)}</p></div>
    <div class="detail__sec"><div class="sec-title"><span>표준 조치 가이드</span></div>${guide}</div>
    <div class="detail__sec"><div class="sec-title"><span>알람 정보</span></div><dl class="dl">${info.map(([k, v]) => `<div><dt>${k}</dt><dd>${esc(v)}</dd></div>`).join("")}</dl></div>
    <div class="detail__sec"><div class="sec-title"><span>조치 이력</span><span class="t-sub">${d.actions.length}건</span></div>${actions}</div>`;
}

/** 알람 이력 화면 오른쪽 패널 */
export function renderDetail(root, st, { onClose, onAction }) {
  root.innerHTML = !st ? `<div class="detail detail--empty">알람을 선택하면 상세 정보가 표시됩니다.</div>`
    : !st.ok ? `<div class="detail detail--empty">상세 정보를 불러오지 못했습니다.</div>`
    : `<div class="detail alarm-detail"><button class="detail__close" data-act="close" aria-label="닫기">${icon("x")}</button>
        <div class="alarm-detail__scroll">${detailContent(st.d)}</div>
        ${st.d.canAct ? `<div class="detail__foot"><button class="btn--gold btn--block" data-act="action">조치 등록</button></div>` : ""}</div>`;
  root.onclick = (e) => {
    const a = e.target.closest("[data-act]")?.dataset.act;
    if (a === "close") onClose();
    else if (a === "action") onAction();
  };
}
