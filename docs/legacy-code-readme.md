> [!WARNING]
> **보관용 문서입니다. 운영 기준이 아닙니다.** 개발 단계(SQLite, Codespaces 테스트 환경)의 기록이며, 이미 제거된 도구(시뮬레이터, `init_db.py`, `test.sql` 등)를 언급합니다. 실 DB 운영 절차는 [문서 허브](../README.md)를 따르세요. 문서 제목의 `v1.6`은 개발 당시 문서 표기이며 화면 표기 버전(`v1.1.0`)·인수인계 문서 버전(V1.1)과 다릅니다.

# AJIN QMS v1.6 — 실행 · 테스트 · 실 DB 전환 가이드

용접/비전 품질 관리 시스템입니다. DB 종류는 `.env`의 `DB_BACKEND` 한 줄로 고릅니다.
이 문서는 실행 환경을 **세 가지**로 나눠 설명합니다. 자기 환경의 절만 따라가면 됩니다.

---

## 0. 환경 구분 (먼저 읽기)

| 구분 | [A] SQLite (로컬 개발) | [B] MSSQL 테스트 (Codespaces) | [C] MSSQL 실 DB (전산실) |
|---|---|---|---|
| 용도 | 기능 개발 | 실 DB 전환 연습, 검증 증빙 | 실제 생산 데이터 |
| DB 위치 | 이 PC 파일 `data/factory.db` | Codespace 안 Docker 컨테이너 | 전산실 DB 서버 |
| 백엔드(8000) | 이 PC | **Codespace** | 이 PC 또는 서버 |
| 화면(5173) | 이 PC | 이 PC | 이 PC 또는 서버 |
| DB 접속 주소 | 파일 | `localhost,1433` (Codespace 안) | 전산실이 알려 준 `주소,포트` |
| 포트 전달 | 없음 | **8000만** Codespace → 이 PC | 없음 (사내망 직접 접속) |
| DB/계정 생성 | `init_db.py` | 우리가 sa로 직접 | **DB 담당자** |
| 시뮬레이터 | 가능 | 가능 | **금지** |
| `test.sql` 테스트 데이터 | 해당 없음 | 가능 | **금지** |
| 해당 절 | 2절 | 3절 | 4절 |

- 1절(공통)은 모든 환경에 적용됩니다.
- [B]에서 **1433을 이 PC로 전달해 로컬 백엔드로 접속하는 방식은 쓰지 않습니다.** TCP는 열리지만 SQL 로그인이 시간 초과(258)로 실패하는 것을 확인했습니다(5.2). 그래서 [B]는 DB와 백엔드를 모두 Codespace에서 실행합니다.

---

## 1. 공통

### 1.1 프로젝트 구조

```
app/
  backend/
    __init__.py          시간대(KST) 고정 — import 시 적용
    common.py            공통 상수 (FMT 등)
    config.py            화면·집계 설정값
    db.py                DB 스위치 (.env 를 읽고 DB_BACKEND 로 드라이버 선택)
    db_sqlite.py         SQLite 드라이버
    db_mssql.py          MSSQL 드라이버 (pyodbc)
    sqldialect.py        DB별 SQL 문법 차이 모음
    security.py          비밀번호 해시(scrypt) · 세션 토큰 서명
    routers/             auth · dashboard · weld · vision · alarm · lots · live · master · export · admin
  collector/simulator.py 테스트 데이터 생성기 (실 DB 금지)
  data/
    schema.sql           SQLite 테이블 정의
    seed.sql             기준정보 초기 데이터 (SQLite 전용)
    .secret              세션 서명 키 (자동 생성, 공유 금지)
  frontend/
    js/main.js           앱 진입점, 화면 라우팅 (관리자 화면 가드 포함, 1.7)
    js/config.js         API 주소, 메뉴
    js/components/sidebar.js   메뉴 + POP DB 칸 (1.7)
    js/pages/admin/      기준정보 관리 (index.js, detail.js, recipe.js)
  tools/
    load_sqlite_to_mssql.py   테스트 DB 적재 (DB 이름에 test 있을 때만)
    compare_sqlite_mssql.py   조회 결과 비교 (읽기 전용)
  requirements.txt
  serve_ui.py            화면 서버 (5173)
  init_db.py             SQLite DB 생성 + 데모 계정
  .env.example           .env 견본
mssql_query.sql          MSSQL 생성 스크립트 (v1.1)
test.sql                 화면 연동 확인용 테스트 데이터 (TEST_0426)
test_insert.sql          임의 테스트 값 입력용 (값을 바꿔 여러 번 실행)
start_all.sh, stop_all.sh  구 Codespace(ms_sql_prove) 전용 기동·종료 (3.11)
```

### 1.2 `.env` 키

`app/.env`에 둡니다. 저장소, 채팅, 문서에 올리지 않습니다.

```env
DB_BACKEND=sqlite                 # sqlite | mssql (알 수 없는 값이면 서버가 시작되지 않음)

# DB_BACKEND=mssql 일 때만 사용
MSSQL_SERVER=<주소>,<포트>          # [B] localhost,1433  [C] 전산실 값
MSSQL_DATABASE=<DB이름>            # [B] factory_db_test  [C] test 없는 이름
MSSQL_USER=<DB 접속 계정>           # [B] fa00  [C] 전산실이 발급한 SQL 로그인 (sa 금지, 화면 로그인 ID 아님)
MSSQL_PASSWORD=<비밀번호>
MSSQL_TRUST_CERT=yes              # [B] yes  [C] 정식 인증서면 no
MSSQL_DRIVER=ODBC Driver 18 for SQL Server
# MSSQL_CHAR_ENCODING=cp949       # VARCHAR 한글이 깨질 때만
```

- 값에 따옴표를 쓰지 않습니다.
- 비밀번호에 `;` `{` `}`가 있으면 연결 문자열이 깨질 수 있습니다. 이 문자는 피합니다(6절).
- PowerShell에 같은 이름의 환경변수(`MSSQL_USER` 등)가 있으면 `.env`보다 우선합니다. 이상하면 확인합니다.
  ```powershell
  Get-ChildItem Env: | Where-Object { $_.Name -like "MSSQL_*" } | ForEach-Object { $_.Name }
  ```
- 실제 접속 설정 확인 (비밀번호는 가려서 출력):
  ```powershell
  python -c "import backend.db; import backend.db_mssql as m; s=m._conn_str(); print(s.replace(s.split('PWD=')[1].split(';')[0], '***'))"
  ```
  `backend.db`를 먼저 import해야 `.env`가 읽힙니다.

### 1.3 시각 기준 (KST)

- `backend/__init__.py`가 시간대를 `Asia/Seoul`로 고정합니다. Codespace(UTC)에서도 같습니다.
- MSSQL 등록 시각 기본값: `DATEADD(HOUR, 9, SYSUTCDATETIME())` (서버 시간대와 무관)
- SQLite 등록 시각 기본값: `datetime('now', '+9 hours')`
- 수집기(실 PLC 연동)가 시각을 넣을 때도 **KST**로 넣어야 합니다.

### 1.4 SQL 작성 규칙 (SQLite ↔ MSSQL)

| 하고 싶은 것 | 쓰지 말 것 | 이렇게 |
|---|---|---|
| 첫 1건 | `LIMIT 1` | ORDER BY 후 `FIRST_ROW` |
| N건만 | `LIMIT n` / `LIMIT ?` | `limit_n(n)` / `LIMIT_PARAM` |
| 페이징 | `LIMIT ? OFFSET ?` | `paging(건수, 시작)` |
| 경과 시간(초) | `julianday`, `strftime` | `age_seconds(컬럼)`, `seconds_between(시작, 끝)` |
| 조건 개수 | `SUM(a = 'NG')` | `SUM(CASE WHEN a = 'NG' THEN 1 ELSE 0 END)` |
| 날짜 더하기 | `date(?, '+1 day')` | 파이썬에서 계산 후 `?` 전달 |
| 집계 + 일반 컬럼 | GROUP BY에 없는 컬럼 | 모두 GROUP BY 또는 `MAX()` |
| FROM 서브쿼리 | 별칭 없음 | 반드시 별칭 |
| `IN (?, ...)` | 건수 제한 없음 | `chunks(목록)` 900개씩 |

- INSERT 후 ID가 필요하면 INSERT와 `SCOPE_IDENTITY()`를 **한 배치**로 실행합니다.
- 시스템 뷰의 이름 컬럼을 `+`로 이어 붙이지 않습니다(콜레이션 충돌 Msg 451).

### 1.5 계정 종류 (두 종류를 구분)

| 구분 | 무엇을 위한 계정 | 어디에 만드나 | 쿼리 | 실행 주체 |
|---|---|---|---|---|
| **DB 접속 계정** (예: fa00) | 백엔드가 SQL Server에 접속 | 서버 로그인(`master`) + DB 사용자 | `CREATE LOGIN`, `CREATE USER`, `GRANT` | [B] 우리(sa) / [C] **DB 담당자** |
| **앱 로그인 계정** (예: admin) | 화면 로그인 사용자 | DB 안 `m_user` 테이블 행 | `INSERT INTO m_user` | [B] 우리 / [C] 우리(fa00으로 가능) |

- 이름이 같아도(fa00) 두 계정은 **별개**입니다.
- DB 접속 계정 권한은 **SELECT, INSERT, UPDATE만** 줍니다. DELETE, CREATE, ALTER는 주지 않습니다.
- `.env`의 `MSSQL_USER`에는 DB 접속 계정(fa00)을 넣습니다. **sa를 넣지 않습니다.**

**앱 역할 (`role_code`) 현황 (현재 코드 기준)**

| 역할 | 할 수 있는 것 |
|---|---|
| `ADMIN` | 기준정보 등록·수정, 레시피 등록, LOT 데이터 초기화(SQLite만), 알람 확인 |
| `MANAGER` | 알람 확인 |
| `OPERATOR` | 알람 확인 |
| `VIEWER` | **아직 없음** (코드 수정 필요, 6절) |

- 로그인한 사용자는 모든 조회 화면과 추출을 쓸 수 있습니다.
- 알람 조치 등록은 역할 검사가 없습니다(6절).
- 기준정보 관리 메뉴와 화면은 ADMIN만 보입니다(1.7). API도 ADMIN만 허용합니다(403).

### 1.6 앱 로그인 비밀번호 해시 만들기

`m_user.password_hash`에는 평문이 아니라 scrypt 해시를 넣습니다. 해시는 **DB에 접속하지 않고** 코드가 있는 곳에서 만듭니다.

**이 PC (PowerShell, `app` 폴더)**
```powershell
cd "C:\Users\UsersPC\Desktop\qms_mssql_\app"
$sec   = Read-Host "비밀번호 (8자 이상)" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
py -c "import sys; from backend.security import hash_password; print(hash_password(sys.argv[1]))" $plain
Remove-Variable plain, sec
```

**Codespace (bash, `app` 폴더, 패키지 설치 후)**
```bash
read -rsp "비밀번호 (8자 이상): " PW; echo
python3 -c "import sys; from backend.security import hash_password; print(hash_password(sys.argv[1]))" "$PW"
unset PW
```

- 입력할 때 글자가 보이지 않는 것이 정상입니다.
- 출력된 `scrypt$...` 한 줄을 그대로 복사합니다. 앞뒤 공백이나 줄바꿈이 섞이면 로그인이 실패합니다.
- PowerShell 창은 VS Code 터미널(`` Ctrl+` ``), 탐색기에서 Shift+우클릭 → PowerShell 창에서 열기, 시작 메뉴 중 편한 것을 씁니다.

**앱 로그인 계정 넣기 (fa00 또는 sa로 접속, 대상 DB)**
```sql
USE <DB 이름>;
GO
IF NOT EXISTS (SELECT 1 FROM m_user WHERE login_id = N'<로그인 ID>')
    INSERT INTO m_user (login_id, password_hash, user_name, role_code, department, force_change_yn, use_yn)
    VALUES (N'<로그인 ID>', N'<해시>', N'<이름>', 'ADMIN', N'<부서>', 'Y', 'Y');   -- 운영자는 'OPERATOR'
GO
SELECT login_id, role_code, use_yn FROM m_user ORDER BY user_id;
```

**관리 쿼리**
```sql
-- 비밀번호 변경 (새 해시는 위 방법으로 생성)
UPDATE m_user SET password_hash = N'<새 해시>', password_changed_at = DATEADD(HOUR, 9, SYSUTCDATETIME()),
       updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME()) WHERE login_id = N'<ID>';
-- 잠금 해제 (5회 실패 시 10분 잠금)
UPDATE m_user SET failed_login_count = 0, locked_until = NULL WHERE login_id = N'<ID>';
-- 퇴직자: 삭제하지 않고 사용 중지
UPDATE m_user SET use_yn = 'N', updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME()) WHERE login_id = N'<ID>';
```

**로그인 실패 원인 (`t_user_login_history.login_result`)**

| 값 | 의미 |
|---|---|
| `FAIL_NO_USER` | 아이디가 없거나 `use_yn = 'N'` |
| `FAIL_PW` | 비밀번호 또는 해시가 맞지 않음 |
| `FAIL_LOCKED` | 5회 실패로 잠김 (10분) |

### 1.7 화면 코드 메모 (v1.6 반영)

**(1) POP DB 칸 — `frontend/js/components/sidebar.js`**

왼쪽 메뉴 아래 POP DB 칸은 `m_line`에서 **`line_code = 'TEST_0426'` 행 하나만** 읽어 `line_name`을 보여 줍니다. 화면을 열 때 한 번 읽으므로 값을 바꾸면 F5로 새로고침합니다.
```javascript
  const showDb = async () => {
    const el = root.querySelector(".dbtest__pending");
    try {
      const rows = await api.lines();
      const row = rows.find((r) => r.line_code === "TEST_0426");
      el.textContent = row ? `DB 값: ${row.line_name}` : "DB 연결됨 (테스트 행 없음)";
    } catch {
      el.textContent = "DB 연결 실패";
    }
  };
  showDb();
```

| 화면 문구 | 의미 |
|---|---|
| `DB 값: …` | 연동 성공 |
| `DB 연결됨 (테스트 행 없음)` | 연결은 됐으나 `TEST_0426` 행이 없음 |
| `DB 연결 실패` | 백엔드 꺼짐, 로그인 필요, DB 오류 중 하나 (백엔드 로그 확인) |

- 다른 코드(`TEST_0427` 등)로 넣은 값은 POP DB 칸에 나오지 않습니다. 값을 바꿔 보려면 `TEST_0426`의 이름을 수정합니다(3.6).

**(2) 관리자 화면 가드 — `frontend/js/main.js`의 `route()`**

메뉴를 숨겨도 주소창에 `#/admin`을 입력하면 화면이 열리던 문제를 막았습니다. ADMIN이 아니면 대시보드로 보냅니다.
```javascript
  let id = location.hash.replace("#/", "").split("?")[0]; // ?id=N 같은 파라미터는 화면 모듈이 직접 읽는다
  // 관리자 전용 화면: ADMIN이 아니면 기본 화면으로 보낸다 (메뉴 숨김과 같은 기준)
  if (id === "admin" && session.user?.role !== "ADMIN") id = DEFAULT_PAGE;
  const page = PAGES[id] ?? PAGES[DEFAULT_PAGE];
```

**(3) 계정 전환 시 메뉴가 안 바뀌는 현상**

사이드바는 처음 로그인할 때 한 번만 그려집니다. 같은 브라우저에서 OPERATOR로 쓰다가 ADMIN으로 바꾸면 "기준정보 관리" 메뉴가 안 보일 수 있습니다.
- 대처: **로그아웃 후 다시 로그인**하거나 Ctrl+F5로 새로고침합니다.
- 근본 수정(로그인 사용자가 바뀌면 사이드바 다시 그리기)은 6절 개선 항목입니다.

**(4) 화면 코드 수정 위치**

화면(frontend)은 **화면 서버를 띄운 곳의 파일**을 고쳐야 반영됩니다. [B]에서는 화면이 이 PC에서 돌므로 이 PC의 `qms_mssql_\app\frontend`를 고칩니다. 백엔드(backend)는 Codespace의 파일을 고칩니다. 두 곳의 소스는 같은 내용으로 맞춰 둡니다.

---

## 2. [A] SQLite — 로컬 개발

### 2.1 최초 1회

```powershell
cd "C:\Users\UsersPC\Desktop\qms_mssql_\app"
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python init_db.py            # data/factory.db 생성 + 데모 계정(admin, operator1)
```
- `Activate.ps1`이 실행 정책으로 막히면 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`를 한 번 실행합니다.
- `factory.db`를 VS Code에서 열어 둔 탭은 먼저 닫습니다.
- `.env`는 `DB_BACKEND=sqlite` 한 줄이면 됩니다(없어도 기본값 sqlite).

### 2.2 실행 (터미널 3개, 모두 `app` 폴더, venv 켠 상태)

| 터미널 | 명령 | 역할 |
|---|---|---|
| A | `python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000 --reload` | API 서버 |
| B | `python serve_ui.py` | 화면 → http://127.0.0.1:5173 |
| C | `python collector\simulator.py` | 실시간 데이터 생성 (Ctrl+C 종료) |

- 새 터미널마다 `.\.venv\Scripts\Activate.ps1`로 venv를 켭니다. 줄 앞에 `(.venv)`가 보여야 합니다.
- `--backfill` 옵션은 쓰지 않습니다. 하루치를 한꺼번에 채워 데이터 정합성이 깨집니다.
- 확인: `curl.exe http://127.0.0.1:8000/health` → `{"status":"ok","backend":"sqlite",...}`
- 데모 계정 비밀번호는 `init_db.py` 상단에 있습니다. 운영에서는 쓰지 않습니다.

---

## 3. [B] MSSQL 테스트 — Codespaces

### 3.1 구조

```
[Codespace]  MSSQL 컨테이너(1433) ← 백엔드(8000, --host 0.0.0.0)
                                         │ VS Code 포트 전달 (8000만)
[이 PC]                           화면(5173) → http://127.0.0.1:8000
```

- DB와 백엔드가 같은 Codespace 안에 있으므로 백엔드는 `localhost,1433`으로 바로 접속합니다.
- 이 PC는 **8000만 전달**받습니다. 1433은 전달하지 않습니다(5.2).
- 화면의 API 주소는 `config.js`가 `http://127.0.0.1:8000`으로 정하므로 코드 수정이 필요 없습니다.
- 아래 경로는 저장소 `final_mssql` 기준입니다. 저장소 이름이 다르면 `/workspaces/<저장소>`로 바꿉니다.

### 3.2 최초 1회 설정

**① Codespace 만들기**
GitHub 저장소 → **Code → Codespaces → Create codespace on main**. 터미널에서 Docker 확인:
```bash
docker version --format '{{.Server.Version}}'
```

**② SQL Server 컨테이너 설치 (sa 비밀번호 입력)**
```bash
read -rsp "sa 비밀번호 (12자 이상, 대·소문자·숫자·기호 중 3종 이상): " SA_PW; echo
docker run -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$SA_PW" -p 1433:1433 \
  -v ajin_mssql_data:/var/opt/mssql --name ajin-mssql -d mcr.microsoft.com/mssql/server:2022-latest
sleep 60
docker logs ajin-mssql 2>&1 | grep -i "ready for client" | tail -1
```
- 마지막에 `SQL Server is now ready for client connections`가 나오면 준비 완료입니다.
- `-v ajin_mssql_data`(데이터 보존 볼륨)를 빼지 않습니다.

**③ VS Code SQL Server 확장 설치와 연결 (Codespace 창에서)**
1. `Ctrl+Shift+X` → `SQL Server (mssql)` (게시자 Microsoft) → Install
2. 왼쪽 SQL Server 아이콘 → **Add Connection**
   - Server `localhost,1433` / Authentication **SQL Login** / User `sa` / Trust server certificate **체크**
- 확장은 DB에 접속해 쿼리를 실행하는 도구입니다. 서버는 ②의 컨테이너입니다.

**④ DB 만들기 (sa, New Query)**
```sql
IF DB_ID(N'factory_db_test') IS NULL
    CREATE DATABASE factory_db_test COLLATE Korean_Wansung_CI_AS;
GO
SELECT name, DATABASEPROPERTYEX(name, 'Collation') AS collation
FROM sys.databases WHERE name = N'factory_db_test';
```
- `collation = Korean_Wansung_CI_AS`여야 합니다. 다르면 한글이 `?`로 저장됩니다.

**⑤ 테이블 만들기 (`mssql_query.sql`, sa)**
1. `mssql_query.sql`을 Codespace 탐색기로 끌어다 올리고 엽니다.
2. 대상 DB를 **`factory_db_test`**로 선택합니다(`master` 아님).
3. 전체 실행(F5) → 마지막 메시지 `AJIN QMS 스키마 생성 완료`

터미널로 실행하려면:
```bash
sed '1s/^\xEF\xBB\xBF//' /workspaces/final_mssql/mssql_query.sql > /tmp/create.sql
docker cp /tmp/create.sql ajin-mssql:/tmp/create.sql
docker exec ajin-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PW" -C -d factory_db_test -i /tmp/create.sql | tail -1
```

검증 (기대값 `23 / 36 / 7`)
```sql
USE factory_db_test;
SELECT (SELECT COUNT(*) FROM sys.tables)       AS tables,
       (SELECT COUNT(*) FROM sys.foreign_keys) AS fks,
       (SELECT COUNT(*) FROM sys.indexes WHERE name LIKE 't_%_index_%') AS idx;
```

**⑥ DB 접속 계정 fa00 (sa)**
```sql
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'fa00')
    CREATE LOGIN [fa00] WITH PASSWORD = N'여기에 비밀번호', CHECK_POLICY = ON;
GO
USE factory_db_test;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'fa00')
    CREATE USER [fa00] FOR LOGIN [fa00];
GRANT SELECT, INSERT, UPDATE ON SCHEMA::dbo TO [fa00];
GO
SELECT dp.name, p.permission_name
FROM sys.database_permissions p
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE dp.name = N'fa00';
```
- `N'`와 `'` 사이에 비밀번호만 넣습니다. 따옴표를 지우면 `Incorrect syntax`(Msg 102)가 납니다.
- 비밀번호는 대·소문자·숫자·기호 중 3종 이상이어야 합니다(아니면 Msg 33064). 작은따옴표(`'`)는 쓰지 않습니다.
- 권한 결과에 SELECT, INSERT, UPDATE만 나와야 합니다.
- 실행 후 쿼리 창에 남은 비밀번호는 지웁니다.

**⑦ 앱 코드 올리기**
이 PC의 `qms_mssql_\app` 폴더를 Codespace 탐색기의 `/workspaces/final_mssql`로 끌어다 놓습니다.
- `.venv`(Windows용), `.env`, `data/factory.db`, `data/.secret`, `__pycache__`는 **빼고** 올립니다.
```bash
ls /workspaces/final_mssql/app      # backend, frontend, requirements.txt, serve_ui.py 확인
```

**⑧ 패키지 설치**
```bash
cd /workspaces/final_mssql/app
python3 -m pip install -r requirements.txt
```
- Codespace에서는 `py`가 없습니다. `python3`를 씁니다.

**⑨ ODBC Driver 18 설치 (Linux)**
```bash
python3 -c "import pyodbc; print(pyodbc.drivers())"     # [] 이면 아래 설치
curl -sSL -o /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
python3 -c "import pyodbc; print(pyodbc.drivers())"     # ['ODBC Driver 18 for SQL Server']
```

**⑩ `.env` 만들기 (Codespace, `app` 폴더)**
```bash
cd /workspaces/final_mssql/app
read -rsp "fa00 비밀번호: " FA00_PW; echo
cat > .env <<EOF
DB_BACKEND=mssql
MSSQL_SERVER=localhost,1433
MSSQL_DATABASE=factory_db_test
MSSQL_USER=fa00
MSSQL_PASSWORD=${FA00_PW}
MSSQL_TRUST_CERT=yes
MSSQL_DRIVER=ODBC Driver 18 for SQL Server
EOF
unset FA00_PW
chmod 600 .env
python3 -c "import backend.db; from backend.db import query; print(query('SELECT COUNT(*) AS n FROM m_line'))"
```
- 마지막 줄 결과가 `[{'n': 0}]`이면 백엔드가 DB에 연결된 것입니다.

**⑪ 앱 관리자 계정 admin**
1.6의 Codespace 방법으로 해시를 만든 뒤, SQL 확장에서 1.6의 INSERT 쿼리(`role_code = 'ADMIN'`)를 실행합니다.

**⑫ (선택) 시뮬레이터용 기준정보**
빈 DB에는 라인·설비·제품·파라미터·레시피·용접부위가 없어 시뮬레이터가 멈춥니다. 데모 기준정보를 넣으려면:
```bash
cd /workspaces/final_mssql/app
python3 init_db.py
python3 tools/load_sqlite_to_mssql.py
```
- **`--reset`을 쓰지 않습니다.** fa00에는 DELETE 권한이 없어 실패합니다.
- 데모 데이터에는 `admin`, `operator1` 계정이 포함됩니다. ⑪에서 이미 `admin`을 만들었다면 중복으로 적재가 실패할 수 있으니, **기준정보 적재를 쓸 경우 ⑪보다 먼저** 실행합니다.
- 적재 도구는 DB 이름에 `test`가 없으면 실행을 거부합니다(정상).

### 3.3 매일 기동

**Codespace 터미널 A — DB 확인과 백엔드**
```bash
docker start ajin-mssql 2>/dev/null; docker ps --filter name=ajin-mssql --format '{{.Names}} {{.Status}}'
cd /workspaces/final_mssql/app
python3 -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```
- `Application startup complete`가 나오면 정상입니다. 이 터미널은 켜 둡니다.
- `--host 0.0.0.0`이어야 포트 전달이 됩니다.

**Codespace VS Code — 포트 8000 전달**
- 이 PC의 VS Code에서 `Ctrl+Shift+P` → **Codespaces: Connect to Codespace** → 해당 Codespace
- **PORTS** 탭 → **Add Port** → `8000` → Visibility `Private`
- 이 창은 닫지 않습니다. 닫으면 전달이 끊깁니다.

**이 PC PowerShell — 전달 확인**
```powershell
curl.exe http://127.0.0.1:8000/health
```
- `{"status":"ok","backend":"mssql"}`이면 정상입니다. `/`는 404가 정상입니다(API만 있음).

### 3.4 화면 실행 (이 PC)

```powershell
cd "C:\Users\UsersPC\Desktop\qms_mssql_\app"
.\.venv\Scripts\Activate.ps1
python serve_ui.py
```
- 브라우저 `http://127.0.0.1:5173` → Ctrl+F5 → `admin` 로그인
- 이 PC에서는 백엔드를 띄우지 않습니다. 8000은 Codespace 백엔드가 전달된 것입니다.
- 이 PC에 예전 백엔드나 `gh` 전달이 남아 8000/1433을 잡고 있으면 충돌합니다.
  ```powershell
  Get-NetTCPConnection -LocalPort 8000,1433 -State Listen -ErrorAction SilentlyContinue | Select-Object LocalPort, OwningProcess
  ```
  Codespace 전달 외의 프로세스가 나오면 그 창을 닫거나 `Stop-Process -Id <번호>`로 끕니다.

### 3.5 연동 확인 — `test.sql`

SQL 확장(Codespace)에서 `factory_db_test`를 대상으로 실행합니다(fa00 또는 sa).
```sql
/* test.sql : 화면 연동 확인용 (m_line 에 TEST_0426 / 123). 실 DB 실행 금지 */
USE factory_db_test;
GO
IF EXISTS (SELECT 1 FROM m_line WHERE line_code = N'TEST_0426')
    UPDATE m_line SET line_name = N'123', use_yn = 'Y',
           updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME())
     WHERE line_code = N'TEST_0426';
ELSE
    INSERT INTO m_line (line_code, line_name, use_yn) VALUES (N'TEST_0426', N'123', 'Y');
GO
SELECT line_id, line_code, line_name, use_yn, created_at, updated_at
FROM m_line WHERE line_code = N'TEST_0426';
GO
```
- 화면에서 F5 → 왼쪽 아래 POP DB 칸이 `DB 값: 123`이면 **연동 성공**입니다.

### 3.6 임의 값 넣기 — `test_insert.sql`

맨 위 두 변수만 바꿔 여러 번 실행합니다.
```sql
/* test_insert.sql : 임의 테스트 값 입력 (m_line). 실 DB 실행 금지 */
USE factory_db_test;
GO
DECLARE @line_code VARCHAR(20)   = 'TEST_0426';     -- POP DB 칸에 보려면 TEST_0426 유지
DECLARE @line_name NVARCHAR(100) = N'테스트 라인';    -- 바꿀 값

IF EXISTS (SELECT 1 FROM m_line WHERE line_code = @line_code)
    UPDATE m_line SET line_name = @line_name, use_yn = 'Y',
           updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME())
     WHERE line_code = @line_code;
ELSE
    INSERT INTO m_line (line_code, line_name, use_yn) VALUES (@line_code, @line_name, 'Y');
GO
SELECT line_id, line_code, line_name, use_yn, created_at, updated_at
FROM m_line ORDER BY line_id DESC;
GO
```
- 같은 코드로 다시 실행하면 새 행이 아니라 **이름만 수정**됩니다.
- POP DB 칸은 `TEST_0426`만 읽습니다(1.7). 다른 코드로 넣은 값은 기준정보 관리 → 라인 목록에서 확인합니다.
- fa00에는 DELETE 권한이 없어 테스트 행을 지울 수 없습니다. 지우려면 sa로 실행합니다(테스트 DB만).

### 3.7 시뮬레이터 (Codespace 터미널 B)

```bash
cd /workspaces/final_mssql/app
python3 collector/simulator.py          # Ctrl+C 로 종료
```
- 기준정보(3.2 ⑫)가 없으면 "기준정보가 부족합니다"로 멈춥니다.
- 유효한 레시피가 없으면 "유효한 레시피(m_recipe)가 없습니다"로 멈춥니다.
- `py`, 파일 직접 실행(`./simulator.py`)은 Codespace에서 동작하지 않습니다.

### 3.8 종료

1. Codespace 터미널의 백엔드·시뮬레이터: `Ctrl+C`
2. 이 PC의 화면 서버: `Ctrl+C`
3. PORTS 탭에서 8000 행 삭제
4. (선택) 컨테이너 정지: `docker stop ajin-mssql` — 데이터는 볼륨에 남습니다.

### 3.9 데이터 보존과 백업

- 데이터는 볼륨 `ajin_mssql_data`에 있습니다. 확인: `docker inspect ajin-mssql --format '{{json .Mounts}}'`
- **Codespace를 삭제하면 볼륨도 사라집니다.**

금지 명령 (데이터가 사라짐)

| 명령 | 이유 |
|---|---|
| `docker volume rm ajin_mssql_data` | 볼륨 = 데이터 전체 |
| `docker system prune --volumes` | 볼륨 삭제 |
| 볼륨 없이 `docker run` | 데이터가 컨테이너에만 남음 |

백업과 복원 (sa)
```bash
read -rsp "sa 비밀번호: " SA_PW; echo
docker exec ajin-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PW" -C \
  -Q "BACKUP DATABASE factory_db_test TO DISK = N'/var/opt/mssql/data/factory_db_test.bak' WITH INIT"
# 복원:
# docker exec ajin-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PW" -C \
#   -Q "RESTORE DATABASE factory_db_test FROM DISK = N'/var/opt/mssql/data/factory_db_test.bak' WITH REPLACE"
unset SA_PW
```

컨테이너가 깨졌을 때 (볼륨이 있을 때만)
```bash
docker volume ls | grep ajin_mssql_data && echo "볼륨 있음" || echo "볼륨 없음 - 중단"
docker rm -f ajin-mssql
read -rsp "sa 비밀번호: " SA_PW; echo
docker run -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$SA_PW" -p 1433:1433 \
  -v ajin_mssql_data:/var/opt/mssql --name ajin-mssql -d mcr.microsoft.com/mssql/server:2022-latest
unset SA_PW
```

### 3.10 검증과 비교 (보고 증빙)

**DDL 기대 수치 (v1.1)**: 테이블 23 · 컬럼 200 · PK 23 · FK 36 · UQ 14 · DEFAULT 41 · CHECK 2 · INDEX 7 · `updated_at` 12 · KST 기본값 22

**스냅샷 비교 (SQLite ↔ MSSQL)** — 비교 전용 DB `factory_db_cmp_test`에서, 시뮬레이터를 멈춘 상태로 진행합니다.
```bash
cd /workspaces/final_mssql/app
MSSQL_DATABASE=factory_db_cmp_test python3 tools/load_sqlite_to_mssql.py
MSSQL_DATABASE=factory_db_cmp_test python3 tools/compare_sqlite_mssql.py
```
- 비교 DB는 3.2 ④⑤⑥과 같은 방법으로 만들고 fa00 사용자를 추가합니다.
- 기대 결과: 일치 146 / 내용 다름 0 / MSSQL 오류 0 / 누락 0

| 증빙 | 캡처 대상 |
|---|---|
| DDL | 검증 쿼리 수치 |
| 연동 | POP DB `DB 값: 123` 화면 |
| 조회 일치 | 비교 요약 |
| 기능 제한 | reset-db 403, OPERATOR의 `#/admin` 접근 시 대시보드 이동 |

### 3.11 구 Codespace(`ms_sql_prove`) 스크립트

`start_all.sh`(`up`), `stop_all.sh`(`down`)는 구 Codespace 경로(`/workspaces/ms_sql_prove`)와 컨테이너 안 백엔드·시뮬레이터 기동을 전제로 만든 스크립트입니다. 새 Codespace에서는 3.3 절차를 씁니다. 스크립트를 쓰려면 경로를 새 저장소에 맞게 고쳐야 합니다. **실 DB에서는 사용하지 않습니다.**

---

## 4. [C] MSSQL 실 DB — 전산실

### 4.1 [B]와 달라지는 점

| 항목 | [B] 테스트 | [C] 실 DB |
|---|---|---|
| DB 접속 | Codespace 안 `localhost,1433` | 전산실 `서버주소,포트` 직접 접속 |
| 포트 전달 | 8000 | 없음 |
| DB·스키마 생성 | 우리(sa) | **DB 담당자** |
| DB 접속 계정 (`.env`에 넣는 SQL 로그인) | 우리가 만든 fa00 | **전산실이 발급** |
| 앱 로그인 계정 (화면 로그인, `m_user`) | 우리가 만든 admin | 우리가 만듦 (DB 접속 계정으로 INSERT) |
| 인증서 | 자체 서명 (`TRUST_CERT=yes`) | 정식 인증서 목표 (`no`) |
| 테스트 데이터·시뮬레이터 | 사용 | **금지** |

### 4.2 전산실에 받을 것 / 확인할 것

1. 서버 주소, 포트, DB 이름 (DB 이름에 `test`가 없어야 함)
2. 이 PC(또는 백엔드 서버)에서 그 포트로 접속 가능한지 (방화벽, VPN)
3. 서버 인증 모드: 혼합 모드(SQL 로그인 가능)인지, Windows 인증만인지
   - 확인 쿼리: `SELECT SERVERPROPERTY('IsIntegratedSecurityOnly')` → `0` 혼합 모드, `1` Windows 인증만
   - Windows 인증은 현재 코드가 지원하지 않습니다(`Trusted_Connection=yes` 코드 수정 필요, 6절).
4. **DB 접속 계정**(앱 전용 SQL 로그인) ID와 비밀번호 — `.env`에 넣을 값 (채팅 말고 안전한 경로로)
   - 권한은 대상 DB에 SELECT, INSERT, UPDATE만
   - 화면 로그인 계정(admin 등)과는 별개입니다. 화면 로그인 계정은 우리가 4.4 ⑤에서 만듭니다.
5. 인증서가 정식인지 (`MSSQL_TRUST_CERT` 값 결정)
6. DB collation (`Korean_Wansung_CI_AS`인지)
7. 백업 정책

### 4.3 DB 담당자가 실행할 것 (sa)

#### ㅇ DB 생성
```sql
-- ① DB 생성 (정렬 규칙 필수)
IF DB_ID(N'<실 DB 이름>') IS NULL
    CREATE DATABASE [<실 DB 이름>] COLLATE Korean_Wansung_CI_AS;
GO
SELECT DATABASEPROPERTYEX(N'<실 DB 이름>', 'Collation') AS collation;
GO
```
#### ② 백업 확인 후 `mssql_query.sql`을 실 DB 대상으로 실행 → `AJIN QMS 스키마 생성 완료`, 검증 수치 `23 / 36 / 7`
```sql
-- ③ DB 접속 계정 = 앱 전용 SQL 로그인 (SELECT, INSERT, UPDATE만). 이 ID/비밀번호가 .env에 들어감
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'<DB 접속 계정>')
    CREATE LOGIN [<DB 접속 계정>] WITH PASSWORD = N'<비밀번호>', CHECK_POLICY = ON;
GO
USE [<실 DB 이름>];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'<DB 접속 계정>')
    CREATE USER [<DB 접속 계정>] FOR LOGIN [<DB 접속 계정>];
GRANT SELECT, INSERT, UPDATE ON SCHEMA::dbo TO [<DB 접속 계정>];
GO
```
- 테이블이 이미 있는 DB라면 4.6을 따릅니다.

### 4.4 우리가 할 것

**① 네트워크 확인 (PowerShell)**
```powershell
Test-NetConnection <서버주소> -Port <포트>
```
- `TcpTestSucceeded : True`가 아니면 전산실에 방화벽·VPN 확인을 요청합니다.

**② `.env` (이 PC 또는 백엔드 서버의 `app` 폴더)**
```env
DB_BACKEND=mssql
MSSQL_SERVER=<서버주소>,<포트>
MSSQL_DATABASE=<실 DB 이름>
MSSQL_USER=<DB 접속 계정>
MSSQL_PASSWORD=<DB 접속 계정 비밀번호>
MSSQL_TRUST_CERT=no
MSSQL_DRIVER=ODBC Driver 18 for SQL Server
```
- `MSSQL_USER`, `MSSQL_PASSWORD`에는 전산실이 발급한 **DB 접속 계정**을 넣습니다. 화면 로그인 ID(admin 등)는 넣지 않습니다.
- 인증서 오류가 나면 `yes`로 바꾸지 말고 먼저 전산실과 상의합니다.

**③ 연결 확인 (venv 켠 상태)**
```powershell
python -c "import pyodbc; print(pyodbc.drivers())"
python -c "import backend.db; from backend.db import query; print(query('SELECT COUNT(*) AS n FROM m_line'))"
```

**④ 백엔드·화면 기동 (시뮬레이터 없음)**
```powershell
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
python serve_ui.py
```
- `--reload`는 쓰지 않습니다.
- `health`는 백엔드가 떠 있는지만 보여 줍니다. DB는 ③으로 확인합니다.

**⑤ 앱 로그인 계정 (화면 로그인용)** — 1.6 절차로 관리자(ADMIN), 운영자(OPERATOR)를 `m_user`에 만듭니다. INSERT는 DB 접속 계정으로 실행합니다(sa 불필요). 비밀번호는 현장 담당자가 정하며, DB 접속 계정 비밀번호와 다르게 둡니다.

**⑥ 기준정보** — 현장 값을 화면(기준정보 관리)으로 등록합니다. 화면에 없는 제품·용접기 상세·설비 정격은 담당자와 SQL로 등록합니다(6절). 용접부위 등록은 6절의 ID 문제를 고친 뒤 진행합니다.

**⑦ 쓰기 확인** — 담당자 입회 하에 1건씩 확인합니다(알람 조치, 로그인 이력, 기준정보 등록).

### 4.5 실 DB 금지 사항

| 항목 | 이유 |
|---|---|
| 시뮬레이터 | 가짜 데이터가 섞임 (DB 이름에 test가 없으면 자동 거부) |
| `test.sql`, `test_insert.sql`, `TEST_0426` | 테스트 데이터 |
| `load_sqlite_to_mssql.py`, `compare_sqlite_mssql.py` | 데모 데이터·계정 복사 |
| `init_db.py` 데모 계정(admin, operator1) | 알려진 비밀번호 |
| sa를 `.env`에 사용 | 권한 제한이 무의미해짐 |
| `start_all.sh`, `stop_all.sh`, Docker 명령 | 테스트 전용 |
| `BACKUP`/`RESTORE` 수동 실행 | DB 담당자 정책 |

### 4.6 테이블이 이미 있는 DB에 적용할 때

1. `created_at` 기본값을 KST로 교체 (22개 테이블). 스크립트는 `db/fix_created_default.sql`로 보관합니다.
2. 기본값 변경 전 쌓인 행이 UTC라면 9시간을 더합니다(`db/fix_created.sql`). `ROLLBACK`으로 건수를 먼저 확인하고, **한 번만** 실행합니다.
3. `mssql_query.sql`을 실행하면 `updated_at`이 없는 테이블에만 칼럼이 추가됩니다.
4. 반드시 DB 담당자와 백업 후 진행합니다.

### 4.7 운영 전 체크리스트

**보안**
- [ ] 데모·테스트 계정 없음, 관리자 계정 비밀번호는 현장 담당자가 설정
- [ ] `.env`, `data/.secret`이 공유·저장소에 없음
- [ ] 문서·스크립트·채팅에 비밀번호가 남아 있지 않음 (노출된 비밀번호는 교체)
- [ ] `MSSQL_TRUST_CERT=no` (정식 인증서)
- [ ] HTTPS 적용 후 세션 쿠키 Secure 플래그 (`backend/security.py`)
- [ ] `allow_origins`를 운영 주소로 변경 (`backend/main.py`)
- [ ] OPERATOR로 `#/admin` 접근 시 대시보드로 이동 확인
- [ ] reset-db가 MSSQL 모드에서 403

**DB**
- [ ] collation `Korean_Wansung_CI_AS`
- [ ] DB 접속 계정 권한 SELECT, INSERT, UPDATE만
- [ ] 스키마 수치 `23 / 36 / 7`
- [ ] 기준정보 현장 확인, 쓰기 1건씩 확인

**실행**
- [ ] 시뮬레이터 미실행, 실 수집기 방식 확정 (알람 생성 포함, 6절)
- [ ] 백엔드 배치 위치(PC/서버)와 로그 정책 확정

---

## 5. 문제 해결

### 5.1 공통

| 증상 | 원인 | 조치 |
|---|---|---|
| `Python was not found` / `py` 없음 | venv 꺼짐 또는 Linux | Windows: `.\.venv\Scripts\Activate.ps1`. Codespace: `python3` |
| `No module named uvicorn` | venv에 패키지 없음 | venv 켜고 `python -m pip install -r requirements.txt` |
| `Activate.ps1` 실행 거부 | 실행 정책 | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `.env 에 다음 값이 필요합니다` | `backend.db_mssql`만 import | 확인 명령에서 `import backend.db`를 먼저 |
| 연결 문자열에 `UID=sa` | `.env` 또는 PowerShell 환경변수 | `.env`를 fa00으로, `Env:MSSQL_*` 삭제 (1.2) |
| `GET / 404` | API 루트에 페이지 없음 | 정상. `/health`로 확인 |
| `ERR_CONNECTION_REFUSED :8000` | 백엔드 꺼짐 또는 전달 끊김 | 백엔드 재기동, PORTS 8000 확인 |
| `/api/auth/me 401` (로그인 전) | 로그인 안 됨 | 정상 |
| 로그인 `500` | DB 연결 실패 | 백엔드 로그의 `pyodbc` 오류 확인 |
| `Login failed for user` | 계정·비밀번호 불일치 | `.env`와 DB 로그인 비밀번호 확인 |
| `Cannot open database ... (4060)` | DB 이름 틀림·없음 | `MSSQL_DATABASE` 확인 |
| `Invalid object name 'm_line'` | 스키마 미실행 또는 다른 DB | 대상 DB 확인 후 `mssql_query.sql` |
| 한글이 `?` | collation 불일치 | DB collation 확인, `MSSQL_CHAR_ENCODING=cp949` |
| 관리자인데 기준정보 메뉴 없음 | 다른 계정으로 그려진 사이드바 | 로그아웃 후 로그인, Ctrl+F5 (1.7) |
| POP DB 값이 안 바뀜 | `TEST_0426`이 아닌 코드로 입력, 새로고침 안 함 | 3.6, F5 |

### 5.2 [B] Codespaces

| 증상 | 원인 | 조치 |
|---|---|---|
| 이 PC 백엔드 → `localhost,1433` 시간 초과(258), `Test-NetConnection`은 True | 1433 포트 전달(VS Code·`gh` 모두)이 SQL 로그인 트래픽을 중계하지 못함 | **이 구조를 쓰지 않음.** 백엔드를 Codespace에서 실행 (3.1) |
| PORTS 1433 행에 웹 주소(`devtunnels`)만 있음 | 웹 전달은 SQL 클라이언트가 쓸 수 없음 | 위와 같음 |
| `pyodbc.drivers()`가 `[]` | Linux ODBC 드라이버 없음 | 3.2 ⑨ |
| `CREATE LOGIN` Msg 33064 | 비밀번호 정책 미충족 | 대·소문자·숫자·기호 중 3종 이상 |
| `CREATE LOGIN` Msg 102 | 비밀번호를 따옴표 밖에 씀 | `N'비밀번호'` 형태 유지 |
| 시뮬레이터 "기준정보가 부족합니다" | 빈 DB | 3.2 ⑫ |
| `ready for client`가 안 나옴 | 기동 중 | 30초 후 다시, `docker logs --tail 30 ajin-mssql` |
| 컨테이너가 `Exited` | Codespace 정지 후 재개 | `docker start ajin-mssql` |
| 적재 도구 DELETE 권한 오류 | `--reset` 사용 | 빈 DB에서는 `--reset` 없이 실행 |

### 5.3 [C] 실 DB

| 증상 | 원인 | 조치 |
|---|---|---|
| `Test-NetConnection` False | 방화벽, VPN, 주소 | 전산실 확인 |
| 인증서 오류 | 자체 서명 인증서 | 전산실과 상의 (임의로 `yes` 금지) |
| 시뮬레이터 "test 가 없는 DB" 거부 | 실 DB 보호 | 정상 |

---

## 6. 남은 개선 사항 (코드)

| 항목 | 현재 상태 | 필요한 작업 |
|---|---|---|
| 용접부위 등록 ID 혼용 | 등록 화면이 `m_machine.machine_id`를 `weld_machine_id`로 보냄. 목록도 설비명이 어긋남 | `admin.py` 목록 조인, `admin/index.js` 선택값을 `m_weld_machine` 기준으로 수정 |
| 화면 등록 불가 기준정보 | 제품, 용접기 상세, 설비 정격, 팁 상태, 사용자 등록 API 없음 | SQL 투입 절차 또는 API 추가 |
| 알람 생성 주체 | LIM/A-00x/VIS_NG 알람은 시뮬레이터만 생성 | 실 수집기에서 같은 형식으로 생성 |
| 조회 전용 역할 | `VIEWER` 없음 | 역할 추가, 조회·추출만 허용 |
| 알람 조치 등록 권한 | 역할 검사 없음 | `alarm.py`의 `register_action`에 역할 검사 |
| 첫 로그인 비밀번호 변경 | `force_change_yn` 미사용 | `auth.py`에서 강제 |
| 계정 전환 시 메뉴 | 사이드바를 한 번만 그림 | 로그인 사용자가 바뀌면 다시 그리기 (`main.js` `boot()`) |
| Windows 인증 | 미지원 | `db_mssql.py`에 `Trusted_Connection=yes` 옵션 |
| 비밀번호 특수문자 | `;` `{` `}` 포함 시 연결 문자열 깨짐 | `PWD={...}` 형태로 감싸기 |
| 쿼리 타임아웃 | 없음 | 연결에 쿼리 타임아웃 설정 |
| `db_mssql.execute()` 생성 ID | INSERT와 `SCOPE_IDENTITY()`가 다른 배치 | 한 배치로 실행 (현재 반환값 사용처는 없음) |
| 인덱스 | 7개 | 운영 데이터 증가 시 `t_sensor_reading.reading_time`, `t_weld_event(weld_point_id, created_at)`, `t_vision_image.detail_id`, `t_alarm_action.alarm_id` 검토 |
| 이미지 경로 | `app/data/vision_images` 고정 | 파일서버 경로 설정화 |
| CORS | `localhost`, `127.0.0.1`만 허용 | 운영 주소 추가 |
| `t_alarm_action` 칼럼 | 소속·사번·연락처가 `action_desc` 문자열 안 | 칼럼 분리 |
| 설계서 | `password_hash` 설명이 bcrypt/argon2 | scrypt로 정정 |

---

## 7. 미결 설계 사항

| 항목 | 현재 상태 | 결정 필요 |
|---|---|---|
| 허용 값 CHECK | `data_type`, `image_type`만 | OK/NG/PENDING 등을 DB에서 막을지 |
| 팁 상태 저장 | `m_weld_tip_status` 카운터 | 카운터 vs 이력에서 계산 |
| 센서값 적재 조건 | 변화/이탈 시만으로 가정 | 적재 기준 확정 |
| LOT 판정 규칙 | `final_result`, `overall_result` | 설계서 기준 확인 |
| 인덱스 명명 | `t_lot_index_0` 형식 | 회사 규칙 확인 |
| 백엔드 운영 위치 | 미정 | PC 실행 vs 사내 서버 |

---

## 8. 변경 이력

### v1.6
- 문서를 환경별로 재편: [A] SQLite, [B] MSSQL 테스트(Codespaces), [C] MSSQL 실 DB
- [B] 구조 변경: DB와 백엔드를 Codespace에서 실행, 이 PC는 화면만 실행하고 8000만 전달 (1433 전달 방식은 SQL 시간 초과로 폐기)
- [B] 절차 추가: 새 Codespace, SQL 확장, ODBC Driver 18(Linux) 설치, Codespace `.env` 생성, 시뮬레이터용 기준정보 적재 순서
- 계정을 DB 접속 계정과 앱 로그인 계정으로 구분, 해시 생성(PowerShell, bash)과 INSERT 절차 통합
- `test.sql`, `test_insert.sql`(임의 값) 추가, POP DB 칸 동작 설명
- `main.js`에 관리자 화면 가드 추가 (OPERATOR의 `#/admin` 접근 차단)
- 계정 전환 시 사이드바 메뉴가 안 바뀌는 현상과 대처 기록
- 문제 해결 표를 환경별로 정리
- 4절 용어 정리: `.env`에 넣는 "DB 접속 계정(전산실 발급 SQL 로그인)"과 화면 "앱 로그인 계정(m_user)"을 구분, 서버 인증 모드 확인 쿼리 추가

### v1.5
- DDL v1.1: `updated_at` 4개 추가, 칼럼 196 → 200
- 기준정보 6개 항목 관리 화면, 레시피 등록(버전 관리), 관리자 API
- 테스트 DB 접속 계정 fa00, 데모 계정 operator1 비활성화

### v1.4 이전
- v1.4: 테스트 DB 접속 계정 sa → fa00
- v1.3: 환경 구분, 데이터 보존 원칙, 장애 복구, 스냅샷 비교
- v1.2: KST 통일, MSSQL 드라이버, 비밀번호 변경 절차
- v1.1: 알람 조치 팝업, 설정 패널, 공정 연결 상태, 반응형 화면

---

## 9. 관련 문서
- 설계서: `Weld_Vision_DB설계서_1026_MSSQL_1.xlsx` (MSSQL, 칼럼 200), `Weld_Vision_DB설계서_1021_1.xlsx` (SQLite)
- 생성 스크립트: `mssql_query.sql` (v1.1)
- 테스트 데이터: `test.sql`, `test_insert.sql` ([B] 전용)
- 구 Codespace 스크립트: `start_all.sh`, `stop_all.sh` (3.11)