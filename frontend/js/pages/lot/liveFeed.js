/** 실시간 수신(폴링): 전류값 / 용접결과 / 비전결과 이벤트를 주기적으로 가져와 화면에 알린다. */
import { api } from "../../api.js";
import { LIVE_POLL_MS, PARAMS } from "../../config.js";
import { esc } from "../../utils.js";

/**
 * 폴링 시작. 이전 요청이 끝난 뒤에만 다음 요청을 예약하므로 요청이 겹치지 않는다.
 * @param isActive  false를 돌려주면 폴링 종료(화면이 사라졌을 때)
 * @param onStatus  (online:boolean) 연결 상태 변화
 * @param onEvents  (events, isInitial) 새 이벤트 도착 (첫 응답은 isInitial=true)
 * @returns stop()  수동 중지 함수
 */
export function startLiveFeed({ isActive, onStatus, onEvents }) {
  let cursor = "", timer = null, stopped = false, first = true;

  async function tick() {
    if (stopped || !isActive()) return;
    if (!document.hidden) {                       // 탭이 숨겨져 있으면 요청 생략
      try {
        const r = await api.feed(cursor);
        cursor = r.cursor;                        // 다음 요청은 여기서부터 (중복/누락 방지)
        onStatus(true);
        if (r.events.length) onEvents(r.events, first);
        first = false;
      } catch {
        onStatus(false);
      }
    }
    if (!stopped) timer = setTimeout(tick, LIVE_POLL_MS);
  }
  tick();
  return () => { stopped = true; clearTimeout(timer); };
}

/** 이벤트 1건 → 화면용 짧은 문구. LOT 번호는 뒤 6자리(시분초)만 표시 */
export function eventChip(e) {
  const lot = String(e.lot_no).slice(-6);
  if (e.type === "CURRENT") return { text: `${lot} · ${e.part_no}번 전류 ${PARAMS.WELD_CURRENT.fmt(e.value, e.unit)}`, cls: "" };
  if (e.type === "WELD") return { text: `${lot} · ${e.part_no}번 용접 ${e.result}`, cls: e.result.toLowerCase() };
  return { text: `${lot} · 비전${String(e.camera ?? "").replace(/^VISION/i, "")} ${e.result}`, cls: e.result.toLowerCase() };
}

/** 상태 점 + 최근 수신 칩을 그린다. live = { online, items: [chip, ...] } */
export function paintLive(el, live) {
  if (!el) return;
  el.innerHTML = `
    <span class="live__dot ${live.online ? "is-on" : ""}"></span>
    <span class="live__label">${live.online ? "실시간" : "연결 끊김"}</span>
    <span class="live__feed">${live.items.map((c) => `<span class="live__chip ${c.cls ? `live__chip--${c.cls}` : ""}">${esc(c.text)}</span>`).join("")}</span>`;
}
