/** 기준정보 공통 상세/편집 모달. 행 클릭 → 상세(읽기) → 수정 → 저장(PUT, updated_at 갱신). */
import { openModal } from "../../components/modal.js";
import { esc } from "../../utils.js";

// fields: [{ key, label, editable, type?, options? }]
// save(row, values) → Promise (PUT 호출)
export function openDetail({ title, row, fields, save, onDone }) {
  const shownOf = (f, v) => (f.options ? (f.options.find((o) => o.value === v)?.label ?? v) : (v ?? "-"));
  const viewRows = fields.map((f) =>
    `<tr><th style="text-align:left;width:34%">${esc(f.label)}</th><td>${esc(String(shownOf(f, row[f.key])))}</td></tr>`).join("");

  const modal = openModal({
    title: `${title} 상세`,
    width: 520,
    body: `<table class="tbl tbl--sm"><tbody>${viewRows}</tbody></table><p class="dt-err" style="color:#b91c1c;min-height:1.2em"></p>`,
    footer: `<button class="btn btn--ghost" id="dt-close">닫기</button><button class="btn btn--primary" id="dt-edit">수정</button>`,
  });

  modal.el.querySelector("#dt-close").addEventListener("click", () => modal.close());
  modal.el.querySelector("#dt-edit").addEventListener("click", () => toEdit());

  function toEdit() {
    const rows = fields.map((f) => {
      if (!f.editable) {
        return `<tr><th style="text-align:left;width:34%">${esc(f.label)}</th><td>${esc(String(shownOf(f, row[f.key])))}</td></tr>`;
      }
      const cur = row[f.key] ?? "";
      const input = f.options
        ? `<select id="e-${f.key}" class="input">${f.options.map((o) =>
            `<option value="${esc(o.value)}"${o.value === cur ? " selected" : ""}>${esc(o.label)}</option>`).join("")}</select>`
        : `<input id="e-${f.key}" class="input" type="${f.type || "text"}" value="${esc(String(cur))}" ${f.type === "number" ? 'step="any"' : ""}>`;
      return `<tr><th style="text-align:left;width:34%">${esc(f.label)}</th><td>${input}</td></tr>`;
    }).join("");
    modal.setBody(`<table class="tbl tbl--sm"><tbody>${rows}</tbody></table><p class="dt-err" style="color:#b91c1c;min-height:1.2em"></p>`);
    modal.setFoot(`<button class="btn btn--ghost" id="dt-cancel">취소</button><button class="btn btn--primary" id="dt-save">저장</button>`);
    modal.el.querySelector("#dt-cancel").addEventListener("click", () => modal.close());
    modal.el.querySelector("#dt-save").addEventListener("click", async () => {
      const values = {};
      for (const f of fields.filter((x) => x.editable)) {
        const raw = modal.el.querySelector(`#e-${f.key}`).value.trim();
        values[f.key] = f.type === "number" ? Number(raw) : raw;
      }
      try {
        await save(row, values);
        modal.close();
        onDone();
      } catch (e) {
        modal.el.querySelector(".dt-err").textContent = e.message || "저장에 실패했습니다.";
      }
    });
  }
}
