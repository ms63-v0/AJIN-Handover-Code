/**
 * Lot 조회 화면 (Figma: Dashboard - Lot - before/after).
 *  before: 검색 필터만, 결과 없음 (초기 상태)
 *  after:  조회 버튼 클릭 후 표 + 행 클릭 시 오른쪽 상세 패널
 */
import { api } from "../../api.js";
import { downloadCsv, fmtDateTime, today } from "../../utils.js";
import { renderSearchBar } from "./searchBar.js";
import { renderResultTable } from "./resultTable.js";
import { renderDetailPanel } from "./detailPanel.js";
import { startLiveFeed, eventChip, paintLive } from "./liveFeed.js";
import { loadFilters, saveFilters } from "../../settings.js";
import { exportReport } from "../../exporter.js";
import { defaultRange, rangeChip, rangeParams, rangeLabel, isLiveRange, openRangePicker } from "../../components/rangePicker.js";
import { bindPagination } from "../../components/pagination.js";


export const lotPage = {
  id: "lot",
  title: "Lot 조회",

  render(root) {
    root.innerHTML = `
      <div class="lot-layout" id="lot-wrap">
        <section class="lot-main">
          <div id="lot-search"></div>
          <div id="lot-result"></div>
        </section>
        <aside id="lot-detail" class="lot-detail" hidden></aside>
      </div>`;
    const $ = (s) => root.querySelector(s);

    const state = {
      filters: { range: defaultRange(), lot_no: "", ...loadFilters("lot", { part: "", result: "" }) },
      applied: null,
      partNos: [],
      list: { status: "idle", items: [], total: 0, page: 1, perPage: 50 },
      newIds: new Set(),
      selectedId: null,
      detail: { status: "idle", data: null },
      live: { online: false, items: [] },
    };
    let detailSeq = 0;
    const lotParams = ({ range, ...rest }) => ({ ...rest, ...rangeParams(range) });

    const paintLiveEl = () => paintLive(root.querySelector(".live"), state.live);

    const drawList = () => {
      if (!root.isConnected) return;
      renderResultTable($("#lot-result"), {
        ...state.list, partNos: state.partNos,
        selectedId: state.selectedId, newIds: state.newIds,
      });
      paintLiveEl();
    };

    const drawDetail = () => {
      if (!root.isConnected) return;
      const el = $("#lot-detail");
      el.hidden = state.selectedId == null;
      if (!el.hidden) {
        renderDetailPanel(el, state.detail, { onClose: () => select(null) });
      }
    };

    async function select(id) {
      state.selectedId = id;
      drawList();
      if (id == null) {
        state.detail = { status: "idle", data: null };
        return drawDetail();
      }
      const seq = ++detailSeq;
      state.detail = { status: "loading", data: null };
      drawDetail();
      try {
        const data = await api.lot(id);
        if (seq !== detailSeq) return;
        state.detail = { status: "ok", data };
      } catch {
        if (seq !== detailSeq) return;
        state.detail = { status: "error", data: null };
      }
      drawDetail();
    }

    async function fetchList(page = 1) {
      if (!state.applied) return;
      state.list = { ...state.list, status: "loading", page };
      drawList();
      try {
        const r = await api.lots({ ...lotParams(state.applied), page, per_page: state.list.perPage });
        state.list = { status: "ok", items: r.items, total: r.total, page: r.page, perPage: r.per_page };
      } catch {
        state.list = { ...state.list, status: "error", items: [], total: 0 };
      }
      drawList();
    }

    async function search() {
      saveFilters("lot", { part: state.filters.part, result: state.filters.result });
      state.applied = { ...state.filters };
      state.newIds = new Set();
      state.selectedId = null;
      drawDetail();
      await fetchList(1);  // 새 조회 시 1페이지로 리셋
    }

    // 실시간 수신 후 목록만 조용히 갱신 (현재 페이지 유지)
    async function refresh() {
      if (!state.applied) return;
      try {
        const r = await api.lots({ ...lotParams(state.applied), page: state.list.page, per_page: state.list.perPage });
        const known = new Set(state.list.items.map((i) => i.lot_id));
        state.newIds = new Set(r.items.filter((i) => !known.has(i.lot_id)).map((i) => i.lot_id));
        state.list = { status: "ok", items: r.items, total: r.total, page: r.page, perPage: r.per_page };
        drawList();
      } catch { /* 일시 오류: 다음 갱신에 복구 */ }
    }


    // ─── 이벤트 ───
    $("#lot-result").addEventListener("click", (e) => {
      const tr = e.target.closest("tr[data-id]");
      if (tr) select(Number(tr.dataset.id));
    });

    // 페이지네이션 이벤트
    bindPagination($("#lot-result"), {
      onPage: (p) => fetchList(p),
      onPerPage: (n) => { state.list.perPage = n; fetchList(1); },
    });

    root.addEventListener("click", (e) => {
      const act = e.target.closest("[data-act]")?.dataset.act;
      if (act === "search") search();
      else if (act === "pdf" || act === "excel" || act === "csv")
        exportReport("lot", act === "excel" ? "xlsx" : act, lotParams(state.applied ?? state.filters));
    });
    root.addEventListener("input", (e) => {
      if (e.target.name === "lot_no") {
        e.target.value = e.target.value.replace(/\D/g, "");
        state.filters.lot_no = e.target.value;
      }
    });
    root.addEventListener("click", (e) => {
      const rg = e.target.closest("[data-range]");
      if (rg) openRangePicker(rg, state.filters.range, (r) => {
        state.filters.range = r;
        renderSearchBar($("#lot-search"), state.filters, { partNos: state.partNos });
      }, { title: "LOT 종료 일시 (최대 31일)" });
    });
    root.addEventListener("click", (e) => {
      const opt = e.target.closest("[data-name]");
      if (!opt) return;
      state.filters[opt.dataset.name] = opt.dataset.value;
      opt.closest(".seg, .chip")?.querySelectorAll("[data-name]")
        .forEach((b) => b.classList.toggle("is-active", b === opt));
    });

    // ─── 초기 렌더 ───
    const stopLive = startLiveFeed({
      isActive: () => root.isConnected,
      onStatus: (online) => { state.live.online = online; paintLiveEl(); },
      onEvents: (events, isInitial) => {
        state.live.items = [...state.live.items, ...events.map(eventChip)].slice(-3);
        paintLiveEl();
        if (!isInitial && events.some((e) => e.type === "VISION")) refresh();
      },
    });

    api.parts()
      .then((r) => { state.partNos = r.map((p) => p.part_no); })
      .catch(() => {})
      .finally(() => {
        renderSearchBar($("#lot-search"), state.filters, { partNos: state.partNos });
        drawList();
      });

    return () => stopLive();
  },
};