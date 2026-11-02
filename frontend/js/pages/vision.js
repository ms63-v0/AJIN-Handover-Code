/** 비전 검사 현황: KPI · LIVE · 불량 유형 분포 / 검사 이미지 · 카메라 상태 · 최근 비전 알람(클릭 → 상세 팝업). 정의서 '비전 검사 현황'. */
import { api } from "../api.js";
import { API_BASE } from "../config.js";
import { startPolling } from "../components/poller.js";
import { barChart } from "../components/charts.js";
import { exportReport } from "../exporter.js";
import { defaultRange, rangeChip, rangeParams, rangeLabel, isLiveRange, openRangePicker } from "../components/rangePicker.js";

import { headerExtra } from "../components/header.js";
import { icon } from "../components/icons.js";
import { openModal } from "../components/modal.js";
import { dateChip, tabs, partItems, viewToggle, exportButtons, statusChip, nowHms, skeleton } from "../components/ui.js";
import { alarmAttrs, bindAlarmClicks, onAlarmChanged } from "../components/alarmPopup.js";
import { settings, loadFilters, saveFilters } from "../settings.js";
import { downloadCsv, esc, num, today } from "../utils.js";
import { paginationHtml, bindPagination } from "../components/pagination.js";
import { setHtml, syncList } from "../components/dom.js";

const LIVE = { live: ["ok", "LIVE"], idle: ["gold", "대기 (최근 검사 없음)"], off: ["ng", "연결 끊김"] };
const img = (id) => `${API_BASE}/api/vision/images/${id}`;

const cardHtml = (c) => `<button class="vcard vcard--${c.result === "NG" ? "ng" : "ok"}" data-img="${c.imageId ?? ""}" data-title="${esc(c.lotNo)} · ${c.partNo}번 파트 · ${c.result}">
  <div class="vcard__img">${c.imageId ? `<img loading="lazy" alt="${esc(c.lotNo)} ${c.partNo}번 파트 ${c.result}" src="${img(c.imageId)}">` : `<span>이미지 없음</span>`}</div>
  <div class="vcard__row"><b>${esc(c.lotNo.slice(-11))}</b><span>${c.time}</span></div><div class="vcard__part">${c.partNo}번 파트</div></button>`;

const camHtml = (c) => `<div class="camcard"><div class="camcard__top"><b>${esc(c.camera || "-")}</b><span class="camcard__st ${c.active ? "is-on" : ""}"><i></i>${c.active ? "가동중" : "연동 안됨"}</span></div><div class="camcard__sub">담당 구역: <b>${c.partNo}번 파트</b></div></div>`;

const cardKey = (c) => `${c.lotNo}|${c.partNo}|${c.time}|${c.imageId ?? ""}`;

const alarmHtml = (a) => `<div class="acard acard--click acard--${a.status === "발생" ? "red" : "green"}" ${alarmAttrs(a)}><div class="acard__top">${statusChip(a.status)}<span class="acard__time">${a.time}${a.resolvedTime ? ` → ${a.resolvedTime}` : ""}</span><span class="acard__go">상세 ›</span></div>
  <div class="acard__msg">${esc(a.message)}</div>${a.lotNo ? `<div class="acard__lot">Lot <b>${esc(a.lotNo.slice(-11))}</b></div>` : ""}</div>`;

export const visionPage = {
  id: "vision",
  title: "비전 검사 현황",

  render(root) {
    const f = loadFilters("vision", { part: "", results: ["OK", "NG"], view: settings.defaultView === "table" ? "cards" : "chart" });
    const state = { range: defaultRange(), part: f.part, view: f.view, results: new Set(f.results), data: null, online: true, partNos: [], at: "", cardsPage: 1, cardsPerPage: 24 };
    const remember = () => saveFilters("vision", { part: state.part, results: [...state.results], view: state.view });
    root.innerHTML = `
      <div class="vis">
        <div class="vis__main">
          <div class="dash__kpis dash__kpis--3" id="v-kpi">${skeleton(3, "skel--kpi")}</div>
          <div class="vis__head"><h2 class="section-title">전체 파트 현황</h2><span class="live-tag" id="v-live"></span></div>
          <div class="filter-bar" id="v-ctrl"></div>
          <div id="v-body"><div class="skel skel--chart"></div></div>
        </div>
        <aside class="vis__side">
          <h2 class="section-title">카메라 상태</h2><div class="stack" id="v-cam">${skeleton(3)}</div>
          <div class="side-head"><h2 class="section-title">최근 비전 검사 알람</h2><span class="count" id="v-count"></span></div><div class="stack" id="v-alarm"></div>
        </aside>
      </div>`;
    const $ = (s) => root.querySelector(s);
    const tabsEl = headerExtra();
    const sel = () => (state.results.size === 2 ? "ALL" : [...state.results][0]); // OK·NG 둘 다 = 전체

    const drawTabs = () => { tabsEl.innerHTML = tabs(partItems(state.partNos), state.part, "part"); };
    const check = (k, l) => `<button class="rchip ${sel() === k ? "is-on" : ""}" data-res="${k}">${l}${sel() === k ? icon("check") : ""}</button>`;
    const drawCtrl = () => {
      $("#v-ctrl").innerHTML = `${rangeChip(state.range)}<div class="pchips">${check("ALL", "전체")}${check("OK", "OK")}${check("NG", "NG")}</div><span class="filter-bar__grow"></span>${viewToggle(state.view, ["chart", "chart", "불량 유형 분포"], ["cards", "grid", "검사 이미지"])}${exportButtons()}`;
    };
    const kpi = (title, dot, v, unit) => `<div class="kpi"><div class="kpi__title"><i class="dot dot--${dot}"></i>${title}</div><div class="kpi__big"><b>${v}</b><span>${unit}</span></div></div>`;
    const draw = () => {
      const d = state.data, [cls, txt] = !isLiveRange(state.range) ? ["gold", "기간 조회 (자동 갱신 없음)"] : LIVE[state.online ? d?.live.status ?? "idle" : "off"];
      setHtml($("#v-live"), `<i class="dot dot--${cls} ${cls === "ok" ? "dot--pulse" : ""}"></i>${txt}${state.online && state.at ? `<span class="live-at">${state.at} ${isLiveRange(state.range) ? "갱신" : "조회"}</span>` : ""}`);
      if (!d) return;
      setHtml($("#v-kpi"), kpi("금일 검사수량", "gold", Number(d.kpi.inspectionCount).toLocaleString("ko-KR"), "건") + kpi("비전검사 합격률", "ok", num(d.kpi.okRate, 1), "%") + kpi("비전검사 불량률", "ng", num(d.kpi.ngRate, 1), "%"));

      // 본문: 보기 모드가 바뀔 때만 골격을 만들고, 이후에는 바뀐 항목만 갱신한다
      const body = $("#v-body");
      if (state.view === "chart") {
        if (body.dataset.mode !== "chart") {
          body.dataset.mode = "chart";
          body.innerHTML = `<div class="sec-head"><h2 class="section-title">불량 유형 분포</h2><span class="t-sub sec-head__note">상위 5개 + 기타</span></div><div class="card" id="v-chart"></div>`;
        }
        setHtml($("#v-chart"), barChart(d.defectTypes));
      } else {
        if (body.dataset.mode !== "cards") {
          body.dataset.mode = "cards";
          body.innerHTML = `<div class="vgrid" id="v-grid"></div><div id="v-pg"></div>`;
        }
        syncList($("#v-grid"), d.cards, cardKey, cardHtml, `<div class="empty">조건에 맞는 검사 결과가 없습니다.</div>`);
        setHtml($("#v-pg"), d.cards.length ? paginationHtml({ total: d.total_cards ?? d.cards.length, page: d.page ?? 1, perPage: d.per_page ?? 24 }) : "");
      }

      setHtml($("#v-cam"), d.cameras.map(camHtml).join("") || `<div class="empty">카메라 정보가 없습니다.</div>`);
      setHtml($("#v-count"), `<i class="dot dot--ng"></i>${d.alarms.count}건`);
      syncList($("#v-alarm"), d.alarms.items, (a) => `${a.alarmId}-${a.partNo ?? 0}`, alarmHtml,
        `<div class="empty">오늘 발생한 비전 알람이 없습니다.</div>`);
    };
    const load = async () => {
      try { state.data = await api.vision({ ...rangeParams(state.range), part: state.part, result: state.results.size === 2 ? "" : [...state.results][0], page: state.cardsPage, per_page: state.cardsPerPage }); state.online = true; state.at = nowHms(); }
      catch { state.online = false; }
      if (root.isConnected) draw();
    };
    const onClick = (e) => {
      const t = e.target.closest("[data-tab]"), r = e.target.closest("[data-res]"), v = e.target.closest("[data-view]"), card = e.target.closest("[data-img]"), a = e.target.closest("[data-act]")?.dataset.act;
      if (t) { state.part = t.dataset.value; state.cardsPage = 1; remember(); drawTabs(); load(); }
      else if (r) { const k = r.dataset.res; state.results = k === "ALL" || sel() === k ? new Set(["OK", "NG"]) : new Set([k]); state.cardsPage = 1; remember(); drawCtrl(); load(); }
      else if (v) { state.view = v.dataset.view; remember(); drawCtrl(); draw(); }
      else if (card && card.dataset.img) openModal({ title: card.dataset.title, subtitle: "비전 검사 이미지", width: 720, body: `<img class="img-full" alt="${card.dataset.title}" src="${img(card.dataset.img)}">` }); // 이미지 크게 보기
      else if (a === "pdf" || a === "excel" || a === "csv")
        exportReport("vision", a === "excel" ? "xlsx" : a, { ...rangeParams(state.range), part: state.part, result: state.results.size === 2 ? "" : [...state.results][0] });
    };
    root.addEventListener("click", onClick);
    tabsEl.addEventListener("click", onClick);
    bindAlarmClicks(root);
    bindPagination($("#v-body"), {
      onPage: (p) => { state.cardsPage = p; load(); },
      onPerPage: (n) => { state.cardsPerPage = n; state.cardsPage = 1; load(); },
    });

    drawCtrl();
    api.parts().then((r) => { state.partNos = r.map((p) => p.part_no); drawTabs(); }).catch(() => {});
    root.addEventListener("click", (e) => {   // 조회 기간 선택
      const rg = e.target.closest("[data-range]");
      if (rg) openRangePicker(rg, state.range, (r) => { state.range = r; drawCtrl(); load(); });
    });
    const stop = startPolling(() => (isLiveRange(state.range) ? load() : undefined), { isActive: () => root.isConnected });   // 과거 구간은 자동 갱신 안 함
    const off = onAlarmChanged(load);
    return () => { stop(); off(); };
  },
};