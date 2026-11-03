# 개발 가이드

[문서 허브](../README.md) · [설치·실행](setup.md) · [사용자 설명서](user-guide.md) · [개발](development.md) · [운영·장애 대응](operations.md) · [변경·배포](release.md) · [인수인계](handover.md)

코드 구조, 데이터 흐름, 코드만으로는 알기 어려운 업무 규칙, 수정 후 검증 방법입니다.

> 문서 기준 V1.1 (2026-11-02). 본문의 장 번호(예: `12-3`, `18장`)는 전체 인수인계 문서 기준입니다. 장별 위치는 [문서 허브의 장 번호 안내](../README.md#장-번호-안내)에 있습니다.

## 목차

- 3. 시스템 구성과 데이터 흐름
- 5. 소스 코드 위치·접근·구조
- 12. 핵심 업무 규칙
- 18. 테스트와 검증

---

## 3. 시스템 구성과 데이터 흐름

### 3-1. 전체 구성

```text
[센서] ─(미연결)─► [PLC] ──► [Kepware] ──► [사내 MSSQL: HW_Q_DB] ◄── [백엔드 :8000] ◄── [UI 서버 :5173] ◄── 브라우저
                   연결 완료    DB 전송 구현                         읽기·일부 쓰기       화면 파일 전달
```

| 구간 | 상태 | 담당 |
|---|---|---|
| 센서 ↔ PLC | **미연결 (남은 연동 작업)** | 설비 담당 |
| PLC ↔ Kepware | 연결 완료 | 설비 담당 |
| Kepware → DB | 전송 구현 완료 · 센서 연결 후 값 검증 필요 | 설비 담당 |
| DB ↔ 백엔드 ↔ 화면 | 동작 확인 | 프로젝트 담당 |

### 3-2. 화면 요청 흐름 (예: Lot 조회 [조회] 버튼)

| 순서 | 일어나는 일 | 코드 위치 |
|---|---|---|
| 1 | 화면에서 조건을 받아 요청 | `frontend/js/pages/lot/` |
| 2 | 백엔드로 요청 전송 `GET /api/lots` | `frontend/js/api.js` |
| 3 | 로그인 쿠키 확인 (없으면 401) | `backend/security.py` |
| 4 | DB 조회 | `backend/routers/lots.py` → `backend/db.py` |
| 5 | 결과를 표와 상세 패널에 표시 | `frontend/js/pages/lot/` |

### 3-3. 누가 어느 테이블에 쓰는가

| 쓰는 주체 | 테이블 | 시점 |
|---|---|---|
| Kepware | `t_lot`, `t_loading_event`, `t_weld_event`, `t_sensor_reading`, `t_vision_inspection`, `t_vision_inspection_detail`, `t_vision_image`, `t_alarm_event` (발생) | 설비 이벤트 발생 시 (13장) |
| 백엔드 (로그인) | `m_user` (실패 횟수·잠금·마지막 로그인), `t_user_login_history` | 로그인 시도마다 |
| 백엔드 (기준정보 관리) | `m_line`, `m_station`, `m_machine`, `m_weld_point`, `m_parameter`, `m_recipe`, `m_recipe_target` | ADMIN이 저장할 때 |
| 백엔드 (알람) | `t_alarm_event` (확인·해결 시각), `t_alarm_action` | 확인·조치 등록 시 |
| 관리자 (SQL) | `m_user` 발급·변경, `m_product`, `m_weld_machine`, `m_machine_spec` | 필요 시 (14·15장) |

> [!NOTE]
> 화면별로 어느 테이블을 읽는지는 10장 표에, 테이블·칼럼 전체 정의는 **상세 설명서 5장**(24-2)에 있습니다.

---

## 5. 소스 코드 위치·접근·구조

### 5-1. 저장소와 접근 권한

| 항목 | 내용 |
|---|---|
| 저장소 | `https://github.com/ms63-v0/HW-Automation-Facility-Data-System` (저장소 루트 = `app` 폴더) |
| 공개 범위 | `<Public / Private 확인 후 기입>` (16-5) |
| 브랜치 운영 | `<기본 브랜치 이름>` = 운영 반영 기준 · 작업용 브랜치 규칙 `<기입>` |
| 접근 권한 신청 | `<신청 경로 기입: 예) 프로젝트 담당에게 GitHub 계정 전달 → Collaborator 초대>` |
| 권한 회수 | 담당 변경·퇴직 시 Collaborator에서 제거 (16-3) |
| 저장소에 없는 것 | `.env`, `data/.secret`, `.venv`, `mssql_query.sql`(DB 담당 보관) |

### 5-2. 폴더 구조

```text
app/
├─ backend/                     API 서버
│  ├─ main.py                   ★ 진입점: 서버 시작, 라우터 등록, CORS, /health
│  ├─ config.py                 업무 설정값 (로그인 정책, 조회 한도, 알람 우선순위·조치 가이드)
│  ├─ db.py                     .env 로딩, DB_BACKEND로 드라이버 선택
│  ├─ db_mssql.py               MSSQL 연결
│  ├─ db_sqlite.py              개발용 SQLite 연결 (운영 미사용, 5-5)
│  ├─ sqldialect.py             SQLite·MSSQL 문법 차이 흡수
│  ├─ security.py               비밀번호 해시(scrypt), 쿠키 서명, 로그인 확인
│  ├─ alarms.py                 알람 해석 규칙 (유형·우선순위·상태·현장 복구) — 12-2·12-3
│  ├─ common.py                 기간 계산, 파트 종합 판정, 불량 분포 — 12-1
│  ├─ report.py / vision_image.py    PDF·Excel 보고서, 비전 이미지 표시
│  └─ routers/                  화면별 API (파일명 = 기능)
│     ├─ auth.py  master.py  admin.py  dashboard.py  weld.py
│     └─ vision.py  lots.py  alarm.py  live.py  export.py
├─ frontend/
│  ├─ index.html                ★ 화면 진입점
│  ├─ css/                      디자인
│  └─ js/
│     ├─ main.js                화면 라우팅 (#/dashboard 등)
│     ├─ api.js                 백엔드 요청 함수 모음
│     ├─ config.js              API 주소, 메뉴, 갱신 주기, 센서 표시 규칙
│     ├─ pages/                 메뉴별 화면
│     └─ components/            공통 부품 (사이드바, 차트, 팝업 등)
├─ data/.secret                 로그인 서명 키 (자동 생성)
├─ serve_ui.py                  ★ 화면 서버 진입점 (:5173)
├─ requirements.txt             Python 패키지 목록
├─ .env / .env.example          DB 접속 정보 / 견본 (8장 주의)
├─ docs/                        인수인계 문서 (설치, 사용자, 개발, 운영, 배포, 인수인계)
└─ README.md                    문서 허브 (저장소 첫 화면)
```

### 5-3. 고치려는 기능이 어디에 있나

| 바꾸고 싶은 것 | 볼 파일 |
|---|---|
| 화면 모양·문구 | `frontend/js/pages/<화면>/`, `frontend/css/` |
| 화면이 부르는 API 주소 | `frontend/js/api.js` |
| 화면 갱신 주기, 센서 표시 이름·소수 자리 | `frontend/js/config.js` |
| 조회 조건, 집계 쿼리 | `backend/routers/<기능>.py` |
| 알람 등급, 조치 가이드, 조회 기간 한도, 로그인 정책 | `backend/config.py` |
| 알람 유형·상태 판단 | `backend/alarms.py` |
| 판정·불량 집계 | `backend/common.py` |
| 허용 주소(CORS) | `backend/main.py` |
| PDF·Excel·CSV 형식 | `backend/routers/export.py`, `backend/report.py` |

### 5-4. 코드 설명 수준 안내

| 코드 유형 | 이 문서에서 다루는 수준 | 예 |
|---|---|---|
| 단순 조회·저장 | 용도와 테이블만 (10장, 상세 설명서 2.3) | `master.py`, `admin.py` |
| 화면과 공유하는 API | 경로·권한·테이블 (상세 설명서 2.3) | `/api/lots`, `/api/alarms` |
| 핵심 업무 로직 | **규칙·근거·예외까지 (12장)** | 판정, 알람 상태, 기준 이탈 |
| 임시 우회·호환 처리 | **이유와 제거 조건 (5-5)** | SQLite 분기, 조치 정보 접두어 |

코드 수정 시 함수 주석(docstring)도 함께 갱신하세요. 핵심 함수에는 이미 규칙 설명이 주석으로 달려 있습니다(`alarms.py`, `common.py`, `routers/alarm.py`).

### 5-5. 임시 처리·호환 코드 목록

| 위치 | 무엇을 하나 | 왜 있나 | 제거·변경 조건 |
|---|---|---|---|
| `db.py` 기본값 `sqlite` | `DB_BACKEND`가 없으면 SQLite로 동작 | 개발 시절 기본값 | 운영 전환 시 "값 없으면 오류"로 변경 (22장) |
| `db_sqlite.py`, `sqldialect.py` | 두 DB 문법 동시 지원 | 개발용 SQLite 병행 | SQLite 폐기 결정 시 제거, `sqldialect`는 MSSQL 전용으로 단순화 |
| `/api/auth/reset-db` | 실적 초기화 | 개발 데이터 초기화용, 실 DB에서는 차단 | SQLite 제거 시 함께 제거 |
| `config.js`, `serve_ui.py`의 Codespaces 분기 | 원격 개발 환경에서 `/api` 전달 | 개발 환경 지원 | 사용하지 않으면 제거 |
| `vision.py`의 `sim://` 경로 | 데모용 생성 이미지 표시 | 시뮬레이터 데이터 호환 | 실제 이미지 경로로 운영 확인 후 제거 |
| `t_alarm_action.action_desc` 접두어 `[구분\|소속\|사번\|연락처]` | 조치 구분·작업자 정보를 내용 앞에 저장 | 전용 칼럼 없음 | 칼럼 추가 후 분리 (22장) |
| `DEFECT_CATALOG` (config.py) | 불량 유형 이름 목록 | 시뮬레이터용, 분포 차트는 DB 실제 값 집계 | 현장 불량 코드 확정 시 정리 |
| 사이드바 "POP DB" 표시 | 연동 확인용 값 표시 | 개발 중 확인용 | 제거 예정 |

---

## 12. 핵심 업무 규칙

> 코드만 읽어서는 알기 어려운 **판정·계산·상태 규칙**입니다. 규칙을 바꿀 때는 이 장, 코드 주석, 18장 검증 항목을 함께 고칩니다.

### 12-1. LOT 판정과 집계 (대시보드·Lot 조회)

| 규칙 | 내용 | 코드 |
|---|---|---|
| 집계 대상 LOT | `lot_end_time`이 조회 기간 안이고 `final_result`가 `PENDING`이 아닌 LOT | `routers/dashboard.py` |
| 생산량 | 위 대상 LOT 수 | 〃 |
| 합격률·불량률 | `final_result = OK` 수 ÷ 생산량, `NG` 수 ÷ 생산량 | 〃 |
| LOT 종합 판정 | `t_lot.final_result` 값을 그대로 사용 (계산 주체: 데이터를 기록하는 쪽, 13장) | - |
| 파트 종합 판정 | 해당 파트의 용접·비전 결과 중 **하나라도 NG면 NG, 둘 다 OK면 OK**, PENDING은 제외 | `common.part_verdicts` |
| 사이클 타임 | LOT의 첫 `LOAD_COMPLETE` 시각 → 마지막 비전 검사 종료 시각, 0초 이하 제외 | `routers/dashboard.py` |
| LOT 시작·종료 시각 | 시작 = 첫 `LOAD_COMPLETE`, 종료 = 비전 검사 중 가장 늦은 종료 (완료 전 NULL) | DB 설계 기준 |
| 불량 유형 분포 | `t_vision_inspection_detail.defect_type`에 **실제 기록된 값** 집계 | `common.defect_distribution` |

### 12-2. 알람 유형·코드·우선순위

알람은 모두 `t_alarm_event`에 저장되며, 화면은 아래 규칙으로 유형과 등급을 정합니다(`backend/alarms.py`, `backend/config.py`).

| 유형 | 판단 기준 | `alarm_code` 형식 | 우선순위 |
|---|---|---|---|
| 비전 알람 | 알람 설비(`machine_id`)의 `machine_type`이 `VISION` | `VIS_NG` | 2 경고 |
| 기준 이탈 | 코드가 `LIM_HI` / `LIM_LO` 형식 | `LIM_HI:<파라미터코드>:<파트번호>` 예) `LIM_HI:WELD_CURRENT:2` | 2 경고 |
| 설비 알람 | 위 두 가지가 아닌 경우 | `A-001` 또는 파트 연결 시 `A-001:2` | `A-004` 3 주의, 그 외 `A-` 1 긴급 |
| (규칙 외 코드) | - | - | 2 경고 (기본값) |

- 우선순위는 `ALARM_PRIORITY_RULES`의 **앞부분 일치, 위에서부터 먼저 맞는 규칙**으로 정합니다.
- 비전 알람은 같은 LOT·카메라의 NG 부위마다 화면에서 **1행씩 펼쳐** 보여 줍니다.
- 표준 조치 가이드는 `config.py`의 `ALARM_GUIDES`에서 유형·코드로 찾습니다. 사내 OCAP 문서가 정해지면 교체합니다.

> [!IMPORTANT]
> **Kepware가 알람을 기록할 때 이 코드 형식을 지켜야** 화면에 유형·파트·등급·조치 가이드가 올바르게 표시됩니다. 형식이 다르면 모두 "설비 알람, 경고"로 보입니다(13-3).

### 12-3. 알람 상태 전환

```text
[미해결] ──(확인 버튼)──► [미해결 · 확인됨] ──(조치 등록)──► [해결됨]
   │                                                   ▲
   └──────────────(조치 등록, 확인 자동 기록)──────────┘
```

| 상태 | 조건 (`backend/alarms.status_of`) |
|---|---|
| 해결됨 | `resolved_time`이 있음 |
| 조치중 | `resolved_time`이 없고 조치 기록(`t_alarm_action`)이 1건 이상 |
| 미해결 | 그 외 |

| 동작 | DB 변경 | 규칙 |
|---|---|---|
| 확인 | `ack_time`, `ack_user_id` | **최초 1회만 기록** (이미 있으면 유지) |
| 조치 등록 | `t_alarm_action` 1행 추가 + `resolved_time` = 현재 시각 | 구분(재작업·부품 교체·설비 점검·기타), 이름·소속·사번 필수 · 확인 정보가 없으면 함께 기록 |
| MTTR | 해결된 알람의 (`resolved_time` − `occurred_time`) 평균, 분 단위 | `routers/alarm.py` |

> [!WARNING]
> **`resolved_time`의 의미가 두 가지로 쓰일 수 있습니다.** DB 설계서는 "알람 해제 시각(설비)"으로, 화면은 "조치 완료 시각"으로 씁니다. Kepware가 설비 해제 시 `resolved_time`을 채우면 **조치 없이 '해결됨'** 으로 표시됩니다. 연동 사양 확정 시 결정이 필요합니다(21장 K-1).

### 12-4. 기준 이탈과 현장 복구

| 항목 | 규칙 |
|---|---|
| 기준값 | `m_recipe_target`의 `upper_limit`(UCL), `lower_limit`(LCL) · LOT의 `recipe_id` 기준 |
| 이탈 알람 | 센서 값이 기준을 벗어난 **첫 값**에서 알람 1건 (`LIM_HI` / `LIM_LO`) |
| 현장 복구 시각 | 기준 이탈: 이탈 후 **기준 안으로 돌아온 첫 센서 값** 시각 · 비전 NG: 같은 카메라·파트의 **다음 OK 검사** 시각 · 설비 알람: PLC 해제 신호 저장 위치가 없어 **판단 불가** |
| 현장 복구와 해결의 차이 | 현장 복구는 공정 값 기준 자동 판단, 해결은 사람의 조치 등록 |

### 12-5. 기준정보 규칙

| 규칙 | 이유 |
|---|---|
| 삭제하지 않고 `use_yn = N` | FK가 `NO ACTION`이라 참조 중이면 삭제 불가, 과거 기록 보존 |
| `use_yn = N`인 라인·용접부위는 목록·필터에서 빠짐 | 화면은 사용 중인 항목만 표시 |
| 화면의 "N번 파트" = `m_weld_point.sequence_no` | 순번을 바꾸면 화면 파트 번호와 알람 코드의 파트 번호가 바뀜 |
| 파라미터 코드 4종이 화면 표시 기준 | `WELD_CURRENT`, `WELD_PRESS`, `COOLANT_TEMP`, `WELD_TIME` · 바꾸면 `frontend/js/config.js`도 수정 |
| 레시피는 버전 관리 (`recipe_no` + `version` 고유) | 기준값 변경 시 새 버전 등록, 이전 버전은 사용 중지 |
| 용접부위의 검사 카메라 = `vision_machine_id` | 비전 결과를 파트와 연결하는 기준 |

### 12-6. 시간·조회 한도

| 항목 | 값 | 위치 |
|---|---|---|
| 모든 시각 | KST · DB 기본값 `DATEADD(HOUR, 9, SYSUTCDATETIME())` | DB, 백엔드 |
| 조회 기간 한도 | 용접 7일, 비전·Lot·알람 31일 | `config.py` |
| 비전 Live 판정 | 최근 2분 안에 검사 데이터 있으면 가동중 | `config.py` `VISION_LIVE_MIN` |
| 공정 연결 상태(사이드바) | 파트별 최근 용접 실적이 기준 시간 안에 있으면 연결됨 | `routers/master.py` |
| 로그인 | 5회 실패 10분 잠금, 12시간 유지, 자동 로그인 7일 | `config.py` |

---

## 18. 테스트와 검증

### 18-1. 현재 테스트 현황

| 항목 | 상태 |
|---|---|
| 자동 테스트 (단위·통합) | **없음** |
| 테스트용 DB | 없음 · 운영 DB(HW_Q_DB)에서 검증 |
| 테스트 데이터 생성기 | 제거됨 (시뮬레이터) |
| 검증 방식 | 아래 수동 체크리스트 |

> [!WARNING]
> 운영 DB에서 검증하므로 **테스트 데이터는 `TEST_` 접두어**로 만들고, 확인 후 DB 담당 승인을 받아 정리합니다(현재 남은 것: `TEST_0426`, `TEST_1st`, `TEST_WRITE_01`).

### 18-2. 수정 후 확인할 항목

| 수정한 영역 | 반드시 확인할 것 | 정상 기준 |
|---|---|---|
| 공통 (모든 수정) | 9-1 실행 확인, 화면 6개 열림, 브라우저 개발자 도구 콘솔 오류 없음 | 오류 없음 |
| `db*.py`, `.env` | `/health` | `"backend": "mssql"` |
| `security.py`, `auth.py` | 정상 로그인, 5회 실패 잠금, 로그아웃, 자동 로그인 | 15-5 기록값 일치 |
| `admin.py`, 기준정보 화면 | 각 탭 등록·수정 후 SSMS에서 값과 `updated_at` 확인 | 화면 ↔ DB 일치 |
| `alarm.py`, `alarms.py` | 확인·조치 등록 후 `ack_time`, `resolved_time`, `t_alarm_action` 확인, 상태 표시 | 12-3 규칙대로 |
| `dashboard.py`, `common.py` | 같은 기간 SQL 집계와 화면 수치 비교 | 12-1 규칙대로 |
| `weld.py` | 기준선이 `m_recipe_target`과 같은지 | UCL·LCL 일치 |
| `export.py`, `report.py` | PDF·Excel·CSV 각각 생성, 한글·행 수 | 화면 결과와 같은 행 |
| `config.js`, CSS | 주요 화면 표시 깨짐 없음 | - |

### 18-3. DB 적재 확인 SQL (연동 검증·장애 확인용)

```sql
-- 최근 LOT
SELECT TOP 10 lot_no, lot_start_time, lot_end_time, final_result, created_at FROM dbo.t_lot ORDER BY lot_id DESC;
-- 최근 센서 값
SELECT TOP 20 p.parameter_code, r.reading_value, r.reading_time, r.created_at
FROM dbo.t_sensor_reading r JOIN dbo.m_parameter p ON p.parameter_id = r.parameter_id ORDER BY r.reading_id DESC;
-- 최근 용접·비전·알람
SELECT TOP 20 * FROM dbo.t_weld_event ORDER BY weld_event_id DESC;
SELECT TOP 20 * FROM dbo.t_vision_inspection_detail ORDER BY detail_id DESC;
SELECT TOP 20 alarm_code, alarm_desc, occurred_time, resolved_time FROM dbo.t_alarm_event ORDER BY alarm_id DESC;
```

### 18-4. 센서 연결 후 연동 검증

| No | 항목 | 합격 기준 |
|---|---|---|
| 1 | LOT 생성 | 생산마다 `t_lot` 1행, 시각 KST |
| 2 | 로딩 이벤트 | `LOAD_COMPLETE` 기록 → 사이클 타임 표시 |
| 3 | 용접 실적 | LOT × 부위 수만큼 `t_weld_event` |
| 4 | 센서 값 | 파라미터 4종, 단위·범위 정상, 용접 그래프 표시 |
| 5 | 비전 | 카메라별 판정, NG면 `defect_type`, 이미지 표시 |
| 6 | 알람 | `alarm_code`가 12-2 형식, 화면 등급·파트·가이드 정상 |
| 7 | 화면 대조 | 같은 LOT을 Lot 조회 상세와 SQL로 비교해 값 일치 |
| 8 | 지연·누락 | 설비 시각과 `created_at` 차이가 수 초 이내, 연속 LOT 누락 없음 |

### 18-5. 아직 검증되지 않은 영역

| 영역 | 이유 |
|---|---|
| 센서 → DB → 화면 전 구간 | 센서 미연결 |
| 실제 설비 알람 기록과 표시 | Kepware 알람 기록 형식 미확인 |
| 여러 PC 동시 접속, 서버 운영 | 서버 미구성 |
| 대량 데이터에서의 조회 속도 | 실데이터 미적재 (인덱스 7개 기준) |
| 용접부위 등록 시 설비 연결 | 과거 기록에서 의심, 재테스트 필요 |
| 실제 비전 이미지 경로 표시 | 파일서버 경로 미확정 |
