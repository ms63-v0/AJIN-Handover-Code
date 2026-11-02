<div align="center">

# 🟡 AJIN HW 품질관리 시스템

### 인수인계 가이드 · 실 DB(MSSQL) 연동 버전

![Version](https://img.shields.io/badge/version-v1.1.0-FFC83D?style=for-the-badge&labelColor=1D1D1F)
![Python](https://img.shields.io/badge/Python-3.10%2B-FFC83D?style=for-the-badge&logo=python&logoColor=1D1D1F&labelColor=1D1D1F)
![FastAPI](https://img.shields.io/badge/FastAPI-backend-FFC83D?style=for-the-badge&labelColor=1D1D1F)
![MSSQL](https://img.shields.io/badge/MSSQL-HW__Q__DB-FFC83D?style=for-the-badge&labelColor=1D1D1F)
![Status](https://img.shields.io/badge/status-DB_연동_완료-FFC83D?style=for-the-badge&labelColor=1D1D1F)

공정 품질 데이터(LOT, 용접, 비전 검사, 알람, 기준정보)를 **사내 MSSQL 실 DB**에서 읽고 쓰는 웹 시스템입니다.
이 문서는 처음 이 프로젝트를 맡는 사람이 **설치 → 설정 → 실행 → 문제 해결**까지 혼자 할 수 있도록 작성했습니다.

</div>

---

## 🟡 목차

- [0. 한눈에 보기](#0-한눈에-보기)
- [1. 시스템 구성](#1-시스템-구성)
- [2. 폴더 구조](#2-폴더-구조)
- [3. 시작 전 준비](#3-시작-전-준비)
- [4. 설치하기](#4-설치하기-처음-한-번만)
- [5. .env 작성 가이드](#5--env-작성-가이드-가장-중요)
- [6. 실행하기](#6-실행하기)
- [7. 화면 안내](#7-화면-안내)
- [8. 기준정보 관리 사용법](#8-기준정보-관리-사용법-관리자)
- [9. 로그인과 보안](#9-로그인과-보안)
- [10. 자주 발생하는 문제](#10-자주-발생하는-문제-해결-방법)
- [11. 현재 진행 상황](#11-현재-진행-상황)
- [12. 인수인계 체크리스트](#12-인수인계-체크리스트)
- [13. 연락처](#13-연락처)
- [14. 변경 이력](#14-변경-이력)

---

## 🟡 0. 한눈에 보기

| 항목 | 내용 |
|---|---|
| 🎯 무엇을 하는가 | 용접 공정 데이터 조회, 비전 검사 결과 확인, 알람 관리, 기준정보 등록·수정 |
| 🗄️ 데이터 저장소 | 사내 MSSQL 서버의 `HW_Q_DB` 데이터베이스 |
| 🧩 구성 | 백엔드(API 서버, Python FastAPI) + 프론트엔드(웹 화면, HTML/JS) |
| 🌐 접속 주소 | 백엔드 `http://127.0.0.1:8000` · 화면 `http://127.0.0.1:5173` |
| ✅ 현재 상태 | 실 DB 연결, 로그인, 기준정보 읽기·쓰기 검증 완료 |
| 🚧 남은 과제 | PLC–Kepware 연동 재설정, Kepware–DB 연동 수행 (11장 참고) |

---

## 🟡 1. 시스템 구성

```
[사용자 브라우저]
      │  http://127.0.0.1:5173
      ▼
[UI 서버: serve_ui.py]  ── 화면 파일(frontend 폴더)을 제공
      │
      │  (화면의 모든 데이터 요청)
      ▼
[백엔드 API 서버: backend]  http://127.0.0.1:8000
      │  .env 의 MSSQL_* 설정으로 접속
      ▼
[사내 MSSQL 서버]  데이터베이스: HW_Q_DB
```

- 사용자는 **화면 주소(5173)** 만 엽니다.
- 화면은 백엔드(8000)에 데이터를 요청하고, 백엔드가 MSSQL에서 값을 읽어 돌려줍니다.
- 로그인하지 않은 상태에서는 업무 데이터 요청이 모두 거부됩니다(401).

---

## 🟡 2. 폴더 구조

```
app/
├─ backend/                 API 서버 (데이터 처리 로직)
│  ├─ main.py               서버 시작점, 라우터 등록
│  ├─ config.py             화면·집계 설정값 (알람 우선순위, 조회 기간 한도, 조치 가이드 등)
│  ├─ db.py                 DB 연결 선택 (.env 의 DB_BACKEND 읽기)
│  ├─ db_mssql.py           MSSQL 연결 (pyodbc)
│  ├─ db_sqlite.py          (로컬 개발용, 실 DB 운영에서는 사용하지 않음)
│  ├─ sqldialect.py         MSSQL 문법 조각 모음 (직접 SQL 문법을 쓰지 말고 여기 함수 사용)
│  ├─ security.py           비밀번호 해시, 로그인 쿠키 서명
│  ├─ alarms.py / report.py / vision_image.py / common.py   알람·보고서·비전 이미지·공통 처리
│  └─ routers/              화면별 API
│     ├─ auth.py            로그인/로그아웃, 로그인 이력
│     ├─ master.py          라인·설비·스테이션 기준정보 조회
│     ├─ admin.py           기준정보 등록·수정 (관리자 전용 메뉴)
│     ├─ dashboard.py       대시보드
│     ├─ weld.py            용접 현황
│     ├─ vision.py          비전 검사 현황
│     ├─ lots.py            Lot 조회
│     ├─ alarm.py           알람 이력 조회·조치
│     ├─ live.py            실시간 데이터
│     └─ export.py          PDF·Excel·CSV 추출
├─ frontend/                웹 화면 (index.html, css/, js/)
├─ data/
│  └─ .secret               로그인 서명 키 (자동 생성, 삭제 금지 — 9장 참고)
├─ serve_ui.py              UI 서버 실행 파일
├─ requirements.txt         설치할 Python 패키지 목록
├─ .env                     DB 접속 정보 (직접 작성, 저장소에 올리지 않음)
├─ .env.example             .env 작성 예시 (저장소에 포함)
├─ .gitignore               저장소에서 제외할 파일 목록
└─ README.md                이 문서
```

> 실 DB의 테이블 생성 스크립트(`mssql_query.sql`)는 DB 담당자가 보관합니다. 이 프로젝트 폴더에는 포함되어 있지 않습니다.

---

## 🟡 3. 시작 전 준비

### 3-1. PC 환경

| 항목 | 요구 사항 |
|---|---|
| 운영체제 | Windows 10 이상 |
| Python | 3.10 이상 (설치 후 `py --version` 으로 확인) |
| ODBC 드라이버 | **ODBC Driver 18 for SQL Server** (Microsoft 공식 사이트에서 설치) |
| 네트워크 | 사내망 연결 또는 VPN 연결 상태에서 DB 서버에 접근 가능해야 함 |
| 방화벽 | DB 서버의 **TCP** 포트 접근이 허용되어 있어야 함 (전산팀 확인) |

ODBC 드라이버 설치 확인:

```powershell
py -c "import pyodbc; print(pyodbc.drivers())"
```

출력 목록에 `ODBC Driver 18 for SQL Server`가 있어야 합니다. 없으면 드라이버를 먼저 설치하세요.

### 3-2. 필요한 정보 받아 두기

> [!WARNING]
> 아래 값은 **담당자에게 받아야 하며**, 이 문서나 메신저에 적지 않습니다.

| 필요한 것 | 누구에게 | 비고 |
|---|---|---|
| DB 서버 IP 주소와 포트 | 서버PC | 서버 PC에 고정 IP 확인 |
| DB 접속 계정(`app_user` 등)과 비밀번호 | DB 담당자 | SQL 인증 계정, 읽기·쓰기 권한 |
| 인증서 사용 여부 | 전산팀 | 자체 인증서면 `MSSQL_TRUST_CERT=yes` |

---

## 🟡 4. 설치하기 (처음 한 번만)

프로젝트 폴더(`app`)에서 PowerShell을 열고 아래를 순서대로 실행합니다.

```powershell
# 1) 가상환경 만들기 (폴더 이름은 .venv 로 고정)
py -m venv .venv

# 2) 가상환경 켜기 (명령 앞에 (.venv) 가 보이면 성공)
.\.venv\Scripts\activate

# 3) 필요한 패키지 설치
pip install -r requirements.txt
```

> 가상환경을 켠 상태에서만 아래 명령을 실행하세요. 창을 새로 열 때마다 2)를 다시 실행해야 합니다.

---

## 🟡 5. `.env` 작성 가이드 (가장 중요)

`.env`는 **DB 접속 정보를 담는 파일**입니다. 프로젝트 최상위(`app` 폴더, `backend` 폴더와 같은 위치)에 만들어야 합니다.

### 5-1. 만드는 방법

1. `app` 폴더에 있는 `.env.example` 파일을 복사합니다.
2. 복사본 이름을 `.env`로 바꿉니다.
   - 탐색기에서 이름이 `.env`만 남도록 입력하면 됩니다.
3. 메모장이나 VS Code로 열어 아래 표의 값을 채웁니다.

> [!CAUTION]
> 파일 이름이 `.env.txt`로 바뀌면 프로그램이 읽지 못합니다. 탐색기에서 **보기 → 파일 확장명**을 켜고 확인하세요.

### 5-2. 항목 설명

| 항목 | 의미 | 값 예시 | 필수 |
|---|---|---|---|
| `DB_BACKEND` | 사용할 DB 종류 | `mssql` (실 DB는 반드시 이 값) | ✅ |
| `MSSQL_SERVER` | DB 서버 주소와 포트 (쉼표로 구분) | `<서버IP>,<HOST>` | ✅ |
| `MSSQL_DATABASE` | 사용할 데이터베이스 이름 | `HW_Q_DB` | ✅ |
| `MSSQL_USER` | DB 접속 계정 | `app_user` (담당자 발급) | ✅ |
| `MSSQL_PASSWORD` | DB 접속 비밀번호 | (담당자 발급) | ✅ |
| `MSSQL_DRIVER` | ODBC 드라이버 이름 | `ODBC Driver 18 for SQL Server` | ✅ |
| `MSSQL_TRUST_CERT` | 서버 인증서 검사 생략 여부 | `yes` 또는 `no` | ✅ |
| `MSSQL_CHAR_ENCODING` | 한글이 깨져 보일 때만 지정 | `cp949` | ⬜ 선택 |

### 5-3. 완성 예시

아래를 복사해서 `.env` 파일에 붙여 넣고, `<...>` 부분만 실제 값으로 바꿉니다.

```env
DB_BACKEND=mssql
MSSQL_SERVER=<서버IP>,<PORT>
MSSQL_DATABASE=HW_Q_DB
MSSQL_USER=<DB접속계정>
MSSQL_PASSWORD=<DB접속비밀번호>
MSSQL_DRIVER=ODBC Driver 18 for SQL Server
MSSQL_TRUST_CERT=yes
```

한글이 깨질 때만 마지막 줄에 아래를 추가합니다.

```env
MSSQL_CHAR_ENCODING=cp949
```

### 5-4. 반드시 지킬 규칙

| 규칙 | ❌ 틀린 예 | ✅ 맞는 예 |
|---|---|---|
| 값 뒤에 설명 주석을 쓰지 않는다 | `MSSQL_TRUST_CERT=yes   # 테스트용` | `MSSQL_TRUST_CERT=yes` |
| 값을 따옴표로 감싸지 않는다 | `MSSQL_USER="app_user"` | `MSSQL_USER=app_user` |
| `=` 앞뒤에 공백을 넣지 않는다 | `MSSQL_USER = app_user` | `MSSQL_USER=app_user` |
| 비어 있는 값을 남기지 않는다 | `MSSQL_PASSWORD=` | 실제 비밀번호 입력 |
| 주석은 줄 맨 앞에 `#`으로 쓴다 | `# 서버 설정` (한 줄 전체) | 맞음 |

> [!WARNING]
> 값 뒤에 `#`으로 설명을 붙이면 설명까지 값으로 읽힙니다. 예를 들어 `MSSQL_CHAR_ENCODING=cp949   # 설명`은 인코딩 이름이 `cp949   # 설명`이 되어 한글 처리가 실패합니다.

### 5-5. 값이 맞는지 확인하기

```powershell
Get-Content .env | Select-String "DB_BACKEND|MSSQL_SERVER|MSSQL_DATABASE|MSSQL_USER|MSSQL_DRIVER|MSSQL_TRUST_CERT"
```

비밀번호(`MSSQL_PASSWORD`)는 화면에 출력하지 않습니다. 이 명령의 결과를 메신저나 문서에 붙여 넣지 마세요.

### 5-6. `.env`의 보안

> [!CAUTION]
> `.env`에는 DB 비밀번호가 들어 있습니다. **GitHub 저장소, 메신저, 메일에 올리거나 보내지 마세요.**

- `.gitignore`에 `.env`가 들어 있어 저장소에는 올라가지 않습니다. 저장소에 `.env`가 보이면 즉시 담당자에게 알리고 비밀번호를 바꾸세요.
- 백업 파일이나 압축 파일을 만들 때도 `.env`를 포함하지 마세요.

---

## 🟡 6. 실행하기

프로젝트 폴더에서 **터미널 두 개**를 엽니다. 두 곳 모두 가상환경(`.venv`)을 켠 상태여야 합니다.

### 터미널 1: 백엔드 (API 서버)

```powershell
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

`Uvicorn running on http://127.0.0.1:8000` 이 보이면 성공입니다. 이 창은 닫지 말고 두세요.

연결 확인 (브라우저에서 열기):

```
http://127.0.0.1:8000/health
```

아래처럼 나오면 정상입니다.

```json
{"status": "ok", "backend": "mssql"}
```

`backend` 값이 `mssql`이 아니면 `.env`의 `DB_BACKEND`를 확인하세요.

### 터미널 2: 화면 (UI 서버)

```powershell
python serve_ui.py
```

### 접속

브라우저에서 아래 주소를 엽니다.

```
http://127.0.0.1:5173
```

앱 로그인 계정으로 로그인합니다. 계정이 없으면 시스템 관리자에게 요청하세요.

### 종료

각 터미널 창에서 `Ctrl + C`를 누릅니다.

---

## 🟡 7. 화면 안내

| 메뉴 | 하는 일 | 권한 |
|---|---|---|
| 📊 대시보드 | 주요 현황 요약, 불량 유형 분포, 추이 그래프 | 전체 |
| 🔥 용접 현황 | 용접부위(파트)별 전류·통전시간·냉각수·공압 등 센서 값과 용접 결과 | 전체 (조회 기간 최대 7일) |
| 👁️ 비전 검사 현황 | 카메라별 검사 결과, 검사 이미지, NG 상세 | 전체 (조회 기간 최대 31일) |
| 🔎 Lot 조회 | LOT 단위 실적과 결과 검색 | 전체 (조회 기간 최대 31일) |
| 🔔 알람 이력 조회 | 알람 발생·해제 이력, 조치 내용 등록 | 전체 (조회 기간 최대 31일) |
| ⚙️ 기준정보 관리 | 라인·공정·설비·용접 부위·파라미터·레시피 등록과 수정 | **관리자(ADMIN)만** |

화면 오른쪽 위 사용자 메뉴의 **설정**에서 화면 옵션을 바꿀 수 있습니다.

<details>
<summary><b>🟡 데이터 추출 규칙 (펼쳐 보기)</b></summary>

Lot 조회, 알람, 비전 검사 화면에서 PDF, Excel, CSV로 내려받을 수 있습니다.

- PDF·Excel은 **10만 행까지** 바로 만들어지고, 그 이상은 CSV를 사용합니다.
- PDF의 상세 표는 **2,000행까지**입니다. 전체 데이터는 Excel 또는 CSV로 받으세요.
- 추출 기록(누가, 언제, 무엇을)이 DB에 남습니다.

</details>

---

## 🟡 8. 기준정보 관리 사용법 (관리자)

1. 관리자 계정으로 로그인합니다.
2. 왼쪽 메뉴에서 **기준정보 관리**를 누릅니다.
3. 상단 탭에서 대상을 고릅니다 (라인, 공정, 설비, 용접부위, 파라미터, 레시피).
4. 등록은 입력 후 저장, 수정은 해당 행을 선택해 값을 바꾸고 저장합니다.
5. **사용 여부**를 `중지`로 바꾸면 화면과 집계에서 그 항목이 빠집니다. 데이터를 지우는 것이 아니므로 되돌릴 수 있습니다.

> [!IMPORTANT]
> 기준정보를 **삭제하지 말고 사용 여부를 중지**로 바꾸세요. 과거 실적이 연결되어 있어 삭제는 막히거나 이력이 깨질 수 있습니다.

## 🟡 8-1. 앱 로그인 계정 관리

> 이 장은 **화면에 로그인하는 계정(앱 로그인 계정)** 을 만들고 관리하는 방법입니다.
> `.env`에 넣는 **DB 접속 계정**과는 다른 계정입니다.

| 구분 | 용도 | 어디에 저장 | 누가 관리 |
|---|---|---|---|
| DB 접속 계정 (`.env`의 `MSSQL_USER`) | 백엔드가 DB에 접속 | SQL Server 로그인 | DB 담당자 |
| 앱 로그인 계정 (화면 ID/PW) | 화면에 로그인 | DB 안 `m_user` 테이블 | 시스템 관리자 |

> [!CAUTION]
> - 비밀번호, 해시 값(`scrypt$...`)은 **채팅, 메신저, 메일, 이 문서에 붙여 넣지 마세요.**
> - 계정 정보는 발급 대장에 **ID, 이름, 역할, 발급일**만 기록합니다. 비밀번호는 기록하지 않습니다.
> - 데모용 계정(`admin`, `operator1`)이 실 DB에 남아 있다면 **즉시 비활성화하거나 비밀번호를 바꾸세요.**

### 8-1-1. 역할(role_code)

| 역할 | 할 수 있는 것 |
|---|---|
| `ADMIN` | 기준정보 등록·수정, 알람 조치 등록, 기준정보 메뉴 사용 |
| `MANAGER` | 알람 조치 등록 |
| `OPERATOR` | 알람 조치 등록, 조회 |

- 모든 역할이 조회 화면과 데이터 추출을 쓸 수 있습니다.
- `VIEWER`(조회 전용) 역할은 아직 없습니다. 필요하면 개선 목록을 참고하세요.

### 8-1-2. 계정 발급 절차

1. **요청**: 사용자 이름, 부서, 로그인 ID, 역할을 시스템 관리자에게 전달합니다.
2. **승인**: 관리자가 요청을 확인하고 승인합니다.
3. **비밀번호 생성**: 아래 8-1-3 방법으로 해시를 만듭니다. 비밀번호는 **본인이 직접 입력**하거나, 발급 담당자가 본인에게 직접 전달합니다.
4. **계정 등록**: 아래 8-1-4의 INSERT를 DB 접속 계정으로 실행합니다.
5. **로그인 확인**: 화면에서 새 계정으로 로그인합니다.
6. **기록**: 발급 대장에 ID, 이름, 역할, 발급일을 적습니다.

### 8-1-3. 해시 만들기 (PowerShell, `app` 폴더)

비밀번호는 화면에 보이지 않게 입력하고, 명령 기록에도 남지 않습니다.

```powershell
cd "C:\Users\UsersPC\Desktop\qms_mssql_\app"
.\.venv\Scripts\Activate.ps1

$sec   = Read-Host "앱 로그인 비밀번호 (8자 이상)" -AsSecureString
$plain = (New-Object System.Net.NetworkCredential("", $sec)).Password
$hash  = $plain | py -c "import sys; from backend.security import hash_password; print(hash_password(sys.stdin.readline().strip()))"
Remove-Variable plain, sec

$hash
```

- 입력할 때 글자가 보이지 않는 것이 정상입니다.
- 출력된 `scrypt$...` 한 줄을 **앞뒤 공백 없이** 복사합니다. 줄이 나뉘면 로그인이 실패합니다.
- 복사를 마치면 아래를 실행해 메모리에서도 지웁니다.
  ```powershell
  Remove-Variable hash
  ```
- 비밀번호 정책(8자 이상, 대·소문자·숫자·기호 중 3종 이상 권장)은 **운영 규칙으로 지켜야 합니다.** 프로그램이 자동으로 검사하지 않습니다.

> [!NOTE]
> 이 방법은 DB에 접속하지 않습니다. `.venv`와 `requirements.txt` 설치가 되어 있으면 어느 PC에서든 만들 수 있습니다.

### 8-1-4. 계정 등록 (INSERT)

DB 접속 계정으로 SQL Server Management Studio에 연결하고, **대상 DB**를 선택한 뒤 실행합니다.

```sql
USE [<DB 이름>];
GO
IF NOT EXISTS (SELECT 1 FROM dbo.m_user WHERE login_id = N'<로그인 ID>')
BEGIN
    INSERT INTO dbo.m_user
        (login_id, password_hash, user_name, role_code, department, force_change_yn, use_yn)
    VALUES
        (N'<로그인 ID>', N'<8-1-3에서 만든 해시>', N'<이름>', N'<역할>', N'<부서>', N'Y', N'Y');
END
GO
SELECT login_id, role_code, use_yn FROM dbo.m_user ORDER BY user_id;
GO
```

| 자리 | 넣을 값 |
|---|---|
| `<로그인 ID>` | 영문 또는 숫자 ID (예: `hong.gd`) |
| `<8-1-3에서 만든 해시>` | `scrypt$`로 시작하는 한 줄 |
| `<역할>` | `ADMIN`, `MANAGER`, `OPERATOR` 중 하나 |
| `<부서>`, `<이름>` | 실제 값 |

- `force_change_yn`을 `Y`로 두어도 현재 프로그램은 **첫 로그인 때 비밀번호 변경을 강제하지 않습니다.** 발급 담당자가 직접 안내하세요.
- 같은 ID가 있으면 아무것도 추가되지 않습니다. 결과 표에서 ID가 보이는지 확인하세요.

> [!WARNING]
> 쿼리를 한글 입력 상태로 직접 타이핑하면 쉼표나 따옴표가 전각 문자로 바뀌어 `156` 같은 구문 오류가 납니다. **영문 입력 상태에서 작성하거나 파일로 열어서** 실행하세요.

### 8-1-5. 로그인 확인

화면(`http://127.0.0.1:5173`)에서 새 계정으로 로그인합니다.

- 성공하면 대시보드가 열립니다.
- `ADMIN`이면 왼쪽 메뉴에 **기준정보 관리**가 보입니다.
- `OPERATOR`가 주소창에 `#/admin`을 입력하면 대시보드로 이동합니다. 정상입니다.

### 8-1-6. 비밀번호 변경

비밀번호 변경 화면은 없습니다. 아래 순서로 처리합니다.

1. 8-1-3 방법으로 새 해시를 만듭니다.
2. DB 접속 계정으로 아래를 실행합니다.

```sql
UPDATE dbo.m_user
   SET password_hash = N'<새 해시>',
       password_changed_at = DATEADD(HOUR, 9, SYSUTCDATETIME()),
       updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME())
 WHERE login_id = N'<로그인 ID>';
```

- `password_changed_at`과 `updated_at`은 한국 시간 기준입니다. 다른 시간 함수를 쓰지 마세요.

### 8-1-7. 잠금 해제

비밀번호를 5회 틀리면 10분 동안 잠깁니다. 시간이 지나면 자동으로 풀립니다. 바로 풀어야 할 때만 아래를 실행합니다.

```sql
UPDATE dbo.m_user
   SET failed_login_count = 0, locked_until = NULL
 WHERE login_id = N'<로그인 ID>';
```

### 8-1-8. 계정 사용 중지 (퇴직·전보)

**계정을 삭제하지 마세요.** 과거 로그인 이력과 조치 기록이 `m_user`를 참조하고 있어 삭제가 막히거나 이력이 깨집니다. 대신 사용 중지합니다.

```sql
UPDATE dbo.m_user
   SET use_yn = 'N', updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME())
 WHERE login_id = N'<로그인 ID>';
```

- 사용 중지된 계정은 로그인할 수 없습니다.
- 다시 쓰려면 `use_yn`을 `'Y'`로 바꿉니다.

### 8-1-9. 로그인 이력 확인

로그인 실패 원인은 `t_user_login_history` 테이블에 기록됩니다.

```sql
SELECT TOP 50 login_id, login_result, login_time, ip_address
FROM dbo.t_user_login_history
ORDER BY login_time DESC;
```

| 기록 값 | 의미 | 조치 |
|---|---|---|
| `FAIL_NO_USER` | ID가 없거나 사용 중지됨 | ID 오타 확인, `use_yn` 확인 |
| `FAIL_PW` | 비밀번호 불일치 | 비밀번호 재확인, 필요하면 8-1-6 |
| `FAIL_LOCKED` | 5회 실패로 잠김 | 10분 대기 또는 8-1-7 |

### 8-1-10. 자주 막히는 경우

| 증상 | 원인 | 해결 |
|---|---|---|
| 로그인 시 401 | ID 또는 비밀번호 불일치, 사용 중지 | 8-1-9로 실패 원인 확인 |
| 해시를 넣었는데 로그인이 안 됨 | 해시 줄이 나뉘거나 앞뒤 공백이 섞임 | 해시를 다시 복사하여 넣기 |
| 로그인 직후 바로 로그아웃 | 로그인 키 파일이 바뀜 | 다시 로그인 (9장) |
| 기준정보 메뉴가 안 보임 | `ADMIN`이 아니거나 사이드바가 이전 계정 그대로 | 로그아웃 후 다시 로그인, Ctrl+F5 |
| INSERT 후에도 목록에 없음 | 다른 DB에 실행함 | `USE` 문의 DB 이름 확인 |
| `156` 구문 오류 | 전각 기호로 입력됨 | 영문 입력 상태에서 다시 작성 |

### 8-1-11. 점검 체크리스트

- [ ] 발급 요청과 승인 기록이 있다
- [ ] 비밀번호는 본인이 입력했거나 본인에게 직접 전달했다
- [ ] 역할이 요청 내용과 같다 (`ADMIN` 발급은 별도 승인)
- [ ] 발급 대장에 ID, 이름, 역할, 발급일을 기록했다 (비밀번호 제외)
- [ ] 화면에서 새 계정으로 로그인이 된다
- [ ] 실 DB에 데모 계정(`admin`, `operator1`)이 없거나 비활성화되었다
- [ ] 퇴직자 계정은 삭제하지 않고 사용 중지했다
---

## 🟡 9. 로그인과 보안

### 로그인 정책 (`backend/config.py`)

| 항목 | 값 |
|---|---|
| 비밀번호 5회 연속 실패 | 10분 잠김 |
| 로그인 유지 시간 | 12시간 (자동 로그아웃) |
| 쿠키 이름 | `qms_session` |

### 로그인 키 파일 `data/.secret`

- 로그인 쿠키를 검증하는 서명 키입니다. 처음 실행할 때 자동으로 만들어집니다.
- **이 파일을 지우면 모든 사용자가 다시 로그인해야 합니다.** 파일이 외부로 유출되었다고 판단되면 지우고 백엔드를 다시 실행하세요 (새 키가 자동 생성됩니다).
- `data` 폴더 자체를 지우지 마세요.
- 저장소에 올리지 않습니다 (`.gitignore`에 포함).

### 운영 수칙

> [!WARNING]
> - 기본으로 설정된 데모용 비밀번호가 있다면 **즉시 변경**하세요.
> - 공용 계정을 여러 사람이 나눠 쓰지 말고, 사람마다 계정을 따로 만드세요.
> - 이 시스템에서 **LOT 데이터 초기화 기능은 실 DB에서 동작하지 않습니다.** 운영 데이터는 삭제하지 마세요.
> - DB 테이블 구조 변경(추가, 삭제, 컬럼 변경)은 DB 담당자와 함께 진행하세요.

---

## 🟡 10. 자주 발생하는 문제 (해결 방법)

| 증상 | 원인 | 해결 |
|---|---|---|
| `py`를 찾을 수 없다고 나옴 | Python 미설치 또는 PATH 미등록 | Python 재설치 시 "Add python.exe to PATH" 체크 |
| `(.venv)`가 보이지 않음 | 가상환경을 켜지 않음 | `.\.venv\Scripts\activate` 실행 |
| `.env 에 다음 값이 필요합니다: ...` | `.env`의 항목 누락 또는 빈 값 | 5-2 표의 필수 항목이 모두 채워졌는지 확인 |
| `DB_BACKEND 값이 올바르지 않습니다` | 값 오타 | `mssql` 또는 `sqlite`로 정확히 입력 |
| `Data source name not found` | ODBC Driver 18 미설치 | 3-1의 드라이버 설치 후 재시작 |
| `Login failed for user` | DB 계정 또는 비밀번호 틀림 | `.env`의 `MSSQL_USER`, `MSSQL_PASSWORD` 재확인 (담당자에게 재발급 요청) |
| `timeout` 또는 서버를 찾을 수 없음 | 네트워크 또는 방화벽 문제 | 사내망/VPN 연결, IP와 포트 확인, 전산팀에 방화벽 확인 |
| `Invalid object name 'm_line'` | 테이블이 없음 (스키마 미적용) | DB 담당자에게 `mssql_query.sql` 적용 요청 |
| 한글이 `???` 또는 깨져 보임 | DB 문자 인코딩 차이 | `.env`에 `MSSQL_CHAR_ENCODING=cp949` 추가 (주석 없이) |
| 로그인 화면에서 401 | 아이디 또는 비밀번호 틀림, 계정 잠금 | 계정 상태 확인 (잠금은 10분 후 자동 해제) |
| 로그인 후 바로 로그아웃됨 | 쿠키 문제 또는 `data/.secret` 변경 | 시크릿 창에서 다시 로그인 |
| 화면은 열리지만 값이 비어 있음 | 해당 기간에 데이터 없음 또는 수집 연동 전 | 조회 기간 변경, 11장의 연동 상태 확인 |
| 500 오류 또는 "서버 처리 중 오류" | 백엔드 내부 오류 | 백엔드 터미널의 빨간 로그 메시지를 개발자에게 전달 |
| 포트 8000 또는 5173 사용 중 | 이전 실행이 남아 있음 | 이전 터미널을 `Ctrl + C`로 종료 후 재실행 |
| 화면 메뉴가 바뀌지 않음 | 브라우저 캐시 | `Ctrl + Shift + R`로 새로고침 |

> 위 표에 없는 오류는 **오류 메시지 전체**(빨간 글씨)와 **발생 시각**을 기록해서 담당자에게 전달하세요.

---

## 🟡 11. 현재 진행 상황

### ✅ 완료

- 실 DB(`HW_Q_DB`) 생성과 백업 설정
- 백엔드와 화면의 DB 연결, 로그인 확인
- 기준정보 **읽기** 검증: DB에 입력한 값이 화면에 표시됨
- 기준정보 **쓰기** 검증: 화면에서 등록·변경한 내용이 DB에 저장됨 (사용 여부 변경, 수정 시각 기록)

### 🚧 남은 과제

| 순서 | 과제 | 내용 |
|---|---|---|
| 1 | PLC와 Kepware 연동 재설정 | Kepware를 새로 설치하여 PLC 통신 설정을 다시 구성 |
| 2 | Kepware와 DB 연동 요구사항 정의 | 어떤 PLC 값을 어떤 주기와 형식으로 DB에 저장할지 정리 |
| 3 | Kepware와 DB 연동 수행 및 검증 | 정의한 요구사항대로 연동하고 읽기·쓰기를 검증 |

> [!NOTE]
> 연동 완료 전까지는 설비 실시간 값이 DB에 계속 들어오지 않을 수 있습니다. 화면의 값을 현재 설비 상태로 판단하기 전에 DB에서 최근 적재 시각을 먼저 확인하세요.

### 🧹 정리 예정 (인수인계 후 진행 가능)

- 검증용 테스트 데이터 정리: `m_line`의 `TEST_0426`, `TEST_1st`, `TEST_WRITE_01` (DB 담당자 승인 후 삭제)
- 화면의 테스트용 요소 제거: 사이드바 하단 "POP DB" 표시 영역

---

## 🟡 12. 인수인계 체크리스트

인수받는 사람이 아래를 순서대로 확인하면 됩니다.

- [ ] 저장소 주소를 알고 접속할 수 있다 (`ms63-v0/HW-Automation-Facility-Data-System`)
- [ ] Python과 ODBC Driver 18을 설치했다
- [ ] 사내망 또는 VPN에 연결되어 있고 DB 서버에 접근할 수 있다
- [ ] DB 접속 계정과 비밀번호를 담당자에게 받았다
- [ ] 앱 로그인 계정을 받았고, 비밀번호를 변경했다
- [ ] `.env`를 작성했고 5-5의 확인 명령으로 값을 점검했다
- [ ] `pip install -r requirements.txt`가 오류 없이 끝났다
- [ ] `http://127.0.0.1:8000/health`에서 `"backend": "mssql"`이 보인다
- [ ] `http://127.0.0.1:5173`에서 로그인이 된다
- [ ] 대시보드, Lot 조회, 기준정보 관리 화면이 열린다
- [ ] 저장소에 `.env`와 `data/.secret`이 없다

---

## 🟡 13. 연락처

| 역할 | 담당 | 연락처 |
|---|---|---|
| 👤 프로젝트 담당 (인수인계자) | 진민수 | 010-8744-6102 |
| 🗄️ DB 담당 (DB 계정, 스키마, 백업) | - | - |
| 🖥️ 전산팀 (네트워크, 방화벽, 서버) | | |
| 🔧 설비 담당 (PLC, Kepware) | | |

---

## 🟡 14. 변경 이력

| 버전 | 날짜 | 내용 |
|---|---|---|
| v1.1.0 | 2026-10-28 | 실 DB(HW_Q_DB) 전환 완료, 로그인·읽기·쓰기 검증, 인수인계용 문서 작성 |

---

<div align="center">

🟡 **AJIN QMS** · 인수인계 문서 · v1.1.0

</div>
