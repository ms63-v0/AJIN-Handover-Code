/** 용접 현황: 파라미터별 측정값 그래프/표 + 기준 상·하한 + 최근 용접 알람. */
import { api } from "../api.js";
import { PARAM_VIEW, PART_COLORS, fmtParam, unitLabel } from "../config.js";
import { startPolling } from "../components/poller.js";
import { lineChart, chartImage } from "../components/charts.js";
import { exportReport } from "../exporter.js";
import { defaultRange, rangeChip, rangeParams, rangeLabel, isLiveRange, openRangePicker, resolveRange } from "../components/rangePicker.js";

import { headerExtra } from "../components/header.js";
import { icon } from "../components/icons.js";
import { dateChip, tabs, partItems, viewToggle, exportButtons, statusChip, verdict, liveTag, nowHms, skeleton } from "../components/ui.js";
import { alarmAttrs, bindAlarmClicks, onAlarmChanged } from "../components/alarmPopup.js";
import { settings, loadFilters, saveFilters } from "../settings.js";
import { downloadCsv, esc, parseTs, today } from "../utils.js";
import { paginationHtml, bindPagination } from "../components/pagination.js";
import { setHtml, syncList } from "../components/dom.js";

const label = (p) => PARAM_VIEW[p.code]?.label ?? p.name;
const dec = (p, v) => fmtParam(p.code, v, p.unit);
const U = (p) => unitLabel(p.unit);
const limitText = (p) => (p.limitLower != null ? `기준 ${dec(p, p.limitLower)}~${dec(p, p.limitUpper)}${U(p)}` : "기준값 없음");

// Canvas 차트 인스턴스를 파라미터 코드별로 관리
const chartInstances = new Map();

function getOrCreateChart(container, paramCode, opts) {
  let inst = chartInstances.get(paramCode);
  if (!inst || !container.querySelector("canvas")) {
    inst?.destroy?.();
    inst = lineChart(container, opts);
    chartInstances.set(paramCode, inst);
  } else {
    inst.update(opts);
  }
  return inst;
}

function chartCard(p, windowMs) {
  const s = p.stats;
  const series = p.series.map((x) => ({
    name: `${x.partNo}번파트`,
    color: PART_COLORS[(x.partNo - 1) % PART_COLORS.length],
    points: x.points.map((q) => ({ t: parseTs(q.time), v: q.value })),
  }));
  const over = p.limitLower != null
    ? p.series.flatMap((x) => x.points).filter((q) => q.value < p.limitLower || q.value > p.limitUpper).length
    : 0;
  return `<section class="wcard" data-param="${p.code}">
    <div class="wcard__head">
      <h3>${esc(p.name)} (${esc(U(p))})</h3>
      ${over ? `<span class="wcard__over">기준 이탈 ${over}건</span>` : ""}
      <span class="wcard__hint">휠 확대·축소 · 드래그 이동 · 더블클릭 실시간</span>
    </div>
    <div class="wcard__avg">${s ? `평균 <b>${dec(p, s.avg)}${U(p)}</b>` : ""}</div>
    <div class="legend">${series.map((x) => `<span><i style="background:${x.color}"></i>${x.name}</span>`).join("")}</div>
    <div class="wcard__canvas" data-canvas="${p.code}"></div>
    <div class="wcard__foot">${s ? `Min ${dec(p, s.min)} · Max ${dec(p, s.max)} · ` : ""}${limitText(p)}</div>
  </section>`;
}

/** 표 보기: 차트와 같은 원본 측정값을 한 건씩(시각 · LOT · 파트 · 측정값 · 판정). 페이지 단위로 자른다. */
const tableRows = (p) => p.series
  .flatMap((s) => s.points.map((q) => ({ time: q.time, t: parseTs(q.time), part: s.partNo, lotNo: q.lotNo, value: q.value })))
  .sort((a, b) => b.t - a.t);

/** 표 보기 카드 골격(한 번만 만든다). 행은 draw() 에서 syncList 가 맞춘다. */
const tableCardShell = (p) => `<section class="wcard" data-param="${p.code}">
    <div class="wcard__head"><h3>${esc(label(p))} (${esc(U(p))})</h3></div>
    <div class="wcard__avg"></div>
    <div class="wtable"></div>
  </section>`;
const tableBodyShell = () => `<table class="tbl tbl--sm">
    <thead><tr><th>시각</th><th>LOT 번호</th><th>파트</th><th>측정값</th><th>판정</th></tr></thead>
    <tbody></tbody></table>`;
const rowKey = (r) => `${r.time}|${r.part}|${r.lotNo}|${r.value}`;
const tableRowHtml = (p, r) => {
  const ng = p.limitLower != null && (r.value < p.limitLower || r.value > p.limitUpper);
  return `<tr class="${ng ? "is-ng" : ""}"><td class="c-time">${esc(r.time.slice(5, 19))}</td><td>${esc(r.lotNo ?? "-")}</td><td>${r.part}번</td><td><b>${dec(p, r.value)}</b></td><td>${verdict(ng ? "NG" : "OK")}</td></tr>`;
};

const alarmHtml = (a, params) => {
  const p = params.find((x) => x.code === a.param);
  const f = (v) => (p ? `${dec(p, v)}${U(p)}` : `${v}`);
  const red = a.status === "발생";
  let meas = "";
  if (a.measured != null) {
    const diff = a.threshold != null ? Math.abs(a.measured - a.threshold) : null;
    meas = `<div class="acard__meas">
      <span class="acard__dir">${a.isHigh ? "↑ 상한 초과" : "↓ 하한 미만"}${diff != null && p ? ` +${dec(p, diff)}` : ""}</span>
      <span>측정 ${a.recovered != null
        ? `<b class="t-gold">${f(a.measured)}</b> → <b class="t-ok">${f(a.recovered)}</b>`
        : `<b class="t-ng">${f(a.measured)}</b>`}
        ${a.threshold != null ? `<span class="acard__thr">(기준 ${f(a.threshold)})</span>` : ""}
      </span>
      ${a.limitLower != null ? `<span class="acard__range">레시피 기준 ${f(a.limitLower)} ~ ${f(a.limitUpper)}</span>` : ""}
    </div>`;
  }
  return `<div class="acard acard--click acard--${red ? "red" : "green"}" ${alarmAttrs(a)}>
    <div class="acard__top">${statusChip(a.status)}<span class="acard__time">${a.time}</span><span class="acard__go">상세 ›</span></div>
    <div class="acard__msg">${esc(a.message)}</div>${meas}
  </div>`;
};

export const weldPage = {
  id: "weld",
  title: "용접 현황",

  render(root) {
    const f = loadFilters("weld", { part: "", hidden: [], view: settings.defaultView === "table" ? "table" : "chart" });
    const state = { range: { preset: "1h" }, part: f.part,
      view: f.view, hidden: new Set(f.hidden), data: null, partNos: [], online: true, at: "",
      tblPage: 1, tblPerPage: 20 };
    const remember = () => saveFilters("weld", { part: state.part, hidden: [...state.hidden], view: state.view });
    // 기본 윈도우: 최근 2시간 (설정에서 5/10분은 표 보기에만 적용)
    const windowMs = 2 * 3600 * 1000;

    root.innerHTML = `
      <div class="weld">
        <div class="weld__main">
          <div class="sec-head"><h2 class="section-title" id="w-title"></h2><span class="live-tag" id="w-live"></span></div>
          <div class="filter-bar" id="w-ctrl"></div>
          <div class="wgrid" id="w-grid">${skeleton(4, "skel--chart")}</div>
          <div id="w-tpage"></div>
        </div>
        <aside class="weld__side">
          <div class="side-head"><h2 class="section-title">최근 용접 알람</h2><span class="count" id="w-count"></span></div>
          <div class="stack" id="w-alarm">${skeleton(3)}</div>
        </aside>
      </div>`;

    const $ = (s) => root.querySelector(s);
    const tabsEl = headerExtra();

    const drawTabs = () => { tabsEl.innerHTML = tabs(partItems(state.partNos), state.part, "part"); };
    const drawCtrl = () => {
      const chips = (state.data?.parameters ?? []).map((p) =>
        `<button class="pchip ${state.hidden.has(p.code) ? "" : "is-on"}" data-param="${p.code}">${label(p)}${state.hidden.has(p.code) ? "" : icon("check")}</button>`).join("");
      const nowOn = state.range?.preset === "1h";
      $("#w-ctrl").innerHTML = `${rangeChip(state.range)}<button type="button" class="now-btn ${nowOn ? "is-on" : ""}" data-now title="지금부터 1시간 전까지 실시간으로 보기"><i></i>현재 기준 1시간</button><div class="pchips">${chips}</div><span class="filter-bar__grow"></span>${viewToggle(state.view, ["chart", "chart", "그래프"], ["table", "excel", "표"])}${exportButtons()}`;
    };

    const domainOf = () => {
      const v = resolveRange(state.range);
      return [v.from.getTime(), v.to ? v.to.getTime() + 59999 : Date.now()];
    };
    // 서버도 같은 구간으로 거르지만, 화면에서도 한 번 더 걸러 기간 밖 값이 차트·표에 절대 들어가지 않게 한다
    const clipToRange = (d) => {
      if (!d) return d;
      const [a, b] = domainOf(), ok = (s) => { const t = parseTs(s); return t >= a && t <= b; };
      d.parameters.forEach((p) => p.series.forEach((s) => { s.points = s.points.filter((q) => ok(q.time)); }));
      d.events = (d.events ?? []).filter((ev) => ok(ev.time));
      return d;
    };

    const draw = () => {
      const d = state.data;
      const title = $("#w-title"), ttl = state.part ? `${state.part}번 파트 파라미터` : "전체 파트 파라미터";
      if (title.textContent !== ttl) title.textContent = ttl;
      setHtml($("#w-live"), isLiveRange(state.range) ? liveTag(state.online, state.at) + (!state.online && state.err ? `<span class="live-at">${esc(state.err)}</span>` : "") : `<i class="dot dot--gold"></i>기간 조회 (자동 갱신 없음)`);
      if (!d) return;

      const shown = d.parameters.filter((p) => !state.hidden.has(p.code));
      const grid = $("#w-grid");
      const codes = shown.map((p) => p.code).join(",");
      const emptyHtml = `<div class="empty">표시할 파라미터를 선택하세요.</div>`;

      if (state.view === "chart") {
        // 차트 모드: 카드 골격은 파라미터 구성이 바뀔 때만 만들고, 이후에는 차트 객체를 update 만 한다
        grid.classList.add("wgrid--stack");
        setHtml($("#w-tpage"), "");
        if (grid.dataset.mode !== "chart" || grid.dataset.codes !== codes) {
          chartInstances.forEach((inst) => inst.destroy?.());
          chartInstances.clear();
          grid.dataset.mode = "chart"; grid.dataset.codes = codes;
          grid.innerHTML = shown.length ? shown.map((p) => chartCard(p, windowMs)).join("") : emptyHtml;
        }
        shown.forEach((p) => {
          const container = grid.querySelector(`[data-canvas="${p.code}"]`);
          if (!container) return;
          const series = p.series.map((x) => ({
            name: `${x.partNo}번파트`,
            color: PART_COLORS[(x.partNo - 1) % PART_COLORS.length],
            points: x.points.map((q) => ({ t: parseTs(q.time), v: q.value })),
          }));
          getOrCreateChart(container, p.code, {
            series,
            lower: p.limitLower,
            upper: p.limitUpper,
            dec: PARAM_VIEW[p.code]?.dec(p.unit) ?? 2,
            windowMs,
            domain: domainOf(),               // X축 = 조회 기간(시작 ~ 종료) 고정
            live: isLiveRange(state.range),
            syncGroup: "weld",                // 4개 차트 크로스헤어·확대 범위 동기화
            events: (d.events ?? []).filter((ev) => !ev.param || ev.param === p.code).map((ev) => ({ t: parseTs(ev.time), label: ev.message })),
          });
        });
      } else {
        // 표 모드: 카드 골격은 한 번만 만들고, 행은 키(시각·파트·LOT·값)로 바뀐 것만 교체한다
        grid.classList.remove("wgrid--stack");
        const total = Math.max(0, ...shown.map((p) => tableRows(p).length));
        const pages = Math.max(1, Math.ceil(total / state.tblPerPage));
        if (state.tblPage > pages) state.tblPage = pages;
        if (grid.dataset.mode !== "table" || grid.dataset.codes !== codes) {
          chartInstances.forEach((inst) => inst.destroy?.());
          chartInstances.clear();
          grid.dataset.mode = "table"; grid.dataset.codes = codes;
          grid.innerHTML = shown.length ? shown.map(tableCardShell).join("") : emptyHtml;
        }
        shown.forEach((p) => {
          const card = grid.querySelector(`.wcard[data-param="${p.code}"]`);
          if (!card) return;
          const all = tableRows(p);
          setHtml(card.querySelector(".wcard__avg"), `${limitText(p)} · 전체 ${all.length.toLocaleString("ko-KR")}건`);
          const wt = card.querySelector(".wtable");
          const rows = all.slice((state.tblPage - 1) * state.tblPerPage, state.tblPage * state.tblPerPage);
          if (!rows.length) { setHtml(wt, `<div class="empty">측정 데이터가 없습니다.</div>`); return; }
          if (!wt.querySelector("tbody")) setHtml(wt, tableBodyShell());
          syncList(wt.querySelector("tbody"), rows, rowKey, (r) => tableRowHtml(p, r));
        });
        setHtml($("#w-tpage"), shown.length && total ? paginationHtml({ total, page: state.tblPage, perPage: state.tblPerPage }) : "");
      }

      setHtml($("#w-count"), `<i class="dot dot--ng"></i>${d.alarms.count}건`);
      syncList($("#w-alarm"), d.alarms.items, (a) => a.alarmId, (a) => alarmHtml(a, d.parameters),
        `<div class="empty">오늘 발생한 용접 알람이 없습니다.</div>`);
    };

    const load = async () => {
      // 요청 실패(연결 끊김)와 화면 가공 실패를 분리한다. 가공이 실패해도 서버 연결 상태는 바꾸지 않는다.
      let res = null;
      try {
        res = await api.weld({ ...rangeParams(state.range), part: state.part });
        state.online = true;
        state.at = nowHms();
        state.err = "";
      } catch (e) {
        state.online = false;
        state.err = e?.message ?? String(e);
        console.error("[용접 현황] 조회 실패", e);
      }
      if (res) {
        try { state.data = clipToRange(res); }
        catch (e) { state.data = res; console.error("[용접 현황] 기간 필터 실패", e); }
      }
      if (!root.isConnected) return;
      if (!$("#w-ctrl").children.length && state.data) drawCtrl();
      draw();
    };


    // 추출: 서버가 DB에서 직접 조회해 생성. 화면은 조건 + 차트 이미지(흰 배경 · 2배 해상도)만 전달
    const doExport = (act) => {
      const shown = (state.data?.parameters ?? []).filter((p) => !state.hidden.has(p.code));
      const evs = state.data?.events ?? [];
      exportReport("weld", act === "excel" ? "xlsx" : act, { ...rangeParams(state.range), part: state.part, parameters: shown.map((p) => p.code) }, () =>
        shown.map((p) => ({
          title: `${p.name} (${U(p)})`,
          image: chartImage("line", {
            series: p.series.map((x) => ({ name: `${x.partNo}번파트`, color: PART_COLORS[(x.partNo - 1) % PART_COLORS.length], points: x.points.map((q) => ({ t: parseTs(q.time), v: q.value })) })),
            lower: p.limitLower, upper: p.limitUpper, dec: PARAM_VIEW[p.code]?.dec(p.unit) ?? 2,
            events: evs.filter((ev) => !ev.param || ev.param === p.code).map((ev) => ({ t: parseTs(ev.time), label: ev.message })),
          }, { title: `${p.name} (${U(p)}) · ${rangeLabel(state.range)}${state.part ? ` · ${state.part}번 파트` : ""}` }),
        })));
    };

    const onClick = (e) => {
      // 드래그 후 mouseup → click 이벤트 발생 시 차단 (canvas._wasDragged 플래그)
      const canvas = e.target.closest(".wcard__canvas");
      if (canvas?._wasDragged) return;

      const t = e.target.closest("[data-tab]"), pc = e.target.closest(".pchip[data-param]"),   // 카드(section.wcard)의 data-param 은 필터가 아님
            v = e.target.closest("[data-view]"), a = e.target.closest("[data-act]")?.dataset.act;
      if (t) { state.part = t.dataset.value; state.tblPage = 1; remember(); drawTabs(); load(); }
      else if (pc) {
        // canvas 위 클릭이면 파라미터 필터 토글 차단
        if (e.target.closest(".wcard__canvas")) return;
        const c = pc.dataset.param; state.hidden.has(c) ? state.hidden.delete(c) : state.hidden.add(c); remember(); drawCtrl(); draw();
      }
      else if (v) { state.view = v.dataset.view; remember(); drawCtrl(); draw(); }
      else if (a === "pdf" || a === "excel" || a === "csv") doExport(a);
    };
    root.addEventListener("click", onClick);
    tabsEl.addEventListener("click", onClick);
    root.addEventListener("input", (e) => {
    });
    bindAlarmClicks(root);
    bindPagination($("#w-tpage"), {
      onPage: (p) => { state.tblPage = p; draw(); },
      onPerPage: (n) => { state.tblPerPage = n; state.tblPage = 1; draw(); },
    });

    api.parts().then((r) => { state.partNos = r.map((p) => p.part_no); drawTabs(); }).catch(() => {});
    const applyRange = (r) => {   // 기간 변경: 차트를 새로 그려 X축을 새 기간으로 즉시 맞춤 (다른 필터는 유지)
      state.range = r; state.tblPage = 1; drawCtrl();
      chartInstances.forEach((i) => i.destroy?.()); chartInstances.clear(); $("#w-grid").innerHTML = ""; delete $("#w-grid").dataset.mode;
      load();
    };
    root.addEventListener("click", (e) => {   // 조회 기간 선택 / [현재 기준 1시간]
      const rg = e.target.closest("[data-range]");
      if (rg) openRangePicker(rg, state.range, applyRange, { maxDays: 7, title: "조회 기간 (최대 7일)" });
      else if (e.target.closest("[data-now]")) applyRange({ preset: "1h" });
    });
    const stop = startPolling(() => (isLiveRange(state.range) ? load() : undefined), { isActive: () => root.isConnected });   // 과거 구간은 자동 갱신 안 함
    const off = onAlarmChanged(load);
    return () => {
      stop(); off();
      chartInstances.forEach((inst) => inst.destroy?.());
      chartInstances.clear();
    };
  },
};