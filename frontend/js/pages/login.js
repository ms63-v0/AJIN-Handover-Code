/** 로그인 화면. 정의서: 입력값을 서버에서 해시 비교, 결과는 t_user_login_history 에 기록(서버가 처리). */
import { api } from "../api.js";
import { esc } from "../utils.js";

export function renderLogin(root, { onSuccess }) {
  root.innerHTML = `
    <div class="login">
      <div class="login__brand">
        <svg class="login__emblem" viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="26" fill="none" stroke="#f59e0b" stroke-width="7"/><path d="M32 14v18M32 32 16 42M32 32l16 10" stroke="#f59e0b" stroke-width="7" stroke-linecap="round"/></svg>
        <div class="login__wordmark"><b>AJIN</b><small>INDUSTRIAL CO., LTD.</small></div>
        <h1 class="login__title">품질 관리 시스템</h1>
      </div>
      <div class="login__panel">
        <form class="login__form" autocomplete="on">
          <label>아이디<input name="login_id" type="text" placeholder="입력하세요." autocomplete="username" maxlength="50" autofocus></label>
          <label>비밀번호<span class="pw-wrap"><input name="password" type="password" placeholder="입력하세요." autocomplete="current-password" maxlength="72"><button type="button" class="pw-eye" data-eye aria-label="비밀번호 보기">보기</button></span></label>
          <label class="login__remember"><span>자동 로그인</span><input name="remember" type="checkbox"></label>
          <button class="login__submit" type="submit" disabled>로그인</button>
          <p class="login__error" role="alert"></p>
        </form>
      </div>
    </div>`;

  const form = root.querySelector("form"), 
        btn = form.querySelector(".login__submit"), // 클래스명으로 명확하게 선택
        err = form.querySelector(".login__error");

  const filled = () => form.elements.login_id.value.trim() && form.elements.password.value; // 둘 다 입력해야 버튼 활성화
  const check = () => { btn.disabled = !filled(); err.textContent = ""; };

  form.addEventListener("input", check);
  form.addEventListener("change", check);

  form.querySelector("[data-eye]").addEventListener("click", (e) => { // 비밀번호 보기/숨기기
    const pw = form.elements.password, show = pw.type === "password";
    pw.type = show ? "text" : "password";
    e.currentTarget.textContent = show ? "숨기기" : "보기";
  });

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!filled()) return;
    btn.disabled = true;
    try {
      await api.login(form.elements.login_id.value.trim(), form.elements.password.value, form.elements.remember.checked);
      form.elements.password.value = "";
      onSuccess();
    } catch (ex) {
      err.textContent = ex.status ? ex.message : "서버에 연결할 수 없습니다.";
      btn.disabled = false;
    }
  });
}