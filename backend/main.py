"""API 서버 진입점. 화면별 API는 routers/ 아래에 파일을 추가하고 여기에 등록한다."""
import logging

from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.db import BACKEND, DB_PATH
from backend.routers import admin, alarm, auth, dashboard, export, live, lots, master, vision, weld
from backend.security import require_user

app = FastAPI(title="Quality DB API (local)")
log = logging.getLogger("qms")


@app.middleware("http")
async def catch_errors(request: Request, call_next):
    """처리 중 예외 → 500 JSON. CORS 미들웨어보다 안쪽에 있어야 오류 응답에도 CORS 헤더가 붙는다(아래에서 CORS를 나중에 등록)."""
    try:
        return await call_next(request)
    except Exception:  # noqa: BLE001
        log.exception("처리 중 오류: %s %s", request.method, request.url.path)
        return JSONResponse(status_code=500, content={"detail": "서버 처리 중 오류가 발생했습니다. API 서버 로그를 확인하세요."})


# UI 개발 서버 주소만 허용 (주소가 다르면 여기에 추가). 쿠키 로그인을 쓰므로 credentials 허용 + 주소는 명시해야 한다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173", "http://127.0.0.1:5173",
        "http://localhost:3000", "http://127.0.0.1:3000",
        # 포트 없이 열었을 때 대비 (py -m http.server 80 등)
        "http://localhost",     "http://127.0.0.1",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Cookie"],
    expose_headers=["Content-Disposition"],   # 추출 파일명 전달
)

app.include_router(auth.router)  # 로그인/로그아웃 (인증 불필요)
app.include_router(export.router)  # 데이터 추출 (자체적으로 로그인 확인 + 출력자 기록)
# 아래 업무 API는 모두 로그인 필수
for r in (admin.router, master.router, lots.router, live.router, dashboard.router, weld.router, vision.router, alarm.router):
    app.include_router(r, dependencies=[Depends(require_user)])


@app.get("/health")
def health():
    if DB_PATH is None:   # MSSQL: 파일이 없으므로 백엔드 이름만 알려준다 (접속 정보는 노출하지 않음)
        return {"status": "ok", "backend": BACKEND}
    return {"status": "ok", "backend": BACKEND, "db": DB_PATH.name, "db_exists": DB_PATH.exists()}
