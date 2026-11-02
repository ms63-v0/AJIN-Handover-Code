/** 백엔드 호출 전용 모듈. 화면 코드는 fetch를 직접 쓰지 않고 api.* 만 사용한다. */
import { API_BASE } from "./config.js";

let online = true; // 서버 연결 상태가 바뀔 때만 이벤트를 보낸다 (qms:offline / qms:online)
const setOnline = (v) => { if (v !== online) { online = v; window.dispatchEvent(new window.Event(v ? "qms:online" : "qms:offline")); } };

async function request(method, path, params = {}, body) {
  const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== "" && v != null)).toString(); // 빈 값 제외
  let res;
  try {
    res = await fetch(`${API_BASE}${path}${qs ? `?${qs}` : ""}`, {
      method,
      credentials: "include", // 세션 쿠키 전송
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    setOnline(false); // 네트워크 오류 = 서버 꺼짐/주소 불일치
    throw Object.assign(new Error("서버에 연결할 수 없습니다."), { status: 0 });
  }
  setOnline(true);
  if (res.status === 401 && !path.startsWith("/api/auth/login")) window.dispatchEvent(new window.Event("qms:unauth")); // 세션 만료 → 로그인 화면
  if (!res.ok) {
    let msg = `요청 실패 (${res.status})`;
    try { const d = (await res.json()).detail; msg = typeof d === "string" ? d : "입력값을 확인하세요."; } catch { /* JSON 아님 */ }
    throw Object.assign(new Error(msg), { status: res.status });
  }
  return res.json();
}

export const api = {
  // 인증 / 시스템
  login: (login_id, password, remember) => request("POST", "/api/auth/login", {}, { login_id, password, remember }),
  logout: () => request("POST", "/api/auth/logout"),
  me: () => request("GET", "/api/auth/me"),
  sessions: () => request("GET", "/api/auth/sessions"),
  resetDb: () => request("POST", "/api/auth/reset-db"),
  status: () => request("GET", "/api/status"),
  // 화면별
  parts: () => request("GET", "/api/parts"),
  lots: (f) => request("GET", "/api/lots", f),
  lot: (id) => request("GET", `/api/lots/${id}`),
  feed: (after) => request("GET", "/api/live/feed", { after }),
  dashboard: (p) => request("GET", "/api/dashboard", p),
  weld: (p) => request("GET", "/api/weld", p),
  weldTable: (p) => request("GET", "/api/weld/table", p),
  vision: (p) => request("GET", "/api/vision", p),
  alarms: (p) => request("GET", "/api/alarms", p),
  unresolved: () => request("GET", "/api/alarms/unresolved"),
  alarm: (id, part) => request("GET", `/api/alarms/${id}`, { part }),
  registerAction: (id, body) => request("POST", `/api/alarms/${id}/actions`, {}, body),
  ackAlarm: (id) => request("POST", `/api/alarms/${id}/ack`),
  // 기준정보 관리 (관리자)
  lines: () => request("GET", "/api/lines"),
  createLine: (body) => request("POST", "/api/admin/lines", {}, body),
  stations: (lineId) => request("GET", `/api/lines/${lineId}/stations`),
  createStation: (body) => request("POST", "/api/admin/stations", {}, body),
  machines: () => request("GET", "/api/machines"),
  createMachine: (body) => request("POST", "/api/admin/machines", {}, body),
  weldPoints: () => request("GET", "/api/admin/weld-points"),
  createWeldPoint: (body) => request("POST", "/api/admin/weld-points", {}, body),
  parameters: () => request("GET", "/api/admin/parameters"),
  createParameter: (body) => request("POST", "/api/admin/parameters", {}, body),
  products: () => request("GET", "/api/admin/products"),
  recipes: () => request("GET", "/api/admin/recipes"),
  recipeTargets: (id) => request("GET", `/api/admin/recipes/${id}/targets`),
  createRecipe: (body) => request("POST", "/api/admin/recipes", {}, body),
  setRecipeUse: (id, use_yn) => request("PUT", `/api/admin/recipes/${id}/use`, {}, { use_yn }),
  updateLine: (id, body) => request("PUT", `/api/admin/lines/${id}`, {}, body),
  updateStation: (id, body) => request("PUT", `/api/admin/stations/${id}`, {}, body),
  updateMachine: (id, body) => request("PUT", `/api/admin/machines/${id}`, {}, body),
  updateWeldPoint: (id, body) => request("PUT", `/api/admin/weld-points/${id}`, {}, body),
  updateParameter: (id, body) => request("PUT", `/api/admin/parameters/${id}`, {}, body),
};