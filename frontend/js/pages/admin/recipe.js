/** 레시피 탭: 목록 · 사용 여부 토글 · 등록(제품·번호·시작일 + 용접부위×파라미터 표 한 번에 입력). */
import { api } from "../../api.js";
import { esc } from "../../utils.js";
import { openModal } from "../../components/modal.js";

const USE_YN = (v) => (v === "Y" ? "사용" : "중지");

async function showTargets(recipeId) {
  const rows = await api.recipeTargets(recipeId);
  const html = rows.length
    ? `<table class="tbl tbl--sm"><thead><tr><th>용접부위</th><th>파라미터</th><th>목표</th><th>상한</th><th>하한</th></tr></thead><tbody>
        ${rows.map((t) => `<tr><td>${esc(t.weld_point_code)}</td><td>${esc(t.parameter_name)} (${esc(t.unit)})</td>
          <td>${t.target_value}</td><td>${t.upper_limit}</td><td>${t.lower_limit}</td></tr>`).join("")}
       </tbody></table>`
    : "<p>타겟이 없습니다.</p>";
  openModal({ title: "레시피 타겟 값", width: 620, body: html });
}

// 등록 양식: 헤더 + 용접부위 × 파라미터 입력 표
export async function openRecipeForm(onDone) {
  const [products, wps, prms] = await Promise.all([api.products(), api.weldPoints(), api.parameters()]);
  const activeWps = wps.filter((w) => w.use_yn === "Y");
  const activePrms = prms.filter((p) => p.use_yn === "Y");
  if (!products.length) { alert("사용 중인 제품이 없습니다."); return; }
  if (!activeWps.length || !activePrms.length) { alert("용접부위와 파라미터를 먼저 등록하세요."); return; }

  const head = activePrms.map((p) => `<th>${esc(p.parameter_name)}<br><small>(${esc(p.unit)})</small></th>`).join("");
  const rows = activeWps.map((w) => `<tr><td>${esc(w.weld_point_code)}</td>${activePrms.map((p) =>
    `<td class="rc-cell" data-w="${w.weld_point_id}" data-p="${p.parameter_id}">
       <input class="input rc-t" placeholder="목표" type="number" step="any" style="width:70px">
       <input class="input rc-u" placeholder="상한" type="number" step="any" style="width:70px">
       <input class="input rc-l" placeholder="하한" type="number" step="any" style="width:70px">
     </td>`).join("")}</tr>`).join("");

  const modal = openModal({
    title: "레시피 등록",
    width: 900,
    body: `<div class="stack">
      <label class="field"><span>제품 *</span><select id="rc-prod" class="input">${products.map((p) =>
        `<option value="${p.product_id}">${esc(p.product_code)} · ${esc(p.product_name)}</option>`).join("")}</select></label>
      <label class="field"><span>레시피 번호 *</span><input id="rc-no" class="input" placeholder="예: RCP-002"></label>
      <label class="field"><span>적용 시작일 * (YYYY-MM-DD)</span><input id="rc-from" class="input" placeholder="2026-11-01"></label>
      <div style="overflow-x:auto"><table class="tbl tbl--sm"><thead><tr><th>용접부위</th>${head}</tr></thead><tbody>${rows}</tbody></table></div>
      <p id="rc-err" style="color:#b91c1c;min-height:1.2em"></p>
    </div>`,
    footer: `<button class="btn btn--ghost" id="rc-cancel">취소</button><button class="btn btn--primary" id="rc-save">저장</button>`,
  });

  const err = modal.el.querySelector("#rc-err");
  const bad = (cell, on) => { cell.style.outline = on ? "2px solid #b91c1c" : ""; };

  // 칸 단위 상하한 검사 (하한 ≤ 목표 ≤ 상한)
  modal.el.querySelectorAll(".rc-cell").forEach((cell) => {
    cell.querySelectorAll("input").forEach((i) => i.addEventListener("input", () => {
      const t = parseFloat(cell.querySelector(".rc-t").value), u = parseFloat(cell.querySelector(".rc-u").value),
        l = parseFloat(cell.querySelector(".rc-l").value);
      const ok = [t, u, l].some(Number.isNaN) || (l <= t && t <= u);
      bad(cell, !ok);
    }));
  });

  modal.el.querySelector("#rc-cancel").addEventListener("click", () => modal.close());
  modal.el.querySelector("#rc-save").addEventListener("click", async () => {
    const no = modal.el.querySelector("#rc-no").value.trim();
    const from = modal.el.querySelector("#rc-from").value.trim();
    if (!no) { err.textContent = "레시피 번호를 입력하세요."; return; }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from)) { err.textContent = "적용 시작일을 YYYY-MM-DD로 입력하세요."; return; }

    const targets = [];
    let invalid = false, empty = 0;
    modal.el.querySelectorAll(".rc-cell").forEach((cell) => {
      const vals = ["t", "u", "l"].map((k) => cell.querySelector(`.rc-${k}`).value.trim());
      if (vals.every((v) => v === "")) { empty++; return; }
      const [t, u, l] = vals.map(Number);
      if (vals.some((v) => v === "") || [t, u, l].some(Number.isNaN) || !(l <= t && t <= u)) { invalid = true; bad(cell, true); return; }
      targets.push({ weld_point_id: Number(cell.dataset.w), parameter_id: Number(cell.dataset.p),
        target_value: t, upper_limit: u, lower_limit: l });
    });
    if (invalid) { err.textContent = "빨간 칸의 값을 확인하세요 (하한 ≤ 목표 ≤ 상한, 세 칸 모두 입력)."; return; }
    if (!targets.length) { err.textContent = "타겟 값을 한 칸 이상 입력하세요."; return; }

    try {
      await api.createRecipe({ product_id: Number(modal.el.querySelector("#rc-prod").value),
        recipe_no: no, effective_from: from, targets });
      modal.close();
      onDone();
    } catch (e) {
      err.textContent = e.message || "저장에 실패했습니다.";
    }
  });
}
