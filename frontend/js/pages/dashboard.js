/** 대시보드: KPI(금일 00:00 기준) · 생산/불량 추이(Canvas) · 불량 유형 분포 · 부위별 현황 · 최근 알람. */
import { api } from "../api.js";
import { startPolling } from "../components/poller.js";
import { trendChart, barChart } from "../components/charts.js";
import { dateChip, tabs, partItems, statusChip, liveTag, nowHms, skeleton } from "../components/ui.js";
import { alarmAttrs, bindAlarmClicks, onAlarmChanged } from "../components/alarmPopup.js";
import { loadFilters, saveFilters } from "../settings.js";
import { esc, num, today } from "../utils.js";

const n = (v) => Number(v ?? 0).toLocaleString("ko-KR");
const kpiCard = (title, dot, body) =>
  `<div class="kpi"><div class="kpi__title">${dot ? `<i class="dot dot--${dot}"></i>` : ""}${title}</div>${body}</div>`;
const big = (v, unit) => `<div class="kpi__big"><b>${v}</b><span>${unit}</span></div>`;

function kpiHtml(k) {
  const c = k.cycle;
  return (
    kpiCard("금일 생산량", "", big(n(k.production), "건") + `<span class="kpi__sub">오늘 종료된 LOT</span>`)
    + kpiCard("품질 합격률", "ok", big(num(k.okRate, 2), "%") + `<span class="kpi__pill kpi__pill--ok">${n(k.okCount)}건</span>`)
    + kpiCard("품질 불량률", "ng", big(num(k.ngRate, 2), "%") + `<span class="kpi__pill kpi__pill--ng">${n(k.ngCount)}건</span>`)
    + kpiCard("평균 사이클 타임", "", `<div class="kpi__cycle"><div class="kpi__big"><b>${c ? num(c.avg, 1) : "-"}</b><span>sec</span></div>
        <div class="kpi__mm"><div>Min <b>${c ? num(c.min, 1) : "-"}</b><small>sec</small></div><div>Max <b>${c ? num(c.max, 1) : "-"}</b><small>sec</small></div></div></div>`)
  );
}

const processHtml = (p) =>
  `<div class="pcard"><div class="pcard__top"><b>${p.partNo}번 파트 용접</b><span class="pcard__pills"><i class="p-ok">${n(p.okCount)}건</i><i class="p-ng">${n(p.ngCount)}건</i></span></div>
   <div class="pcard__bar"><i style="width:${p.okRate}%"></i></div>
   <div class="pcard__rate"><span class="t-ok">합격률 <b>${num(p.okRate, 1)}%</b></span><span class="t-ng">불량률 <b>${num(p.ngRate, 1)}%</b></span></div></div>`;

const alarmHtml = (a) =>
  `<div class="acard acard--click acard--${a.status === "발생" ? "red" : "green"}" ${alarmAttrs(a)}>
   <div class="acard__top">${statusChip(a.status)}<span class="acard__time">${a.time}</span><span class="acard__go">상세 ›</span></div>
   <div class="acard__msg">${esc(a.message)}</div></div>`;

export const dashboardPage = {
  id: "dashboard",
  title: "대시보드",

  render(root) {
    const f = loadFilters("dashboard", { part: "" });
    const state = { date: today(), part: f.part, data: null, online: true, at: "" };
    let trend = null;        // Canvas 차트 인스턴스 (in-place 갱신용)
    let ctrlDrawn = false;

    root.innerHTML = `
      <div class="dash">
        <div class="dash__kpis" id="d-kpi">${skeleton(4, "skel--kpi")}</div>
        <div class="dash__body">
          <div class="dash__main">
            <div class="sec-head"><h2 class="section-title">생산 · 불량 추이</h2></div>
            <div class="dash__ctrl"><div id="d-ctrl" class="ctrl"></div><span class="trend-legend"><span><i class="lg lg--okbar"></i>생산 OK</span><span><i class="lg lg--bar"></i>불량 NG</span><small>(막대 · 좌축 EA)</small><span><i class="lg lg--rate"></i>불량률</span><small>(선 · 우축 %) · 30분 구간별</small></span><span class="live-tag" id="d-live"></span></div>
            <div class="trend card" id="d-trend"><div class="skel skel--chart"></div></div>
            <div class="sec-head" style="margin-top:24px">
              <h2 class="section-title">불량 유형 분포</h2>
              <span class="t-sub sec-head__note">비전 검사 NG 기준 · 상위 5개 + 기타</span>
            </div>
            <div class="card" id="d-defect"><div class="skel skel--chart"></div></div>
          </div>
          <aside class="dash__side">
            <h2 class="section-title">용접 부위별 현황</h2>
            <div class="stack" id="d-proc">${skeleton(3)}</div>
            <div class="side-head"><h2 class="section-title">최근 알람</h2><a class="link-more" href="#/alarm">전체 보기 ›</a></div>
            <div class="stack" id="d-alarm">${skeleton(3)}</div>
          </aside>
        </div>
      </div>`;

    const $ = (s) => root.querySelector(s);

    const drawCtrl = (d) => {
      $("#d-ctrl").innerHTML =
        dateChip(state.date)
        + tabs(partItems(d.processes.map((p) => p.partNo)), state.part, "part");
      ctrlDrawn = true;
    };

    const draw = () => {
      const d = state.data;
      $("#d-live").innerHTML = liveTag(state.online, state.at);
      if (!d) return;

      // KPI
      $("#d-kpi").innerHTML = kpiHtml(d.kpi);

      // 컨트롤 (첫 번째 로드 시만)
      if (!ctrlDrawn) drawCtrl(d);

      // 추이 그래프: in-place 갱신 (DOM 재생성 없음 → 깜빡임 없음)
      const trendEl = $("#d-trend");
      if (!trend || !trendEl.querySelector("canvas")) {
        // 첫 그리기 또는 DOM 교체 후
        trend?.destroy?.();
        trend = trendChart(trendEl, d.trend);
      } else {
        // 이미 Canvas 존재 → 데이터만 교체
        trend.update(d.trend);
      }

      // 불량 분포
      $("#d-defect").innerHTML = barChart(d.defectTypes);

      // 부위별
      $("#d-proc").innerHTML = d.processes.length
        ? d.processes.map(processHtml).join("")
        : `<div class="empty">등록된 용접부위가 없습니다.</div>`;

      // 알람
      $("#d-alarm").innerHTML = d.alarms.length
        ? d.alarms.map(alarmHtml).join("")
        : `<div class="empty">오늘 발생한 알람이 없습니다.</div>`;
    };

    const load = async () => {
      try {
        state.data = await api.dashboard({ date: state.date, part: state.part });
        state.online = true;
        state.at = nowHms();
      } catch {
        state.online = false;
      }
      if (root.isConnected) draw();
    };

    root.addEventListener("click", (e) => {
      const t = e.target.closest("[data-tab]");
      if (!t) return;
      state.part = t.dataset.value;
      saveFilters("dashboard", { part: state.part });
      $("#d-ctrl").querySelectorAll(".tab").forEach((b) => b.classList.toggle("is-active", b === t));
      load();
    });
    root.addEventListener("input", (e) => {
      if (e.target.name === "date" && e.target.value) { state.date = e.target.value; load(); }
    });
    bindAlarmClicks(root);

    const stop = startPolling(load, { isActive: () => root.isConnected });
    const off = onAlarmChanged(load);
    return () => { stop(); off(); trend?.destroy?.(); trend = null; };
  },
};
