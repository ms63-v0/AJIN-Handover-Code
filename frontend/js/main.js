/** 앱 진입점: 테마 적용 → 로그인 여부 확인 → 로그인 화면 또는 (사이드바/헤더 + 본문). 본문은 주소(#/화면id)에 따라 교체한다. */
import { api } from "./api.js";
import { DEFAULT_PAGE } from "./config.js";
import { mountSidebar, setActiveNav } from "./components/sidebar.js";
import { mountHeader, setHeaderTitle, setHeaderUser } from "./components/header.js";
import { toast } from "./components/toast.js";
import { PAGES } from "./pages/index.js";
import { renderLogin } from "./pages/login.js";
import { session } from "./session.js";
import { applyTheme } from "./settings.js";

applyTheme();

const appEl = document.querySelector(".app");
const loginRoot = document.getElementById("login-root");
const sidebar = document.getElementById("sidebar");
const header = document.getElementById("header");
const banner = document.getElementById("offline-banner");
let pageRoot = document.getElementById("page");

let mounted = false;
let cleanup = null; // 현재 화면이 반환한 정리 함수(타이머·리스너 해제)

function route() {
  if (appEl.hidden) return;
  cleanup?.();
  cleanup = null;
  const fresh = pageRoot.cloneNode(false); // 본문 요소 교체 → 이전 화면의 리스너/타이머(isConnected 검사)가 함께 정리된다
  pageRoot.replaceWith(fresh);
  pageRoot = fresh;
    let id = location.hash.replace("#/", "").split("?")[0]; // ?id=N 같은 파라미터는 화면 모듈이 직접 읽는다
  // 관리자 전용 화면: ADMIN이 아니면 기본 화면으로 보낸다 (메뉴 숨김과 같은 기준)
  if (id === "admin" && session.user?.role !== "ADMIN") id = DEFAULT_PAGE;
  const page = PAGES[id] ?? PAGES[DEFAULT_PAGE];
  setActiveNav(sidebar, page.id);
  setHeaderTitle(header, page.title);
  cleanup = page.render(pageRoot) ?? null;
}

function showLogin() {
  cleanup?.();
  cleanup = null;
  session.user = null;
  appEl.hidden = true;
  loginRoot.hidden = false;
  document.title = "로그인 · AJIN QMS";
  renderLogin(loginRoot, { onSuccess: boot });
}

async function boot() {
  let me;
  try { me = await api.me(); } catch { return showLogin(); }
  session.user = me.user;
  loginRoot.hidden = true;
  appEl.hidden = false;
  if (!mounted) {
    mountSidebar(sidebar, me.user);
    const h = mountHeader(header, { onLogout: () => api.logout().catch(() => {}).finally(() => { showLogin(); toast("로그아웃되었습니다."); }) });
    window.addEventListener("hashchange", route);
    window.addEventListener("qms:reload", route); // 설정 변경·데이터 초기화 후 현재 화면 다시 그리기
    mounted = true;
    h.loadBell();
  }
  setHeaderUser(header, me.user, me.online);
  route();
}

// 세션 만료 → 로그인 화면 / 서버 연결 끊김·복구 배너
window.addEventListener("qms:unauth", () => { if (loginRoot.hidden) { showLogin(); toast("세션이 만료되어 다시 로그인해야 합니다.", "warn"); } });
window.addEventListener("qms:offline", () => { banner.hidden = false; });
window.addEventListener("qms:online", () => { if (!banner.hidden) { banner.hidden = true; toast("서버 연결이 복구되었습니다.", "ok"); } });

boot();
