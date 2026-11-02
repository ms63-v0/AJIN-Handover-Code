/**
 * 알람 상세 팝업: 대시보드 / 용접 / 비전 / 헤더 알림 등 어느 화면에서든 알람을 누르면 그 자리에서 연다.
 * 팝업 안에서 바로 조치 등록 가능. 등록되면 'qms:alarm-changed' 이벤트로 열려 있는 화면과 헤더 알림이 갱신된다.
 */
import { api } from "../api.js";
import { openModal } from "./modal.js";
import { toast } from "./toast.js";
import { esc } from "../utils.js";
import { detailContent } from "../pages/alarm/detail.js";
import { openActionModal } from "../pages/alarm/actionModal.js";

export const ALARM_CHANGED = "qms:alarm-changed";

/** 화면 쪽 구독 헬퍼: 반환값을 화면 정리(cleanup) 때 호출 */
export function onAlarmChanged(fn) {
  window.addEventListener(ALARM_CHANGED, fn);
  return () => window.removeEventListener(ALARM_CHANGED, fn);
}

export function openAlarmPopup(alarmId, partNo) {
  const m = openModal({ title: "알람 상세", width: 460, className: "modal--alarm", body: `<div class="skel skel--block"></div><div class="skel skel--line"></div><div class="skel skel--line"></div>` });
  const render = (d) => {
    m.setBody(detailContent(d) + (d.acked ? `<p class="t-sub">확인: ${esc(d.ackBy ?? "-")} · ${esc(d.ackAt ?? "")}</p>` : ""));
    m.setFoot(`${d.acked ? "" : `<button class="btn--ghost" data-act="ack">확인</button>`}<a class="btn--ghost" href="#/alarm?id=${d.alarmId}" data-modal-close>알람 이력에서 보기</a>`
      + (d.canAct ? `<button class="btn--gold btn--grow" data-act="action">조치 등록</button>` : `<span class="modal__done">✓ 조치가 완료된 알람입니다</span>`));
    m.foot.querySelector("[data-act=ack]")?.addEventListener("click", async () => {
      try {
        const r = await api.ackAlarm(d.alarmId);
        toast("알람을 확인했습니다.", "ok");
        window.dispatchEvent(new window.Event(ALARM_CHANGED));
        render({ ...d, acked: true, ackAt: r.ackAt, ackBy: r.ackBy });
      } catch (e) { toast(`확인 실패: ${e.message}`); }
    });
    m.foot.querySelector("[data-act=action]")?.addEventListener("click", () =>
      openActionModal(d, {
        onDone: (nd) => {
          render(nd);
          toast("조치가 등록되어 알람이 해결되었습니다.", "ok");
          window.dispatchEvent(new window.Event(ALARM_CHANGED));
        },
      }));
  };
  api.alarm(alarmId, partNo ?? 0).then(render).catch((e) => m.setBody(`<div class="msg msg--error">알람 정보를 불러오지 못했습니다. (${esc(e.message)})</div>`));
  return m;
}

/** 알람 카드 HTML 을 버튼으로 감싸 클릭 가능하게 (data-alarm / data-part 로 위임 처리) */
export const alarmAttrs = (a) => `data-alarm="${a.alarmId}" data-part="${a.partNo ?? ""}" data-prio="${a.priority ?? ""}"${a.acked === undefined ? "" : ` data-acked="${a.acked ? 1 : 0}"`} role="button" tabindex="0"`;

/** 컨테이너 안의 [data-alarm] 클릭·Enter → 팝업 */
export function bindAlarmClicks(container) {
  const open = (e) => {
    const c = e.target.closest("[data-alarm]");
    if (c && (e.type === "click" || e.key === "Enter")) openAlarmPopup(c.dataset.alarm, c.dataset.part || null);
  };
  container.addEventListener("click", open);
  container.addEventListener("keydown", open);
}