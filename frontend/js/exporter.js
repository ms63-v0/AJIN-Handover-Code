/**
 * 데이터 추출(PDF · Excel · CSV) 공통 처리.
 *  - 파일은 서버가 DB에서 직접 조회해 만든다(무결성). 화면은 조회 조건과 차트 이미지만 보낸다.
 *  - 진행 중에는 버튼을 잠그고, 실패하면 서버가 알려준 이유(예: 건수 한도 초과)를 그대로 보여준다.
 */
import { API_BASE } from "./config.js";
import { toast } from "./components/toast.js";

const LABEL = { pdf: "PDF", xlsx: "Excel", csv: "CSV" };
let busy = false;

/** @param report weld|vision|lot|alarm  @param format pdf|xlsx|csv  @param makeCharts () => [{title, image}] (PDF/Excel만) */
export async function exportReport(report, format, filters, makeCharts) {
  if (busy) return toast("이전 파일을 만드는 중입니다. 잠시 후 다시 시도하세요.", "warn");
  busy = true;
  document.body.classList.add("is-exporting");
  toast(`${LABEL[format]} 파일을 만드는 중입니다…`, "info", 2200);
  try {
    const charts = format !== "csv" && makeCharts ? makeCharts() : [];
    const res = await fetch(`${API_BASE}/api/export/${report}?format=${format}`, {
      method: "POST", credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ filters, charts }),
    });
    if (!res.ok) {
      let msg = `파일 생성에 실패했습니다. (${res.status})`;
      try { const d = (await res.json()).detail; if (typeof d === "string") msg = d; } catch { /* JSON 아님 */ }
      throw new Error(msg);
    }
    const blob = await res.blob();
    const m = (res.headers.get("Content-Disposition") || "").match(/filename\*=UTF-8''([^;]+)/);
    const name = m ? decodeURIComponent(m[1]) : `qms_export.${format}`;
    const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: name });
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    toast(`다운로드: ${name}`, "ok", 4000);
  } catch (e) {
    toast(e.message === "Failed to fetch" ? "서버에 연결할 수 없습니다." : e.message, "error", 6000);
  } finally {
    busy = false;
    document.body.classList.remove("is-exporting");
  }
}
