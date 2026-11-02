/** 알람 이력 조회: 필터(날짜/구분/파트/우선순위) · 목록 · 상세 패널 · 조치 등록. 정의서 '알람 이력 조회' 시트. */
import { api } from "../../api.js";
import { startPolling } from "../../components/poller.js";
import { tabs, partItems, exportButtons, prioBadge, stateTag } from "../../components/ui.js";
import { downloadCsv, esc, fmtDateTime, today } from "../../utils.js";
import { renderDetail } from "./detail.js";
import { openActionModal } from "./actionModal.js";
import { exportReport } from "../../exporter.js";
import { defaultRange, rangeChip, rangeParams, rangeLabel, isLiveRange, openRangePicker } from "../../components/rangePicker.js";
import { paginationHtml, bindPagination } from "../../components/pagination.js";

import { toast } from "../../components/toast.js";
import { onAlarmChanged, ALARM_CHANGED } from "../../components/alarmPopup.js";
import { loadFilters, saveFilters } from "../../settings.js";

const CATEGORY = [["all", "전체"], ["welder", "용접"], ["vision", "비전"]];
const PRIO_NAME = { 1: "긴급", 2: "경고", 3: "주의" };
const shortDt = (s) => (s ? `${s.slice(5, 10).replace("-", ".")} ${s.slice(11, 19)}` : "-");

function rowHtml(r, sel) {
  const open = r.status !== "해결됨";
  return `<tr data-key="${r.key}" class="${sel ? "is-selected" : ""} ${open ? "" : "is-closed"} ${r.priority === 1 && open ? "is-crit" : ""}">
    <td class="td-prio">${prioBadge(r.priority, { blink: r.priority === 1 && r.status === "미해결" })}</td>
    <td class="td-date">${shortDt(r.occurredAt)}</td>
    <td><span class="cat cat--${r.category === "비전" ? "v" : "w"}">${esc(r.category ?? "-")}</span></td>
    <td class="td-msg">${esc(r.message)}</td>
    <td class="td-lot">${esc(r.lotNo ?? "-")}</td>
    <td class="td-verdict">${r.verdict ? `<span class="vtxt vtxt--${r.verdict === "NG" ? "ng" : "ok"}">${esc(r.verdict)}</span>` : "-"}</td>
    <td class="td-worker">${esc(r.worker ?? "-")}</td>
    <td>${stateTag(r.status)}</td></tr>`;
}

/** KPI: 백엔드에서 전체 건수 기반으로 계산한 값을 사용 (페이지 무관하게 정확). */
function kpiHtml(kpi, prio) {
  if (!kpi) return "";
  const { byPriority, open, unacked = 0, mttr, top } = kpi;
  const chip = (p) => `<button type="button" class="akpi__p ${prio === p ? "is-on" : ""}" data-prio="${p}">${prioBadge(p)}<b>${byPriority[p] ?? 0}</b></button>`;
  const mttrTxt = mttr == null ? "-" : mttr >= 60 ? `${Math.floor(mttr / 60)}시간 ${Math.round(mttr % 60)}분` : `${Math.round(mttr)}분`;
  return `${chip(1)}${chip(2)}${chip(3)}<span class="akpi__sep"></span>
    <span class="akpi__m"><small>미확인</small><b class="${unacked ? "t-gold" : ""}">${unacked}건</b></span>
    <span class="akpi__m"><small>미해결</small><b class="${open ? "t-ng" : ""}">${open}건</b></span>
    <span class="akpi__m"><small>평균 조치 시간(MTTR)</small><b>${mttrTxt}</b></span>
    <span class="akpi__m akpi__m--top"><small>최다 발생</small><b>${top ? `${esc(top.message)} ${top.count}건` : "-"}</b></span>`;
}

export const alarmPage = {
  id: "alarm",
  title: "알람 이력 조회",

  render(root) {
    const initId = new URLSearchParams(location.hash.split("?")[1] ?? "").get("id");
    const saved = loadFilters("alarm", { category: "all", part: "" });
    const state = {
      range: initId ? { preset: "7d" } : defaultRange(),
      f: { category: initId ? "all" : saved.category, part: initId ? "" : saved.part },
      list: { status: "loading", items: [], total: 0, page: 1, perPage: 50, kpi: null },
      selKey: null, detail: null, partNos: [], initId,
      prio: null,  // 우선순위 필터 (서버사이드)
    };
    root.innerHTML = `
      <div class="alarm">
        <div class="alarm__left">
          <div class="filter-bar" id="a-ctrl"></div>
          <div class="result-head"><span>알람 이력</span><span class="result-head__count" id="a-total"></span></div>
          <div class="akpi" id="a-kpi"></div>
          <div id="a-table"></div>
        </div>
        <aside class="alarm__detail" id="a-detail"></aside>
      </div>`;
    const $ = (s) => root.querySelector(s);
    let detailSeq = 0;

    const drawCtrl = () => {
      $("#a-ctrl").innerHTML = `${rangeChip(state.range)}<div class="tabgroup">${tabs(CATEGORY, state.f.category, "category")}</div><div class="tabgroup">${tabs(partItems(state.partNos), state.f.part, "part")}</div><span class="filter-bar__grow"></span>${exportButtons()}`;
    };

    const drawList = () => {
      const { status, total, page, perPage, kpi } = state.list;
      const prioLabel = state.prio ? `${PRIO_NAME[state.prio]} ` : "";
      $("#a-total").textContent = status === "ok" ? `${prioLabel}총 ${total.toLocaleString("ko-KR")}건` : "";
      $("#a-kpi").innerHTML = status === "ok" ? kpiHtml(kpi, state.prio) : "";
      $("#a-table").innerHTML = status === "error" ? `<div class="msg msg--error">서버에 연결할 수 없습니다.</div>`
        : !state.list.items.length ? `<div class="msg">${status === "loading" ? "조회 중…" : "조회된 알람이 없습니다."}</div>`
        : `<div class="table-wrap table-wrap--alarm"><table class="tbl tbl--alarm"><thead><tr><th>등급</th><th>발생 일시</th><th>구분</th><th>알람 내용</th><th>LOT 번호</th><th>LOT 판정</th><th>조치자</th><th>상태</th></tr></thead><tbody>${state.list.items.map((r) => rowHtml(r, r.key === state.selKey)).join("")}</tbody></table></div>${paginationHtml({ total, page, perPage })}`;
    };
    const drawDetail = () => renderDetail($("#a-detail"), state.detail, { onClose: () => select(null), onAction: openAction });

    async function loadDetail() {
      const row = state.list.items.find((r) => r.key === state.selKey);
      if (!row) { state.detail = null; return drawDetail(); }
      const seq = ++detailSeq;
      try { const d = await api.alarm(row.alarmId, row.partNo ?? 0); if (seq === detailSeq) state.detail = { ok: true, d }; }
      catch { if (seq === detailSeq) state.detail = { ok: false }; }
      if (root.isConnected) drawDetail();
    }
    function select(key) { state.selKey = key; drawList(); loadDetail(); }
    function openAction() {
      const d = state.detail?.d;
      if (d) openActionModal(d, { onDone: (nd) => {
        state.detail = { ok: true, d: nd }; drawDetail();
        toast("조치가 등록되어 알람이 해결되었습니다.", "ok");
        window.dispatchEvent(new window.Event(ALARM_CHANGED));
      } });
    }

    async function load(page = state.list.page) {
      try {
        const r = await api.alarms({
          ...rangeParams(state.range), ...state.f,
          priority: state.prio ?? undefined,
          page, per_page: state.list.perPage,
        });
        state.list = { status: "ok", items: r.items, total: r.total, page: r.page, perPage: r.per_page, kpi: r.kpi };
        if (state.initId) {
          const found = r.items.find((x) => String(x.alarmId) === String(state.initId));
          state.selKey = found?.key ?? r.items[0]?.key ?? null;
          state.initId = null;
        } else if (!state.selKey || !r.items.some((x) => x.key === state.selKey)) {
          state.selKey = r.items[0]?.key ?? null;
        }
      } catch { state.list = { ...state.list, status: "error", items: [], total: 0 }; }
      if (!root.isConnected) return;
      drawList();
      await loadDetail();
    }

    // 페이지네이션 이벤트
    bindPagination($("#a-table"), {
      onPage: (p) => load(p),
      onPerPage: (n) => { state.list.perPage = n; load(1); },
    });

    root.addEventListener("click", (e) => {
      const t = e.target.closest("[data-tab]"), tr = e.target.closest("tr[data-key]"), a = e.target.closest("[data-act]")?.dataset.act;
      const pr = e.target.closest("[data-prio]");
      if (pr) {
        const p = Number(pr.dataset.prio);
        state.prio = state.prio === p ? null : p;   // 토글
        state.selKey = null;
        load(1);  // 서버사이드 필터 → 1페이지부터 재조회
        return;
      }
      if (t) { state.f[t.dataset.tab] = t.dataset.value; saveFilters("alarm", { category: state.f.category, part: state.f.part }); state.selKey = null; drawCtrl(); load(1); }
      else if (tr) select(tr.dataset.key);
      else if (a === "pdf" || a === "excel" || a === "csv")
        exportReport("alarm", a === "excel" ? "xlsx" : a, { ...rangeParams(state.range), category: state.f.category, part: state.f.part });
    });

    drawCtrl();
    drawDetail();
    api.parts().then((r) => { state.partNos = r.map((p) => p.part_no); drawCtrl(); }).catch(() => {});
    root.addEventListener("click", (e) => {
      const rg = e.target.closest("[data-range]");
      if (rg) openRangePicker(rg, state.range, (r) => { state.range = r; state.selKey = null; state.prio = null; drawCtrl(); load(1); });
    });
    const stop = startPolling(() => (isLiveRange(state.range) ? load(state.list.page) : undefined), { isActive: () => root.isConnected });
    const off = onAlarmChanged(() => load(state.list.page));
    return () => { stop(); off(); };
  },
};