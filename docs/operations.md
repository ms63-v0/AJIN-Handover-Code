# 운영·장애 대응 가이드

[문서 허브](../README.md) · [설치·실행](setup.md) · [사용자 설명서](user-guide.md) · [개발](development.md) · [운영·장애 대응](operations.md) · [변경·배포](release.md) · [인수인계](handover.md)

운영 구조, 설비 연동, DB와 계정 관리, 보안, 백업·장애 대응, 문제 해결 방법입니다.

> 인계 기준일 2026-11-09. 본문의 장 번호(예: `12-3`, `18장`)는 전체 인수인계 문서 기준입니다. 장별 위치는 [문서 허브의 장 번호 안내](../README.md#장-번호-안내)에 있습니다.

## 목차

- 4. 운영 구조와 서버 요구사항
- 13. 설비 연동 (Kepware)
- 14. DB 관리와 운영 데이터 변경
- 15. 앱 로그인 계정 관리
- 16. 보안과 비밀정보 관리
- 17. 백업·복구·장애 대응
- 20. 자주 발생하는 문제 (해결 방법)

---

## 4. 운영 구조와 서버 요구사항

### 4-1. 지금 운영 방식

| 항목 | 현재 상태 |
|---|---|
| 백엔드와 화면 실행 위치 | 한 대의 PC(로컬)에서 PowerShell 창 2개로 실행 |
| 사용 가능한 사람 | 그 PC에서 직접 접속하는 사람만 |
| 자동 시작 | 없음 (PC 재부팅 시 사람이 다시 실행) |
| DB | 사내 MSSQL 서버 (HW_Q_DB) |
| 설비 데이터 | PLC → Kepware → DB 경로 구현, 센서 미연결 |

> [!WARNING]
> 다른 PC에서 이 화면을 보려면 **지금 구조로는 불가능합니다.** 4-2의 서버와 4-3의 변경이 필요합니다.

### 4-2. 현장 적용 시 필요한 서버와 환경

| 구분 | 필요한 것 | 이유 |
|---|---|---|
| 애플리케이션 서버 | 상시 가동 Windows 서버 또는 PC 1대, 고정 IP | 백엔드와 화면을 24시간 실행 |
| 서버 프로그램 | Python 3.10 이상, ODBC Driver 18, 이 프로젝트 파일 | 실행 환경 |
| 자동 시작 | Windows 서비스 또는 작업 스케줄러 등록 | 재부팅·장애 후 자동 복구 |
| 네트워크 | 현장 PC와 같은 사내망, 서버 포트 허용 | 여러 PC 접속 |
| DB 서버 접근 | 애플리케이션 서버 → MSSQL 포트 허용 | DB 읽기·쓰기 |
| 보안 | HTTPS, 방화벽 범위 제한, 운영 주소 CORS 등록 | 비밀번호와 데이터 보호 |
| 시간 | KST 시간 동기화 | 기록 시각 정확성 |
| 백업 | DB 백업 정책 (17장) | 장애 시 복구 |

> [!NOTE]
> 서버 배치 방식(어느 PC를 서버로 쓸지, 누가 운영할지)은 **아직 결정되지 않았습니다.** 결정되면 이 장과 0장을 갱신하세요.

### 4-3. 서버로 옮길 때 바꿔야 하는 곳

화면은 접속한 주소의 8000 포트로 백엔드를 찾으므로 **화면 코드는 고치지 않아도 됩니다.**

| 위치 | 지금 값 | 바꿀 내용 | 바꾸지 않으면 |
|---|---|---|---|
| 백엔드 실행 명령 (9장) | `--host 127.0.0.1` | 서버 주소로 받도록 변경 (전산팀과 협의) | 다른 PC에서 백엔드 접속 불가 |
| `serve_ui.py` 마지막 줄 | `("127.0.0.1", 5173)` | 위와 같이 변경 | 다른 PC에서 화면 접속 불가 |
| `backend/main.py`의 `allow_origins` | localhost·127.0.0.1만 허용 | `http://<서버 주소>:5173` 추가 | 화면은 열리지만 로그인·데이터 요청이 막힘 |

> [!CAUTION]
> 주소를 열면 사내망의 누구나 접속할 수 있습니다. **방화벽 범위, HTTPS, 데모 계정 정리(16-4)를 먼저 끝낸 뒤** 바꾸세요. 서버 주소는 이 문서에 적지 않습니다.

---

## 13. 설비 연동 (Kepware)

### 13-1. 연동 개요

| 항목 | 내용 |
|---|---|
| 목적 | 설비에서 발생하는 LOT·용접·센서·비전·알람 데이터를 HW_Q_DB에 기록 |
| 방식 | Kepware가 PLC 태그를 읽어 DB 테이블에 직접 기록 |
| 현재 상태 | PLC ↔ Kepware 연결 완료, Kepware → DB 전송 구현 완료, **센서 ↔ PLC 미연결** |
| 인증 | Kepware 전용 DB 계정 (앱 계정과 분리 권장, 16-3) |
| 연동 명세 위치 | **없음 → 작성 필요** (13-4, 22장) |
| 담당 | 설비 담당 |

### 13-2. 기록 대상 테이블 (DB 설계 기준)

| 테이블 | 기록 시점 | 필수 값 | 화면 영향 |
|---|---|---|---|
| `t_lot` | 첫 `LOAD_COMPLETE` 시 생성, 비전 완료 시 `lot_end_time`·`final_result` 갱신 | `lot_no`, `line_id`, `product_id`, `recipe_id`, `lot_start_time` | 없으면 대시보드·Lot 조회 비어 있음 |
| `t_loading_event` | 로딩 로봇 동작마다 | `lot_id`, `machine_id`, `station_id`, `event_type`, `event_time` | 사이클 타임 계산 불가 |
| `t_weld_event` | 부위별 PLC 용접 완료 신호 | `lot_id`, `weld_point_id`, 시작·종료 시각, `weld_result` | 파트 판정·공정 연결 상태 |
| `t_sensor_reading` | 센서 측정 시 (**센서 연결 후**) | `machine_id`, `parameter_id`, `reading_value`, `reading_time` | 용접 그래프, 기준 이탈 |
| `t_vision_inspection` / `_detail` / `t_vision_image` | 카메라 검사·부위 판정·이미지 저장 | `lot_id`, `machine_id`, `overall_result` / `weld_point_id`, `result` / `image_path` | 비전 화면, 파트 판정 |
| `t_alarm_event` | 알람 발생 | `machine_id`, `alarm_code`(12-2 형식), `alarm_desc`, `occurred_time` | 알람 화면·팝업 |
| `t_tip_maintenance` | 팁 교환·드레싱 | `weld_machine_id`, `maintenance_type`, `occurred_at` | 현재 화면 미사용 · 기록 여부 확인 |

> [!IMPORTANT]
> 기록하는 ID(`machine_id`, `weld_point_id`, `parameter_id`, `recipe_id`)는 **`m_` 기준정보에 등록된 값**과 같아야 합니다. 기준정보에 없는 ID는 FK 제약으로 저장이 실패합니다.

### 13-3. 오류·지연·중복 시 동작

| 상황 | 화면에 나타나는 현상 | 확인 방법 | 대응 |
|---|---|---|---|
| Kepware 중단·DB 기록 실패 | 값이 갱신되지 않음, 비전 "연동 안됨", 공정 연결 상태 끊김 | 18-3 SQL로 최근 `created_at` 확인 | 설비 담당에 연락 |
| 기록 지연 | 실시간 피드·그래프가 늦게 바뀜 | 설비 시각과 `created_at` 비교 | 수집 주기 점검 |
| 같은 이벤트 중복 기록 | 건수·알람이 2배로 표시 | 같은 LOT·부위의 중복 행 조회 | 중복 방지 규칙 정의 (13-4) |
| 알람 코드 형식 불일치 | 모두 "설비 알람·경고"로 표시, 파트·가이드 누락 | `alarm_code` 값 확인 | 12-2 형식으로 수정 |
| 앱 쪽 DB 응답 지연 | 화면 로딩이 멈춤 (쿼리 시간 제한 없음) | 창 1 로그 | 21장 K-6 |

### 13-4. 연동 명세에 반드시 남길 것 (작성 필요)

- 태그 ↔ 테이블·칼럼 매핑표, 수집 주기와 기록 조건(변경 시 / 주기)
- LOT 번호 생성 규칙, `final_result` 판정 주체와 규칙
- 알람 발생·해제 조건, 중복 기록 방지, `resolved_time` 사용 여부(12-3 경고)
- 통신 끊김 시 누락 데이터 처리(재전송 여부)
- Kepware 설정 파일 위치와 백업, Kepware DB 계정 관리자

---

## 14. DB 관리와 운영 데이터 변경

### 14-1. 스키마 자료 위치

| 자료 | 위치 | 관리 |
|---|---|---|
| 테이블 생성 스크립트 | [`mssql_query.sql`](../mssql_query.sql) (저장소 루트) | DB 담당 |
| DB 설계서 `Weld_Vision_DB설계서_1026_MSSQL_1.xlsx` | `<보관 위치 기입>` | DB 담당 |
| 테이블·칼럼·FK·인덱스·코드값 정리 | 상세 설명서 5장 | 프로젝트 담당 |
| DB 안의 칼럼 설명 | SSMS → 테이블 → 속성 → 설명(MS_Description) | 스크립트와 함께 갱신 |

### 14-2. 스키마 변경 절차

| 순서 | 작업 | 주의 |
|---|---|---|
| 1 | 변경 내용과 영향 테이블·화면·Kepware 기록 확인 | 3-3, 10장, 13-2 표 기준 |
| 2 | DB 담당 승인 | - |
| 3 | **DB 전체 백업** | 되돌리기 수단 |
| 4 | 변경 스크립트 적용 (칼럼 추가 → 코드 반영 → 기존 칼럼 정리 순) | 기존 칼럼 삭제·이름 변경은 앱과 Kepware를 동시에 깨뜨림 |
| 5 | `mssql_query.sql`, MS_Description, 상세 설명서 갱신 | 스크립트는 멱등. **기본값 변경은 재실행해도 기존 DB에 반영되지 않음** → 별도 ALTER 필요 |
| 6 | 18-2 검증 후 운영 반영 (19장) | - |

> [!WARNING]
> **되돌리기:** 칼럼 추가는 대체로 되돌릴 수 있지만, 삭제·타입 변경·데이터 일괄 수정은 **백업 복원 외에는 되돌릴 수 없습니다.** 복원하면 백업 이후 데이터가 사라집니다.

### 14-3. 운영 데이터를 바꾸는 기능

| 기능 | 실행 조건 | 영향 범위 | 되돌리기 |
|---|---|---|---|
| 기준정보 등록·수정 (화면) | ADMIN | 해당 기준을 쓰는 모든 화면, Kepware 기록 ID | 다시 수정 (`updated_at`으로 시점 확인) · 이전 값은 기록되지 않으므로 **수정 전 값 메모** |
| 레시피 기준값 변경 | ADMIN | 기준 이탈 판정, UCL·LCL | 이전 버전 사용 재개 |
| 알람 확인 | 로그인 사용자 | 확인 시각·확인자 | 불가 (최초 1회 기록) |
| 알람 조치 등록 | 로그인 사용자 (역할 검사 없음) | 알람이 해결됨으로 바뀜 | 화면에서 불가 · SQL로 `resolved_time` 수정은 DB 담당 승인 |
| 계정 발급·변경·중지 (SQL) | DB 접속 계정 | 해당 사용자 로그인 | 사용 중지는 `use_yn` 재변경 |
| 실적 초기화 `/api/auth/reset-db` | ADMIN · **실 DB에서는 차단됨** | - | - |
| 테스트 데이터 정리 (SQL) | DB 담당 승인 | 참조 실적 | 백업 복원 |

---

## 15. 앱 로그인 계정 관리

> **화면 로그인 계정**(`m_user`)과 **DB 접속 계정**(`.env`의 `MSSQL_USER`)은 다른 계정입니다.

| 구분 | 용도 | 저장 위치 | 관리 |
|---|---|---|---|
| DB 접속 계정 | 프로그램 → DB | SQL Server 로그인 | DB 담당 |
| Kepware DB 계정 | Kepware → DB | SQL Server 로그인 | DB·설비 담당 |
| 앱 로그인 계정 | 사람 → 화면 | `m_user` | 시스템 관리자 |

### 15-1. 역할(권한)

| 기능 | ADMIN | MANAGER | OPERATOR |
|---|---|---|---|
| 조회·내보내기 | 가능 | 가능 | 가능 |
| 알람 확인 | 가능 | 가능 | 가능 |
| 알람 조치 등록 | 가능 | 가능 | 가능 (역할 검사 없음, 21장 K-4) |
| 기준정보 관리 | 가능 | 불가 | 불가 |

조회 전용 역할(`VIEWER`)은 없습니다.

### 15-2. 발급 절차

1. **요청**: 이름, 부서, 로그인 ID, 역할 → 시스템 관리자
2. **승인**: 관리자 승인 (`ADMIN`은 별도 승인)
3. **해시 생성**: 15-3 (비밀번호는 본인이 직접 입력 원칙)
4. **등록**: 15-4
5. **로그인 확인** 후 **발급 대장**에 ID, 이름, 역할, 발급일 기록 (비밀번호 제외)

### 15-3. 해시 만들기 (PowerShell, 저장소 폴더)

```powershell
cd "<저장소 폴더의 실제 경로>"
.\.venv\Scripts\Activate.ps1

$sec   = Read-Host "앱 로그인 비밀번호 (8자 이상)" -AsSecureString
$plain = (New-Object System.Net.NetworkCredential("", $sec)).Password
$hash  = $plain | py -c "import sys; from backend.security import hash_password; print(hash_password(sys.stdin.readline().strip()))"
Remove-Variable plain, sec

$hash
```

- 출력된 `scrypt$...` 한 줄을 앞뒤 공백 없이 복사하고, 끝나면 `Remove-Variable hash`
- 비밀번호 규칙(8자 이상, 3종 이상 조합)은 프로그램이 검사하지 않으므로 **운영 규칙으로 지킵니다.**

### 15-4. 계정 등록

```sql
USE [HW_Q_DB];
GO
IF NOT EXISTS (SELECT 1 FROM dbo.m_user WHERE login_id = N'<로그인 ID>')
BEGIN
    INSERT INTO dbo.m_user
        (login_id, password_hash, user_name, role_code, department, force_change_yn, use_yn)
    VALUES
        (N'<로그인 ID>', N'<해시>', N'<이름>', N'<ADMIN|MANAGER|OPERATOR>', N'<부서>', N'Y', N'Y');
END
GO
SELECT login_id, role_code, use_yn FROM dbo.m_user ORDER BY user_id;
```

- `force_change_yn = Y`여도 **첫 로그인 변경을 강제하지 않습니다**(21장 K-5).
- 한글 입력 상태에서 작성하면 전각 기호로 `156` 구문 오류가 납니다. 영문 입력 상태로 작성하세요.

### 15-5. 계정 운영 SQL

| 작업 | SQL |
|---|---|
| 비밀번호 변경 | `UPDATE dbo.m_user SET password_hash = N'<새 해시>', password_changed_at = DATEADD(HOUR, 9, SYSUTCDATETIME()), updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME()) WHERE login_id = N'<ID>';` |
| 잠금 즉시 해제 (10분 후 자동 해제) | `UPDATE dbo.m_user SET failed_login_count = 0, locked_until = NULL WHERE login_id = N'<ID>';` |
| 퇴직·전보 (삭제 금지) | `UPDATE dbo.m_user SET use_yn = 'N', updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME()) WHERE login_id = N'<ID>';` |
| 로그인 기록 확인 | `SELECT TOP 50 attempted_login_id, login_result, login_time, ip_address FROM dbo.t_user_login_history ORDER BY login_time DESC;` |

| `login_result` | 뜻 | 조치 |
|---|---|---|
| `SUCCESS` | 성공 | - |
| `FAIL_NO_USER` | ID 없음 또는 사용 중지 | ID·사용 여부 확인 |
| `FAIL_PW` | 비밀번호 불일치 | 재확인, 필요 시 변경 |
| `FAIL_LOCKED` | 5회 실패로 잠김 | 10분 대기 또는 잠금 해제 |

---

## 16. 보안과 비밀정보 관리

### 16-1. 로그인 보안

| 항목 | 값 |
|---|---|
| 비밀번호 저장 | scrypt 해시 (`backend/security.py`) |
| 잠금 | 5회 연속 실패 → 10분 |
| 세션 | 12시간, 자동 로그인 7일, 쿠키 `qms_session` (HttpOnly, SameSite=Lax) |
| 서명 키 | `data/.secret` (자동 생성) |
| 통신 | HTTP (암호화 없음) → 서버 운영 시 HTTPS 필요 |

### 16-2. 비밀정보 목록

| 비밀정보 | 저장 위치 | 관리 주체 | 저장소 포함 |
|---|---|---|---|
| 앱 DB 접속 계정·비밀번호 | 실행 PC의 `.env` | DB 담당 | 제외 |
| Kepware DB 계정·비밀번호 | Kepware 설정 | DB·설비 담당 | 제외 |
| DB 서버 주소·포트 | `.env` | 전산팀 | 제외 |
| 로그인 서명 키 | `data/.secret` | 프로젝트 담당 | 제외 |
| 앱 계정 비밀번호 | 본인만 (DB에는 해시) | 사용자 본인 | 제외 |

> [!CAUTION]
> 사내 비밀관리 시스템이 없으므로 **비밀정보는 담당자가 대면 또는 승인된 사내 경로로만 전달**합니다. 이 문서, 저장소, 메신저, 메일, 사진에 실제 값을 남기지 마세요.

### 16-3. 신청·회수·교체 절차

| 상황 | 절차 | 담당 |
|---|---|---|
| 신규 담당자 | DB 계정 값 전달 또는 신규 발급 → `.env` 작성 · 저장소 Collaborator 초대 · 앱 ADMIN 발급 | DB 담당, 프로젝트 담당 |
| 담당자 변경·퇴직 | 저장소 권한 제거 · 앱 계정 `use_yn = N` · **DB 비밀번호 교체** 후 `.env` 갱신 | 프로젝트 담당, DB 담당 |
| DB 비밀번호 유출 의심 | DB 비밀번호 교체 → 모든 실행 PC의 `.env` 갱신 → 백엔드 재시작 | DB 담당 |
| `data/.secret` 유출 의심 | 파일 삭제 → 백엔드 재시작 (새 키 생성, 전원 재로그인) | 프로젝트 담당 |
| 저장소에 `.env`가 올라간 경우 | 즉시 DB 비밀번호 교체 (파일 삭제만으로는 이력에 남음) | DB 담당 |

### 16-4. 데모 계정 정리 (인수 직후 1회)

```sql
SELECT login_id, role_code, use_yn, last_login_at FROM dbo.m_user ORDER BY user_id;
```

`admin`, `operator1` 같은 데모 계정이 `use_yn = Y`이면 즉시 사용 중지하거나 비밀번호를 바꾸세요. 데모 비밀번호는 과거 문서에 있었으므로 알려진 값으로 간주합니다.

### 16-5. 저장소 공개 범위

GitHub 저장소가 공개(Public)라면 비공개 전환 또는 접근 권한 정리를 검토합니다. 저장소와 문서에는 계정, 비밀번호, 서버 IP, 해시, 개인 연락처를 적지 않습니다.

---

## 17. 백업·복구·장애 대응

### 17-1. 백업과 복구

| 항목 | 내용 |
|---|---|
| 담당 | **DB 담당** |
| 대상 | `HW_Q_DB` |
| 현재 설정 | 전체·로그 백업 등록 확인 · **주기·보관 기간·복원 테스트 여부는 DB 담당 확인 필요** |
| 복구 | DB 담당이 백업 파일로 복원 · 복원 시점 이후 데이터 손실 |
| 프로젝트 파일 | 저장소가 기준본 · `.env`, `data/.secret`은 실행 PC에만 있음 (재발급·자동 생성으로 복구) |
| Kepware 설정 | `<백업 위치 기입>` (설비 담당) |

> [!NOTE]
> 설비 연동으로 데이터가 빠르게 늘어납니다. 센서 연결 전에 **백업 주기, 보관 기간, 디스크 용량**을 DB 담당과 다시 확인하세요.

### 17-2. 모니터링 현황

| 항목 | 현재 | 대안 |
|---|---|---|
| 서비스 상태 감시 | 없음 | `/health` 주기 확인 (서버 운영 시 모니터링 도구 등록) |
| 설비 데이터 유입 감시 | 화면의 비전 "연동 안됨", 사이드바 공정 연결 상태 | 18-3 SQL로 최근 `created_at` 확인 |
| 오류 로그 | 백엔드 창(창 1) 출력만, 파일 저장 없음 | 서버 운영 시 로그 파일 저장 |
| 알림 | 없음 | 서버 운영 시 결정 |

### 17-3. 장애 대응 순서

| 순서 | 확인 | 판단 |
|---|---|---|
| 1 | 화면 접속 (`:5173`) | 안 되면 창 2 실행 여부 |
| 2 | `/health` (`:8000`) | 안 되면 창 1 실행 여부·오류 메시지 |
| 3 | `/health`의 `backend` 값 | `sqlite`면 `.env` 문제 |
| 4 | 로그인 | 401이면 15-5 로그인 기록 |
| 5 | DB에 최근 데이터 있는지 (18-3) | 없으면 Kepware·설비 쪽 → 설비 담당 |
| 6 | 그 외 | 창 1의 오류 전문과 발생 시각을 기록해 프로젝트 담당에게 전달 (비밀번호·IP는 가림) |

---

## 20. 자주 발생하는 문제 (해결 방법)

| 증상 | 원인 | 해결 |
|---|---|---|
| `py`를 찾을 수 없음 | Python 미설치·PATH 미등록 | 재설치 시 "Add python.exe to PATH" |
| `(.venv)`가 안 보임 | 가상환경 미실행 | `.\.venv\Scripts\Activate.ps1` |
| 스크립트 실행 비활성화 | 실행 정책 | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `.env에 다음 값이 필요합니다` | 필수 항목 누락 | 8-2 |
| `/health`에 `sqlite` | `DB_BACKEND` 없음, `.env.txt` | 8장 확인 후 재실행 |
| `Data source name not found` | ODBC Driver 18 미설치 | 설치 후 재시작 |
| `No module named 'pyodbc'` | 가상환경 밖 설치 | `(.venv)`에서 재설치 |
| `Login failed for user` | DB 계정·비밀번호 오류 | `.env` 확인, DB 담당 |
| `Cannot open database` | DB 이름 오류 | `HW_Q_DB` |
| 서버 찾을 수 없음·시간 초과 | 네트워크·VPN·방화벽 | 전산팀 |
| `Invalid object name 'm_line'` | 테이블 없음 | DB 담당에 스크립트 적용 요청 |
| 한글 `???` | 인코딩 | `MSSQL_CHAR_ENCODING=cp949` |
| 로그인 401 | ID·비밀번호, 사용 중지, 잠금 | 15-5 |
| 로그인 직후 로그아웃 | `data/.secret` 변경 | 재로그인 |
| 값이 비어 있음 | 기간에 데이터 없음, 설비 미연결 | 18-3 SQL로 DB 확인 |
| 알람이 모두 "설비·경고"로 보임 | `alarm_code` 형식 불일치 | 12-2, 설비 담당 |
| 조치 없이 "해결됨" | 설비 쪽에서 `resolved_time` 기록 | 12-3 경고, 21장 K-1 |
| 다른 PC에서 접속 불가 | 127.0.0.1 전용 | 4-3 |
| 다른 주소에서 로그인·데이터 실패 | CORS | `allow_origins` |
| 500 오류 | 백엔드 내부 오류 | 창 1 오류 전문·시각 전달 |
| 포트 사용 중 | 이전 실행 잔존 | 기존 창 종료 후 재실행 |
| 메뉴가 예전 그대로 | 캐시·이전 계정 | `Ctrl+F5`, 재로그인 |
