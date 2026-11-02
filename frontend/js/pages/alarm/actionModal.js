/**
 * 조치 등록 창. 작업자 정보는 직접 입력한다.
 * 저장: t_alarm_action INSERT → 서버가 t_alarm_event.resolved_time 을 채워 '해결됨' 처리 (조치 등록 없이는 해결되지 않음).
 */
import { api } from "../../api.js";
import { session } from "../../session.js";
import { openModal } from "../../components/modal.js";
import { statusChip } from "../../components/ui.js";
import { esc, fmtDateTime } from "../../utils.js";

const CATEGORIES = ["재작업", "부품 교체", "설비 점검", "기타"]; // backend/config.py ACTION_CATEGORIES 와 동일
const MAX = 400;

export function openActionModal(d, { onDone }) {
  const st = { category: "재작업", busy: false };
  const now = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 19).replace("T", " ");
  const field = (label, name, ph, { req = true, value = "", max = 50 } = {}) =>
    `<label>${label}${req ? " <i>*</i>" : " <small>(선택)</small>"}<input name="${name}" value="${esc(value)}" placeholder="${ph}" maxlength="${max}" autocomplete="off"></label>`;
  const m = openModal({
    title: "조치 등록", subtitle: "알람 조치", width: 500, className: "modal--action",
    body: `
      <div class="msum"><div><b>${esc(d.message)}</b><small>${esc(d.lotNo || `ALM-${d.alarmId}`)} · ${fmtDateTime(d.occurredAt)}</small></div>${statusChip(d.status)}</div>
      <h4>작업자 정보</h4>
      <div class="mgrid">${field("작업자 이름", "worker_name", "이름을 입력하세요")}${field("소속", "department", "예: FA 사업팀", { value: session.user?.dept ?? "", max: 40 })}</div>
      <div class="mgrid">${field("사번", "employee_no", "사번을 입력하세요", { max: 20 })}${field("연락처", "phone", "010-0000-0000", { req: false, max: 20 })}</div>
      <h4>조치 정보</h4>
      <div class="mgrid"><label>조치 일시<input value="${fmtDateTime(now)}" readonly></label><label>발생 후 경과<input value="${esc(d.duration.replace("진행중 · ", "").replace(" 경과", ""))}" readonly></label></div>
      <div class="mfield"><span>조치 구분 <i>*</i></span><div class="mchips">${CATEGORIES.map((c) => `<button type="button" class="mchip ${c === st.category ? "is-on" : ""}" data-cat="${c}">${c}</button>`).join("")}</div></div>
      <label class="mfield">조치 내용 <i>*</i><textarea name="content" maxlength="${MAX}" rows="4" placeholder="수행한 조치 내용을 입력하세요."></textarea><small class="mcount">0 / ${MAX}</small></label>
      <div class="mnote"><span>조치를 등록하면 알람이 해결 처리됩니다</span><span>${statusChip(d.status)} → ${statusChip("해결됨")}</span></div>
      <p class="form-error" role="alert"></p>`,
    footer: `<button class="btn--ghost" data-modal-close>취소</button><button class="btn--gold btn--grow" data-act="save" disabled>✓ 조치 완료</button>`,
  });
  const el = m.el, $ = (n) => el.querySelector(`[name="${n}"]`), save = el.querySelector('[data-act="save"]'), err = el.querySelector(".form-error");
  const val = (n) => $(n).value.trim();
  const ready = () => val("worker_name") && val("department") && val("employee_no") && val("content");
  $("worker_name").focus();

  el.addEventListener("input", () => {
    el.querySelector(".mcount").textContent = `${$("content").value.length} / ${MAX}`;
    save.disabled = !ready();
  });
  el.addEventListener("click", async (e) => {
    const cat = e.target.closest("[data-cat]");
    if (cat) { st.category = cat.dataset.cat; el.querySelectorAll(".mchip").forEach((b) => b.classList.toggle("is-on", b === cat)); }
    if (e.target.closest('[data-act="save"]') && !st.busy && ready()) {
      st.busy = true; save.disabled = true; err.textContent = "";
      try {
        const nd = await api.registerAction(d.alarmId, { category: st.category, content: val("content"), worker_name: val("worker_name"),
          department: val("department"), employee_no: val("employee_no"), phone: val("phone") || null, part: d.partNo });
        m.close();
        onDone(nd);
      } catch (ex) { err.textContent = ex.status ? ex.message : "서버에 연결할 수 없습니다. API 서버 실행 여부를 확인하세요."; st.busy = false; save.disabled = false; }
    }
  });
}
