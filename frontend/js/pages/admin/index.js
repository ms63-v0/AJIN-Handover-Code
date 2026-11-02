/** 기준정보 관리(관리자 전용). 6개 항목 모두 행 클릭 → 상세 → 수정(사용 여부 포함) → 저장(updated_at 갱신). 삭제 없음. */
import { api } from "../../api.js";
import { esc } from "../../utils.js";
import { openModal } from "../../components/modal.js";
import { openDetail } from "./detail.js";
import { openRecipeForm } from "./recipe.js";

const TABS = [
  { id: "line", label: "라인" },
  { id: "station", label: "공정" },
  { id: "machine", label: "설비" },
  { id: "weldpoint", label: "용접부위" },
  { id: "parameter", label: "파라미터" },
  { id: "recipe", label: "레시피" },
];
const USE = [{ value: "Y", label: "사용" }, { value: "N", label: "중지" }];
const MACHINE_TYPES = [
  { value: "WELDER", label: "용접기 (WELDER)" }, { value: "VISION", label: "비전 (VISION)" },
  { value: "ROBOT_LOAD", label: "로봇 로딩 (ROBOT_LOAD)" },
];
const DATA_TYPES = [
  { value: "NUMERIC", label: "실수 (NUMERIC)" }, { value: "INT", label: "정수 (INT)" },
  { value: "BOOLEAN", label: "참/거짓 (BOOLEAN)" }, { value: "STRING", label: "문자 (STRING)" },
];
const STATION_TYPES = [
  { value: "WELD", label: "용접 (WELD)" }, { value: "LOAD", label: "로딩 (LOAD)" }, { value: "VISION", label: "비전 (VISION)" },
];
const USE_YN = (v) => (v === "Y" ? "사용" : "중지");

export const adminPage = {
  id: "admin",
  title: "기준정보 관리",
  render(root) {
    let current = "line";
    const draw = async () => {
      root.innerHTML = `
        <div class="stack"><h2 class="section-title">기준정보 관리</h2>
        <div class="tabgroup">${TABS.map((t) =>
          `<button class="tab${t.id === current ? " is-active" : ""}" data-tab="${t.id}">${t.label}</button>`).join("")}</div>
        <div id="admin-body"></div></div>`;
      root.querySelectorAll("[data-tab]").forEach((b) =>
        b.addEventListener("click", () => { current = b.dataset.tab; draw(); }));
      const body = root.querySelector("#admin-body");
      const map = { line: drawLine, station: drawStation, machine: drawMachine,
                    weldpoint: drawWeldPoint, parameter: drawParameter, recipe: drawRecipe };
      await map[current](body);
    };
    draw();
    return () => { root.innerHTML = ""; };
  },
};

// 등록 양식 (사용 여부 선택 포함, 기본 Y)
function openForm({ title, fields, onSubmit, onDone }) {
  const withUse = [...fields, { name: "use_yn", label: "사용 여부", options: USE, value: "Y" }];
  const rows = withUse.map((f) => {
    const id = `f-${f.name}`;
    const input = f.options
      ? `<select id="${id}" class="input">${f.options.map((o) =>
          `<option value="${esc(o.value)}"${o.value === (f.value ?? "") ? " selected" : ""}>${esc(o.label)}</option>`).join("")}</select>`
      : `<input id="${id}" class="input" type="${f.type || "text"}" placeholder="${esc(f.placeholder || "")}" ${f.type === "number" ? 'min="1"' : ""}>`;
    return `<label class="field"><span>${esc(f.label)}${f.required ? " *" : ""}</span>${input}</label>`;
  }).join("");

  const modal = openModal({
    title, width: 460,
    body: `<form class="stack">${rows}<p id="f-err" style="color:#b91c1c;min-height:1.2em"></p></form>`,
    footer: `<button type="button" class="btn btn--ghost" id="f-cancel">취소</button>
             <button type="button" class="btn btn--primary" id="f-save">등록</button>`,
  });
  const errEl = modal.el.querySelector("#f-err");
  modal.el.querySelector("#f-cancel").addEventListener("click", () => modal.close());
  modal.el.querySelector("#f-save").addEventListener("click", async () => {
    const values = {};
    for (const f of withUse) {
      const v = modal.el.querySelector(`#f-${f.name}`).value.trim();
      values[f.name] = f.type === "number" ? Number(v) : v;
    }
    const missing = withUse.find((f) => f.required && (values[f.name] === "" || Number.isNaN(values[f.name])));
    if (missing) { errEl.textContent = `${missing.label}을(를) 입력하세요.`; return; }
    try { await onSubmit(values); modal.close(); onDone(); }
    catch (e) { errEl.textContent = e.message || "등록에 실패했습니다."; }
  });
}

// 공통 목록 틀
function listShell(body, { addId, addLabel, selectHtml = "" }) {
  body.innerHTML = `<div class="toolbar">${selectHtml}${addId ? `<button id="${addId}" class="btn btn--primary">${addLabel}</button>` : ""}</div>
    <div id="list">불러오는 중…</div>`;
  return { list: body.querySelector("#list"), add: addId ? body.querySelector(`#${addId}`) : null };
}

// 행 클릭 → 상세. rows의 각 행에 data-i 부여 후 위임.
function bindRows(list, rows, open) {
  list.querySelectorAll("tr[data-i]").forEach((tr) =>
    tr.addEventListener("click", () => open(rows[Number(tr.dataset.i)])));
}

// 라인 선택 (공정·설비 탭 공통)
async function pickLine(body, onChange) {
  const lines = await api.lines();
  if (!lines.length) { body.innerHTML = "<p>먼저 라인을 등록하세요.</p>"; return null; }
  const selectHtml = `<label>라인 <select id="sel-line" class="input">${lines.map((l) =>
    `<option value="${l.line_id}">${esc(l.line_code)} · ${esc(l.line_name)}</option>`).join("")}</select></label>`;
  return { selectHtml, lines, onChange };
}

// ── 라인 ─────────────────────────────────────────
async function drawLine(body) {
  const { list, add } = listShell(body, { addId: "line-add", addLabel: "라인 등록" });
  let rows = [];
  const load = async () => {
    rows = await api.lines();
    list.innerHTML = rows.length
      ? `<table class="tbl tbl--sm"><thead><tr><th>코드</th><th>이름</th><th>사용</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr data-i="${i}" style="cursor:pointer"><td>${esc(r.line_code)}</td><td>${esc(r.line_name)}</td><td>${USE_YN(r.use_yn)}</td></tr>`).join("")}
         </tbody></table>` : "<p>등록된 라인이 없습니다.</p>";
    bindRows(list, rows, (row) => openDetail({
      title: "라인", row, save: (r, v) => api.updateLine(r.line_id, v), onDone: load,
      fields: [
        { key: "line_code", label: "라인 코드", editable: false },
        { key: "line_name", label: "라인 이름", editable: true },
        { key: "use_yn", label: "사용 여부", editable: true, options: USE },
      ],
    }));
  };
  add.addEventListener("click", () => openForm({
    title: "라인 등록",
    fields: [
      { name: "line_code", label: "라인 코드", required: true, placeholder: "예: HW01" },
      { name: "line_name", label: "라인 이름", required: true, placeholder: "예: LX3 2라인" },
    ],
    onSubmit: (v) => api.createLine(v), onDone: load,
  }));
  await load();
}

// ── 공정 ─────────────────────────────────────────
async function drawStation(body) {
  const picked = await pickLine(body, null);
  if (!picked) return;
  const { list, add } = listShell(body, { addId: "st-add", addLabel: "공정 등록", selectHtml: picked.selectHtml });
  const sel = body.querySelector("#sel-line");
  let rows = [];
  const load = async () => {
    rows = await api.stations(sel.value);
    list.innerHTML = rows.length
      ? `<table class="tbl tbl--sm"><thead><tr><th>순번</th><th>코드</th><th>공정명</th><th>유형</th><th>사용</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr data-i="${i}" style="cursor:pointer"><td>${r.sequence_no}</td><td>${esc(r.station_code)}</td><td>${esc(r.station_name)}</td><td>${esc(r.station_type)}</td><td>${USE_YN(r.use_yn)}</td></tr>`).join("")}
         </tbody></table>` : "<p>이 라인에 등록된 공정이 없습니다.</p>";
    bindRows(list, rows, (row) => openDetail({
      title: "공정", row, save: (r, v) => api.updateStation(r.station_id, v), onDone: load,
      fields: [
        { key: "station_code", label: "공정 코드", editable: false },
        { key: "station_name", label: "공정명", editable: true },
        { key: "station_type", label: "공정 유형", editable: true, options: STATION_TYPES },
        { key: "sequence_no", label: "순번", editable: true, type: "number" },
        { key: "use_yn", label: "사용 여부", editable: true, options: USE },
      ],
    }));
  };
  sel.addEventListener("change", load);
  add.addEventListener("click", () => openForm({
    title: "공정 등록",
    fields: [
      { name: "station_code", label: "공정 코드", required: true, placeholder: "예: ST01" },
      { name: "station_name", label: "공정명", required: true, placeholder: "예: 용접 1공정" },
      { name: "station_type", label: "공정 유형", required: true, options: STATION_TYPES },
      { name: "sequence_no", label: "순번", type: "number", required: true, placeholder: "1 이상" },
    ],
    onSubmit: (v) => api.createStation({ ...v, line_id: Number(sel.value) }), onDone: load,
  }));
  await load();
}

// ── 설비 ─────────────────────────────────────────
async function drawMachine(body) {
  const { list, add } = listShell(body, { addId: "mc-add", addLabel: "설비 등록" });
  let rows = [], stations = [];
  const load = async () => {
    [rows, stations] = await Promise.all([api.machines(), api.stations(await firstLineId())]);
    list.innerHTML = rows.length
      ? `<table class="tbl tbl--sm"><thead><tr><th>설비 코드</th><th>설비명</th><th>유형</th><th>공정</th><th>사용</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr data-i="${i}" style="cursor:pointer"><td>${esc(r.machine_code)}</td><td>${esc(r.machine_name)}</td><td>${esc(r.machine_type)}</td><td>${esc(r.station_name || "")}</td><td>${USE_YN(r.use_yn)}</td></tr>`).join("")}
         </tbody></table>` : "<p>등록된 설비가 없습니다.</p>";
    bindRows(list, rows, (row) => openDetail({
      title: "설비", row, save: (r, v) => api.updateMachine(r.machine_id, v), onDone: load,
      fields: [
        { key: "machine_code", label: "설비 코드", editable: false },
        { key: "machine_name", label: "설비명", editable: true },
        { key: "machine_type", label: "설비 유형", editable: false },
        { key: "model_name", label: "모델명", editable: true },
        { key: "manufacturer", label: "제조사", editable: true },
        { key: "install_date", label: "설치일", editable: true },
        { key: "use_yn", label: "사용 여부", editable: true, options: USE },
      ],
    }));
  };
  add.addEventListener("click", async () => {
    const sts = stations;
    if (!sts.length) { alert("먼저 공정을 등록하세요."); return; }
    openForm({
      title: "설비 등록",
      fields: [
        { name: "station_id", label: "소속 공정", required: true, options: sts.map((s) => ({ value: s.station_id, label: `${s.station_code} · ${s.station_name}` })) },
        { name: "machine_code", label: "설비 코드", required: true, placeholder: "예: WM01" },
        { name: "machine_name", label: "설비명", required: true, placeholder: "예: 1번 용접기" },
        { name: "machine_type", label: "설비 유형", required: true, options: MACHINE_TYPES },
        { name: "model_name", label: "모델명", required: true, placeholder: "예: RSW-3000" },
        { name: "manufacturer", label: "제조사", required: true, placeholder: "예: ABC" },
        { name: "install_date", label: "설치일 (YYYY-MM-DD)", required: true, placeholder: "2026-01-01" },
      ],
      onSubmit: (v) => api.createMachine({ ...v, station_id: Number(v.station_id) }), onDone: load,
    });
  });
  await load();
}

async function firstLineId() {
  const lines = await api.lines();
  return lines.length ? lines[0].line_id : 0;
}

// ── 용접부위 ─────────────────────────────────────
async function drawWeldPoint(body) {
  const { list, add } = listShell(body, { addId: "wp-add", addLabel: "용접부위 등록" });
  let rows = [], welders = [];
  const load = async () => {
    [rows, welders] = await Promise.all([api.weldPoints(),
      api.machines().then((ms) => ms.filter((m) => m.machine_type === "WELDER"))]);
    list.innerHTML = rows.length
      ? `<table class="tbl tbl--sm"><thead><tr><th>순번</th><th>용접기</th><th>부위 코드</th><th>용접 유형</th><th>위치</th><th>사용</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr data-i="${i}" style="cursor:pointer"><td>${r.sequence_no}</td><td>${esc(r.machine_name || "")}</td><td>${esc(r.weld_point_code)}</td><td>${esc(r.weld_type)}</td><td>${esc(r.position_desc || "")}</td><td>${USE_YN(r.use_yn)}</td></tr>`).join("")}
         </tbody></table>` : "<p>등록된 용접부위가 없습니다.</p>";
    bindRows(list, rows, (row) => openDetail({
      title: "용접부위", row, save: (r, v) => api.updateWeldPoint(r.weld_point_id, v), onDone: load,
      fields: [
        { key: "weld_point_code", label: "부위 코드", editable: false },
        { key: "weld_type", label: "용접 유형", editable: false },
        { key: "position_desc", label: "위치 설명", editable: true },
        { key: "vision_machine_id", label: "비전 설비 ID", editable: true, type: "number" },
        { key: "use_yn", label: "사용 여부", editable: true, options: USE },
      ],
    }));
  };
  add.addEventListener("click", () => {
    if (!welders.length) { alert("용접기(WELDER) 설비가 없습니다. 먼저 설비를 등록하세요."); return; }
    openForm({
      title: "용접부위 등록",
      fields: [
        { name: "weld_machine_id", label: "용접기(설비)", required: true, options: welders.map((w) => ({ value: w.machine_id, label: `${w.machine_code} · ${w.machine_name}` })) },
        { name: "weld_point_code", label: "부위 코드", required: true, placeholder: "예: WP01" },
        { name: "weld_type", label: "용접 유형", required: true, placeholder: "예: SPOT" },
        { name: "sequence_no", label: "순번", type: "number", required: true, placeholder: "1 이상" },
        { name: "position_desc", label: "위치 설명", placeholder: "예: 좌측 프레임 상단" },
      ],
      onSubmit: (v) => api.createWeldPoint({ ...v, weld_machine_id: Number(v.weld_machine_id) }), onDone: load,
    });
  });
  await load();
}

// ── 파라미터 ─────────────────────────────────────
async function drawParameter(body) {
  const { list, add } = listShell(body, { addId: "pm-add", addLabel: "파라미터 등록" });
  let rows = [];
  const load = async () => {
    rows = await api.parameters();
    list.innerHTML = rows.length
      ? `<table class="tbl tbl--sm"><thead><tr><th>코드</th><th>이름</th><th>단위</th><th>타입</th><th>사용</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr data-i="${i}" style="cursor:pointer"><td>${esc(r.parameter_code)}</td><td>${esc(r.parameter_name)}</td><td>${esc(r.unit)}</td><td>${esc(r.data_type)}</td><td>${USE_YN(r.use_yn)}</td></tr>`).join("")}
         </tbody></table>` : "<p>등록된 파라미터가 없습니다.</p>";
    bindRows(list, rows, (row) => openDetail({
      title: "파라미터", row, save: (r, v) => api.updateParameter(r.parameter_id, v), onDone: load,
      fields: [
        { key: "parameter_code", label: "파라미터 코드", editable: false },
        { key: "parameter_name", label: "파라미터명", editable: true },
        { key: "unit", label: "단위", editable: true },
        { key: "data_type", label: "데이터 타입", editable: true, options: DATA_TYPES },
        { key: "use_yn", label: "사용 여부", editable: true, options: USE },
      ],
    }));
  };
  add.addEventListener("click", () => openForm({
    title: "파라미터 등록",
    fields: [
      { name: "parameter_code", label: "파라미터 코드", required: true, placeholder: "예: WELD_CURRENT" },
      { name: "parameter_name", label: "파라미터명", required: true, placeholder: "예: 용접 전류" },
      { name: "unit", label: "단위", required: true, placeholder: "예: kA" },
      { name: "data_type", label: "데이터 타입", required: true, options: DATA_TYPES },
    ],
    onSubmit: (v) => api.createParameter(v), onDone: load,
  }));
  await load();
}

// ── 레시피 (상세에서 사용 여부만 수정, 버전 체계 유지) ──
async function drawRecipe(body) {
  const { list, add } = listShell(body, { addId: "rc-add", addLabel: "레시피 등록" });
  let rows = [];
  const load = async () => {
    rows = await api.recipes();
    list.innerHTML = rows.length
      ? `<table class="tbl tbl--sm"><thead><tr><th>레시피</th><th>제품</th><th>버전</th><th>적용 시작</th><th>적용 종료</th><th>사용</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr data-i="${i}" style="cursor:pointer"><td>${esc(r.recipe_no)}</td><td>${esc(r.product_name)}</td><td>${r.version}</td>
            <td>${esc(String(r.effective_from).slice(0, 10))}</td><td>${r.effective_to ? esc(String(r.effective_to).slice(0, 10)) : "-"}</td>
            <td>${USE_YN(r.use_yn)}</td></tr>`).join("")}
         </tbody></table>` : "<p>등록된 레시피가 없습니다.</p>";
    bindRows(list, rows, (row) => openDetail({
      title: "레시피", row, save: (r, v) => api.setRecipeUse(r.recipe_id, v.use_yn), onDone: load,
      fields: [
        { key: "recipe_no", label: "레시피 번호", editable: false },
        { key: "product_name", label: "제품", editable: false },
        { key: "version", label: "버전", editable: false },
        { key: "effective_from", label: "적용 시작", editable: false },
        { key: "effective_to", label: "적용 종료", editable: false },
        { key: "use_yn", label: "사용 여부", editable: true, options: USE },
      ],
    }));
  };
  add.addEventListener("click", () => openRecipeForm(load));
  await load();
}
