# 설치·실행 가이드

[문서 허브](../README.md) · [설치·실행](setup.md) · [사용자 설명서](user-guide.md) · [개발](development.md) · [운영·장애 대응](operations.md) · [변경·배포](release.md) · [인수인계](handover.md)

신규 PC에서 소스를 받아 설치하고, `.env`를 작성하고, 실행을 확인하는 절차입니다.

> 문서 기준 V1.1 (2026-11-02). 본문의 장 번호(예: `12-3`, `18장`)는 전체 인수인계 문서 기준입니다. 장별 위치는 [문서 허브의 장 번호 안내](../README.md#장-번호-안내)에 있습니다.

## 목차

- 6. 시작 전 준비
- 7. 설치하기 (처음 한 번만)
- 8. `.env` 작성 가이드 (가장 중요)
- 9. 실행하기

---

## 6. 시작 전 준비

### 6-1. 소스 받기

| 방법 | 설명 |
|---|---|
| GitHub에서 내려받기 | **Code → Download ZIP** (읽기 전용 확인용) |
| Git / GitHub Desktop | **Clone** 후 **Pull**로 최신화 (코드 수정·운영 반영 시 이 방법 사용, 19장) |

받은 폴더 안에 `backend`, `frontend`, `requirements.txt`가 바로 보이면 맞습니다. 이 폴더를 이하 **`app 폴더`** 라고 부릅니다.

### 6-2. 실행 환경과 버전

| 항목 | 요구 사항 | 확인 명령 |
|---|---|---|
| 운영체제 | Windows 10 이상 | - |
| Python | 3.10 이상 | `py --version` |
| ODBC 드라이버 | ODBC Driver 18 for SQL Server | `py -c "import pyodbc; print(pyodbc.drivers())"` (7장 설치 후) |
| DB | SQL Server 2016 이상 (검증 2022) | DB 담당 확인 |
| Python 패키지 | fastapi, uvicorn, pyodbc, openpyxl, reportlab, pillow (**버전 미고정**) | `python -m pip freeze` |
| 브라우저 | 최신 Chrome / Edge | - |
| 네트워크 | 사내망·VPN, DB 서버 포트 접근 | 전산팀 확인 |

> [!NOTE]
> 패키지 버전이 고정되어 있지 않습니다. **정상 동작하는 PC의 `pip freeze` 결과를 `requirements.lock.txt`로 저장**해 두면 다른 PC에서 같은 상태로 재설치할 수 있습니다(7장).

### 6-3. 미리 받아 둘 정보

> [!WARNING]
> 아래 값은 **담당자에게 별도 경로로 전달받으며**, 이 문서·메신저·메일에 적지 않습니다(16-3).

| 필요한 것 | 누구에게 받나 | 용도 |
|---|---|---|
| DB 서버 주소·포트 | 전산팀 | `.env`의 `MSSQL_SERVER` |
| DB 접속 계정·비밀번호 | DB 담당 | `.env`의 `MSSQL_USER`, `MSSQL_PASSWORD` (`sa` 아님) |
| 인증서 방식 | 전산팀 | `MSSQL_TRUST_CERT` |
| 앱 로그인 계정 | 시스템 관리자 | 화면 로그인 (DB 계정과 다름) |
| 저장소 접근 권한 | 프로젝트 담당 | 5-1 |

---

## 7. 설치하기 (처음 한 번만)

```powershell
# 1) app 폴더로 이동
cd "<app 폴더의 실제 경로>"

# 2) 가상환경 만들기
py -m venv .venv

# 3) 가상환경 켜기 (앞에 (.venv)가 보이면 성공)
.\.venv\Scripts\Activate.ps1

# 4) 패키지 설치 (lock 파일이 있으면 그것을 우선 사용)
python -m pip install -r requirements.txt
#   python -m pip install -r requirements.lock.txt
```

> [!NOTE]
> **"스크립트 실행이 비활성화되어 있습니다"** 오류가 나면 한 번 실행한 뒤 3)을 다시 하세요.
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```
> 창을 새로 열 때마다 3)을 다시 실행해야 합니다.

> [!NOTE]
> `requirements.txt`의 pyodbc 주석에 "SQLite 모드에서는 불필요"라고 적혀 있지만, **실 DB 운영에는 반드시 필요합니다.** 설치가 끝나면 버전을 기록해 두세요.
> ```powershell
> python -m pip freeze > requirements.lock.txt
> ```

---

## 8. `.env` 작성 가이드 (가장 중요)

`.env`는 **DB 접속 정보를 적는 파일**입니다. `app` 폴더 안, `backend` 폴더와 같은 위치에 둡니다.

> [!CAUTION]
> **`.env.example`을 그대로 복사해서 쓰지 마세요.** 개발 시절 견본이라 `DB_BACKEND=sqlite`, `MSSQL_USER=sa`, 테스트 DB 이름, 값 뒤 주석이 들어 있습니다. 반드시 8-3을 기준으로 작성하세요.

### 8-1. 만드는 방법

```powershell
New-Item -Path .env -ItemType File
notepad .env
```

> [!CAUTION]
> 탐색기에서 만들면 `.env.txt`로 저장되어 프로그램이 읽지 못합니다.

### 8-2. 항목 설명

| 항목 | 의미 | 넣을 값 | 필수 |
|---|---|---|---|
| `DB_BACKEND` | DB 종류 | `mssql` | 필수 |
| `MSSQL_SERVER` | DB 서버 주소와 포트 | `<서버 IP>,<포트>` | 필수 |
| `MSSQL_DATABASE` | 데이터베이스 이름 | `HW_Q_DB` | 필수 |
| `MSSQL_USER` | DB 접속 계정 | DB 담당 발급 계정 | 필수 |
| `MSSQL_PASSWORD` | DB 접속 비밀번호 | DB 담당 발급 비밀번호 | 필수 |
| `MSSQL_DRIVER` | ODBC 드라이버 이름 | `ODBC Driver 18 for SQL Server` | 필수 |
| `MSSQL_TRUST_CERT` | 서버 인증서 검사 생략 | `yes` 또는 `no` (전산팀 안내) | 필수 |
| `MSSQL_CHAR_ENCODING` | 한글이 깨질 때만 | `cp949` | 선택 |

> [!WARNING]
> **`DB_BACKEND` 줄이 빠지면 오류 없이 SQLite(개발용) 모드로 켜집니다.** 실행 후 반드시 9장의 `/health`로 `"backend": "mssql"`을 확인하세요.

### 8-3. 완성 예시

```ini
DB_BACKEND=mssql
MSSQL_SERVER=<서버IP>,<포트>
MSSQL_DATABASE=HW_Q_DB
MSSQL_USER=<DB접속계정>
MSSQL_PASSWORD=<DB접속비밀번호>
MSSQL_DRIVER=ODBC Driver 18 for SQL Server
MSSQL_TRUST_CERT=<전산팀 안내값>
```

### 8-4. 반드시 지킬 규칙

| 규칙 | 틀린 예 | 맞는 예 |
|---|---|---|
| 값 뒤에 설명 금지 (설명까지 값으로 읽힘) | `MSSQL_CHAR_ENCODING=cp949  # 설명` | `MSSQL_CHAR_ENCODING=cp949` |
| 따옴표 금지 | `MSSQL_USER="app_user"` | `MSSQL_USER=app_user` |
| `=` 앞뒤 공백 금지 | `MSSQL_USER = app_user` | `MSSQL_USER=app_user` |
| 빈 값 금지 | `MSSQL_PASSWORD=` | 실제 값 |
| 설명은 줄 맨 앞 `#` | 값 뒤 `# 설명` | 줄 전체 `# 설명` |
| `sa` 사용 금지 | `MSSQL_USER=sa` | 전용 계정 |

### 8-5. 값 확인

```powershell
Get-Content .env | Select-String "DB_BACKEND|MSSQL_SERVER|MSSQL_DATABASE|MSSQL_USER|MSSQL_DRIVER|MSSQL_TRUST_CERT"
```

결과를 메신저나 문서에 붙여 넣지 마세요. `.env` 보안과 교체 절차는 16장에 있습니다.

---

## 9. 실행하기

app 폴더에서 **PowerShell 창 두 개**를 엽니다. 두 창 모두 `(.venv)` 상태여야 합니다.

| 창 | 명령 | 정상 표시 |
|---|---|---|
| 창 1 (백엔드) | `python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000` | `Uvicorn running on http://127.0.0.1:8000` |
| 창 2 (화면) | `python serve_ui.py` | `UI 서버: http://127.0.0.1:5173` |

### 9-1. 실행 확인 (매번 필수)

| 순서 | 확인 | 정상 결과 |
|---|---|---|
| 1 | 브라우저 `http://127.0.0.1:8000/health` | `{"status": "ok", "backend": "mssql"}` |
| 2 | 브라우저 `http://127.0.0.1:5173` | 로그인 화면 |
| 3 | 앱 계정으로 로그인 | 대시보드 표시 |

> [!IMPORTANT]
> `/health`에 `"backend": "sqlite"`가 보이면 **실 DB가 아닌 개발용 모드**입니다. `.env`를 확인하고 백엔드를 다시 실행하세요.

끄기는 각 창에서 `Ctrl + C`입니다.
