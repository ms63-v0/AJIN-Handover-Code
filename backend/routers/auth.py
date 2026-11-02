"""로그인 / 로그아웃 / 내 정보. (정의서 '로그인' 시트)

- 입력 비밀번호를 해시로 비교하고, 응답에는 해시를 절대 포함하지 않는다.
- 성공/실패 결과를 t_user_login_history 에 INSERT, 성공이면 m_user.last_login_at 갱신.
- 연속 실패 MAX_FAILED_LOGIN회면 LOCK_MINUTES분 잠금 (m_user.failed_login_count / locked_until).
"""
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from backend.common import FMT
from backend.config import COOKIE_NAME, LOCK_MINUTES, MAX_FAILED_LOGIN, REMEMBER_DAYS, SESSION_HOURS
from backend.db import execute, query
from backend.security import make_token, require_user, verify_password

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginBody(BaseModel):
    login_id: str = Field(min_length=1, max_length=50)
    password: str = Field(min_length=1, max_length=128)
    remember: bool = False  # 자동 로그인: 쿠키를 REMEMBER_DAYS일 유지


def _log(login_id: str, user_id, result: str, ip: str) -> None:
    execute("INSERT INTO t_user_login_history (user_id, attempted_login_id, login_result, ip_address, login_time) VALUES (?, ?, ?, ?, ?)",
            (user_id, login_id, result, ip, datetime.now().strftime(FMT)))


@router.post("/login")
def login(body: LoginBody, request: Request, response: Response):
    ip, now = (request.client.host if request.client else ""), datetime.now()
    rows = query("SELECT * FROM m_user WHERE login_id = ?", (body.login_id,))
    fail = HTTPException(status_code=401, detail="아이디 또는 비밀번호가 올바르지 않습니다.")  # 어느 쪽이 틀렸는지 알려주지 않는다
    if not rows or rows[0]["use_yn"] != "Y":
        _log(body.login_id, None, "FAIL_NO_USER", ip)
        raise fail
    u = rows[0]
    if u["locked_until"] and datetime.strptime(u["locked_until"], FMT) > now:
        _log(body.login_id, u["user_id"], "FAIL_LOCKED", ip)
        left = int((datetime.strptime(u["locked_until"], FMT) - now).total_seconds() // 60) + 1
        raise HTTPException(status_code=401, detail=f"로그인 실패가 반복되어 계정이 잠겼습니다. {left}분 후 다시 시도하세요.")
    if not verify_password(body.password, u["password_hash"]):
        n = u["failed_login_count"] + 1
        lock = (now + timedelta(minutes=LOCK_MINUTES)).strftime(FMT) if n >= MAX_FAILED_LOGIN else None
        execute("UPDATE m_user SET failed_login_count = ?, locked_until = ? WHERE user_id = ?", (0 if lock else n, lock, u["user_id"]))
        _log(body.login_id, u["user_id"], "FAIL_PW", ip)
        raise fail
    execute("UPDATE m_user SET failed_login_count = 0, locked_until = NULL, last_login_at = ? WHERE user_id = ?", (now.strftime(FMT), u["user_id"]))
    _log(body.login_id, u["user_id"], "SUCCESS", ip)
    ttl = REMEMBER_DAYS * 86400 if body.remember else SESSION_HOURS * 3600
    user = {"uid": u["user_id"], "name": u["user_name"], "role": u["role_code"], "dept": u["department"]}
    response.set_cookie(COOKIE_NAME, make_token(user, ttl), httponly=True, samesite="lax", max_age=ttl if body.remember else None, path="/")
    return {"user": user}


@router.post("/logout")
def logout(response: Response):
    response.delete_cookie(COOKIE_NAME, path="/")
    return {"ok": True}


@router.get("/me")
def me(user: dict = Depends(require_user)):
    """현재 사용자 + 접속 중 인원(최근 30분 내 로그인 성공한 사용자 수)."""
    since = (datetime.now() - timedelta(minutes=30)).strftime(FMT)
    n = query("SELECT COUNT(DISTINCT user_id) AS n FROM t_user_login_history WHERE login_result = 'SUCCESS' AND login_time >= ?", (since,))[0]["n"]
    return {"user": user, "online": max(n, 1)}


@router.get("/sessions")
def sessions(user: dict = Depends(require_user)):
    """접속 현황: 최근 30분 안에 로그인에 성공한 사용자 (사용자별 마지막 로그인 1건)."""
    since = (datetime.now() - timedelta(minutes=30)).strftime(FMT)
    rows = query("""SELECT u.user_name AS name, u.department AS dept, u.role_code AS role, h.login_time AS time, h.ip_address AS ip
                    FROM t_user_login_history h JOIN m_user u ON u.user_id = h.user_id
                    WHERE h.login_result = 'SUCCESS' AND h.login_time >= ?
                      AND h.login_history_id = (SELECT MAX(h2.login_history_id) FROM t_user_login_history h2
                                                WHERE h2.user_id = h.user_id AND h2.login_result = 'SUCCESS' AND h2.login_time >= ?)
                    ORDER BY time DESC""", (since, since))
    return {"count": len(rows), "items": rows}


@router.post("/reset-db")
def reset_db(user: dict = Depends(require_user)):
    """LOT 생성 데이터 초기화 (ADMIN 전용): 실적 테이블(t_*, 로그인 이력 제외)을 비우고 번호를 초기화. 기준정보(m_*)는 유지."""
    if user.get("role") != "ADMIN":
        raise HTTPException(status_code=403, detail="관리자(ADMIN)만 사용할 수 있습니다.")
    from backend.db import BACKEND, DB_PATH
    if BACKEND != "sqlite" or DB_PATH is None:
        # 실 DB 에서는 데이터 초기화를 허용하지 않는다 (운영 데이터 보호)
        raise HTTPException(status_code=403, detail="실 DB 에서는 초기화를 사용할 수 없습니다.")
    import sqlite3
    tables = ["t_alarm_action", "t_alarm_event", "t_vision_image", "t_vision_inspection_detail", "t_vision_inspection",
              "t_sensor_reading", "t_weld_event", "t_loading_event", "t_tip_maintenance", "t_lot"]  # 자식 → 부모 순서
    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        counts = {t: conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in tables}
        for t in tables:
            conn.execute(f"DELETE FROM {t}")
        conn.execute(f"DELETE FROM sqlite_sequence WHERE name IN ({','.join('?' * len(tables))})", tables)
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "deleted": counts}
