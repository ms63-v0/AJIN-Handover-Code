/** 주기 갱신: 이전 요청이 끝난 뒤에만 다음 요청을 예약한다(겹침 방지). 숨겨진 탭은 건너뛴다. */
import { REFRESH_MS } from "../config.js";

/** @param task 갱신 함수(최초 1회 즉시 실행)  @param isActive false면 종료  @returns stop() */
export function startPolling(task, { isActive, ms = REFRESH_MS }) {
  let timer, stopped = false;
  async function tick() {
    if (stopped || !isActive()) return;
    if (!document.hidden) { try { await task(); } catch { /* 일시 오류는 다음 주기에 복구 */ } }
    if (!stopped) timer = setTimeout(tick, ms);
  }
  tick();
  return () => { stopped = true; clearTimeout(timer); };
}
