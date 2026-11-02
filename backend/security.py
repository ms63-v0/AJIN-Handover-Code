"""비밀번호 해시 + 서명된 세션 쿠키. (표준 라이브러리만 사용)

- 비밀번호: scrypt (형식 'scrypt$salt$hash'). bcrypt/argon2 설치가 허용되면 hash/verify 두 함수만 교체하면 된다.
- 세션: 서버 재시작에도 유지되도록 data/.secret 의 비밀키로 서명한 토큰을 HttpOnly 쿠키에 저장한다.
"""
import base64, hashlib, hmac, json, os, time
from pathlib import Path

from fastapi import Cookie, HTTPException

from backend.config import COOKIE_NAME

SECRET_FILE = Path(__file__).resolve().parent.parent / "data" / ".secret"


def _secret() -> bytes:
    if not SECRET_FILE.exists():
        SECRET_FILE.write_bytes(os.urandom(32))
    return SECRET_FILE.read_bytes()


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    h = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"scrypt${salt.hex()}${h.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, salt, h = stored.split("$")
        if scheme != "scrypt":
            return False
        calc = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=2**14, r=8, p=1, dklen=32)
        return hmac.compare_digest(calc.hex(), h)
    except Exception:
        return False


def make_token(user: dict, ttl_sec: int) -> str:
    body = base64.urlsafe_b64encode(json.dumps({**user, "exp": int(time.time()) + ttl_sec}).encode()).decode()
    return f"{body}.{hmac.new(_secret(), body.encode(), 'sha256').hexdigest()}"


def read_token(token: str | None) -> dict | None:
    try:
        body, sig = (token or "").split(".")
        if not hmac.compare_digest(sig, hmac.new(_secret(), body.encode(), "sha256").hexdigest()):
            return None
        data = json.loads(base64.urlsafe_b64decode(body))
        return data if data["exp"] > time.time() else None
    except Exception:
        return None


def require_user(qms_session: str | None = Cookie(None, alias=COOKIE_NAME)) -> dict:
    """모든 업무 API에 걸리는 로그인 검사. 실패 시 401."""
    user = read_token(qms_session)
    if not user:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다.")
    return user
