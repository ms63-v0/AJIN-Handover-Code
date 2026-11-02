/* ============================================================================
   문서명    : AJIN QMS 용접/비전 품질 DB 스키마 생성 스크립트
   대상 DB   : Microsoft SQL Server 2016 이상 (검증: SQL Server 2022)
   기준 문서 : Weld_Vision_DB설계서_1026_MSSQL_1.xlsx
   버전      : v1.1 (updated_at 4개 추가)
   작성      : [진민수 / FA]
   검토      : [검토자 이름 / 소속]
   구성      : 테이블 23 · 컬럼 200 · PK 23 · UQ 14 · CHECK 2 · DEFAULT 41 · FK 36 · INDEX 7

   [섹션 구성]
     1. 테이블 생성   (기준정보 m_*, 실적 t_*)
     2. 외래키(FK)    (테이블 생성 후 일괄 추가)
     3. 인덱스
     4. 설명(MS_Description) 등록

   [실행 방법]
     SSMS 에서 대상 DB 를 선택한 뒤 전체 실행(F5).
     여러 번 실행해도 안전하다(멱등). 이미 있는 객체는 건너뛴다.

   [시각 기준 - 중요]
     등록 시각(created_at)은 한국 시간(KST, UTC+9)으로 저장한다.
     기본값: DATEADD(HOUR, 9, SYSUTCDATETIME())  ※ 서버 시간대 설정과 무관
     이 기본값은 본 스크립트로 '새로 생성'하는 테이블에만 적용된다.
     이미 만들어진 DB 는 본 스크립트를 다시 실행해도 기본값이 바뀌지 않으므로
     기본값 변경 스크립트를 별도로 적용해야 한다.

   [운영 주의]
     - 운영 DB 에 적용하기 전에 반드시 백업한다.
     - 본 스크립트는 계정을 생성하지 않는다. 초기 계정(데모용 포함)은 별도 시드 절차로 등록하며, 운영 적용 전 데모 계정은 삭제하거나 비밀번호를 변경한다.
     - 타입 변환: INTEGER→INT, DATETIME→DATETIME2(3), TEXT→VARCHAR(10)+CHECK
   ============================================================================ */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   1. 테이블 생성
      - m_* : 기준정보 (변경 빈도 낮음, 관리자가 등록·수정)
      - t_* : 실적/이력 (설비·시스템이 적재, 원칙적으로 수정하지 않음)
   --------------------------------------------------------------------------- */
-- m_line : 라인 기준정보, 생산 라인 마스터(예:HW01). 신규 라인은 행 추가로 등록
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_line' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_line] (
        [line_id] INT IDENTITY(1,1) NOT NULL,
        [line_code] VARCHAR(20) NOT NULL,
        [line_name] VARCHAR(100) NOT NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_line_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_line_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_line] PRIMARY KEY CLUSTERED ([line_id]),
        CONSTRAINT [uq_m_line_line_code] UNIQUE NONCLUSTERED ([line_code])
    );
END
GO

-- m_station : 공정 구역 기준정보. 라인 내 공정 순서와 공정 유형(LOAD, WELD, VISION, UNLOAD, COMPOSITE) 관리
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_station' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_station] (
        [station_id] INT IDENTITY(1,1) NOT NULL,
        [line_id] INT NOT NULL,
        [station_code] VARCHAR(20) NOT NULL,
        [station_name] VARCHAR(100) NOT NULL,
        [station_type] VARCHAR(20) NOT NULL,
        [sequence_no] INT NOT NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_station_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_station_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_station] PRIMARY KEY CLUSTERED ([station_id]),
        CONSTRAINT [uq_m_station_station_code] UNIQUE NONCLUSTERED ([station_code])
    );
END
GO

-- m_machine : 설비 공통 기준정보, 로봇, PLC, 비전, 용접기 등 모든 설비를 한 테이블에서 관리
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_machine' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_machine] (
        [machine_id] INT IDENTITY(1,1) NOT NULL,
        [station_id] INT NOT NULL,
        [machine_code] VARCHAR(30) NOT NULL,
        [machine_name] VARCHAR(100) NOT NULL,
        [machine_type] VARCHAR(20) NOT NULL,
        [model_name] VARCHAR(100) NOT NULL,
        [manufacturer] VARCHAR(100) NOT NULL,
        [install_date] DATE NOT NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_machine_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_machine_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_machine] PRIMARY KEY CLUSTERED ([machine_id]),
        CONSTRAINT [uq_m_machine_machine_code] UNIQUE NONCLUSTERED ([machine_code])
    );
END
GO

-- m_weld_point : 용접부위(타점) 기준정보, 부위별 검사 카메라(vision_machine_id)를 지정
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_weld_point' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_weld_point] (
        [weld_point_id] INT IDENTITY(1,1) NOT NULL,
        [weld_machine_id] INT NOT NULL,
        [weld_point_code] VARCHAR(30) NOT NULL,
        [weld_type] VARCHAR(10) NOT NULL,
        [sequence_no] INT NOT NULL,
        [position_desc] VARCHAR(200) NULL,
        [vision_machine_id] INT NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_weld_point_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_weld_point_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_weld_point] PRIMARY KEY CLUSTERED ([weld_point_id]),
        CONSTRAINT [uq_m_weld_point_weld_point_code_weld_machine_id_sequence_no] UNIQUE NONCLUSTERED ([weld_point_code], [weld_machine_id], [sequence_no])
    );
END
GO

-- m_parameter : 센서 항목 기준정보, 신규 항목은 행 추가만으로 확장 가능(data_type: NUMERIC/INT/BOOLEAN/STRING)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_parameter' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_parameter] (
        [parameter_id] INT IDENTITY(1,1) NOT NULL,
        [parameter_code] VARCHAR(30) NOT NULL,
        [parameter_name] VARCHAR(100) NOT NULL,
        [unit] VARCHAR(20) NOT NULL,
        [data_type] VARCHAR(10) NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_parameter_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_parameter_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_parameter] PRIMARY KEY CLUSTERED ([parameter_id]),
        CONSTRAINT [uq_m_parameter_parameter_code] UNIQUE NONCLUSTERED ([parameter_code]),
        CONSTRAINT [ck_m_parameter_data_type] CHECK ([data_type] IN ('NUMERIC', 'INT', 'BOOLEAN', 'STRING'))
    );
END
GO

-- m_machine_spec : 설비별 정격값 이력. 적용 기간(effective_from/to)으로 시점별 기준값을 추적
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_machine_spec' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_machine_spec] (
        [spec_id] INT IDENTITY(1,1) NOT NULL,
        [machine_id] INT NOT NULL,
        [parameter_id] INT NOT NULL,
        [rated_value] DECIMAL(15,4) NOT NULL,
        [rated_min] DECIMAL(15,4) NOT NULL,
        [rated_max] DECIMAL(15,4) NOT NULL,
        [effective_from] DATE NULL,
        [effective_to] DATE NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_machine_spec_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_m_machine_spec] PRIMARY KEY CLUSTERED ([spec_id]),
        CONSTRAINT [uq_m_machine_spec_machine_id_parameter_id_effective_from] UNIQUE NONCLUSTERED ([machine_id], [parameter_id], [effective_from])
    );
END
GO

-- m_product : 제품 기준정보. 차종 코드(car_type_code)는 PLC 차종 데이터와 매핑
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_product' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_product] (
        [product_id] INT IDENTITY(1,1) NOT NULL,
        [product_code] VARCHAR(50) NOT NULL,
        [product_name] VARCHAR(200) NOT NULL,
        [car_type_code] VARCHAR(30) NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_product_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_product_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_product] PRIMARY KEY CLUSTERED ([product_id]),
        CONSTRAINT [uq_m_product_product_code] UNIQUE NONCLUSTERED ([product_code])
    );
END
GO

-- m_recipe : 레시피 기준정보. 제품별 버전 관리, 적용 기간 내 최신 버전을 사용
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_recipe' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_recipe] (
        [recipe_id] INT IDENTITY(1,1) NOT NULL,
        [recipe_no] VARCHAR(50) NOT NULL,
        [product_id] INT NOT NULL,
        [version] INT NOT NULL CONSTRAINT [df_m_recipe_version] DEFAULT ((1)),
        [effective_from] DATETIME2(3) NOT NULL,
        [effective_to] DATETIME2(3) NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_recipe_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_recipe_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_recipe] PRIMARY KEY CLUSTERED ([recipe_id]),
        CONSTRAINT [uq_m_recipe_recipe_no_version] UNIQUE NONCLUSTERED ([recipe_no], [version])
    );
END
GO

-- m_recipe_target : 레시피별 용접부위, 파라미터 목표값과 상하한값
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_recipe_target' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_recipe_target] (
        [recipe_target_id] INT IDENTITY(1,1) NOT NULL,
        [recipe_id] INT NOT NULL,
        [weld_point_id] INT NOT NULL,
        [parameter_id] INT NOT NULL,
        [target_value] DECIMAL(15,4) NOT NULL,
        [upper_limit] DECIMAL(15,4) NOT NULL,
        [lower_limit] DECIMAL(15,4) NOT NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_recipe_target_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_recipe_target] PRIMARY KEY CLUSTERED ([recipe_target_id]),
        CONSTRAINT [uq_m_recipe_target_recipe_id_weld_point_id_parameter_id] UNIQUE NONCLUSTERED ([recipe_id], [weld_point_id], [parameter_id])
    );
END
GO

-- m_weld_machine : 용접기 전용 스펙. 팁 교환 기준 타점수, 드레싱 기준 타점수 등 (용접기만 행 존재)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_weld_machine' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_weld_machine] (
        [weld_machine_id] INT IDENTITY(1,1) NOT NULL,
        [machine_id] INT NOT NULL,
        [electrode_type] VARCHAR(50) NOT NULL,
        [tip_type] VARCHAR(50) NOT NULL,
        [tip_change_cycle] INT NOT NULL,
        [tip_dress_cycle] INT NOT NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_weld_machine_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_weld_machine] PRIMARY KEY CLUSTERED ([weld_machine_id]),
        CONSTRAINT [uq_m_weld_machine_machine_id] UNIQUE NONCLUSTERED ([machine_id])
    );
END
GO

-- m_weld_tip_status : 용접기 팁 현재 상태 (누적 타점수, 교환/드레싱 누적횟수). 저장 방식 설계 결정 필요
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_weld_tip_status' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_weld_tip_status] (
        [tip_status_id] INT IDENTITY(1,1) NOT NULL,
        [weld_machine_id] INT NOT NULL,
        [current_tip_count] INT NOT NULL CONSTRAINT [df_m_weld_tip_status_current_tip_count] DEFAULT ((0)),
        [current_dress_count] INT NOT NULL CONSTRAINT [df_m_weld_tip_status_current_dress_count] DEFAULT ((0)),
        [total_tip_change_cnt] INT NOT NULL CONSTRAINT [df_m_weld_tip_status_total_tip_change_cnt] DEFAULT ((0)),
        [total_dress_cnt] INT NOT NULL CONSTRAINT [df_m_weld_tip_status_total_dress_cnt] DEFAULT ((0)),
        [last_tip_changed_at] DATETIME2(3) NULL,
        [last_dressed_at] DATETIME2(3) NULL,
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_weld_tip_status] PRIMARY KEY CLUSTERED ([tip_status_id]),
        CONSTRAINT [uq_m_weld_tip_status_weld_machine_id] UNIQUE NONCLUSTERED ([weld_machine_id])
    );
END
GO

-- m_user : 사용자 계정. 비밀번호는 해시만 저장하며 평문 저장 금지. 잠금/실패 횟수 포함
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'm_user' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[m_user] (
        [user_id] INT IDENTITY(1,1) NOT NULL,
        [login_id] VARCHAR(50) NOT NULL,
        [password_hash] VARCHAR(255) NOT NULL,
        [user_name] VARCHAR(100) NOT NULL,
        [role_code] VARCHAR(20) NOT NULL,
        [department] VARCHAR(100) NULL,
        [email] VARCHAR(100) NULL,
        [phone] VARCHAR(20) NULL,
        [password_changed_at] DATETIME2(3) NULL,
        [force_change_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_user_force_change_yn] DEFAULT ('N'),
        [failed_login_count] INT NOT NULL CONSTRAINT [df_m_user_failed_login_count] DEFAULT ((0)),
        [locked_until] DATETIME2(3) NULL,
        [last_login_at] DATETIME2(3) NULL,
        [use_yn] CHAR(1) NOT NULL CONSTRAINT [df_m_user_use_yn] DEFAULT ('Y'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_m_user_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_m_user] PRIMARY KEY CLUSTERED ([user_id]),
        CONSTRAINT [uq_m_user_login_id] UNIQUE NONCLUSTERED ([login_id])
    );
END
GO

-- t_lot : Lot(제품 1개) 생산 실적. 모든 실적 테이블의 기준 키. 최종 판정(final_result) 포함
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_lot' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_lot] (
        [lot_id] INT IDENTITY(1,1) NOT NULL,
        [lot_no] VARCHAR(50) NOT NULL,
        [line_id] INT NOT NULL,
        [product_id] INT NOT NULL,
        [recipe_id] INT NOT NULL,
        [car_type_snapshot] VARCHAR(30) NULL,
        [lot_start_time] DATETIME2(3) NOT NULL,
        [lot_end_time] DATETIME2(3) NULL,
        [final_result] VARCHAR(10) NOT NULL CONSTRAINT [df_t_lot_final_result] DEFAULT ('PENDING'),
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_lot_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        [updated_at] DATETIME2(3) NULL,
        CONSTRAINT [pk_t_lot] PRIMARY KEY CLUSTERED ([lot_id]),
        CONSTRAINT [uq_t_lot_lot_no] UNIQUE NONCLUSTERED ([lot_no])
    );
END
GO

-- t_weld_event : 용접부위별 용접 실적(시작/종료 시각, 결과). PLC 완료 신호 기준
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_weld_event' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_weld_event] (
        [weld_event_id] INT IDENTITY(1,1) NOT NULL,
        [lot_id] INT NOT NULL,
        [weld_point_id] INT NOT NULL,
        [weld_start_time] DATETIME2(3) NOT NULL,
        [weld_end_time] DATETIME2(3) NOT NULL,
        [weld_result] VARCHAR(10) NOT NULL CONSTRAINT [df_t_weld_event_weld_result] DEFAULT ('PENDING'),
        [source_device] VARCHAR(30) NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_weld_event_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_weld_event] PRIMARY KEY CLUSTERED ([weld_event_id])
    );
END
GO

-- t_sensor_reading : 센서값 이벤트 로그.
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_sensor_reading' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_sensor_reading] (
        [reading_id] BIGINT IDENTITY(1,1) NOT NULL,
        [lot_id] INT NULL,
        [machine_id] INT NOT NULL,
        [weld_point_id] INT NULL,
        [parameter_id] INT NOT NULL,
        [reading_value] DECIMAL(15,4) NULL,
        [reading_time] DATETIME2(3) NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_sensor_reading_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_sensor_reading] PRIMARY KEY CLUSTERED ([reading_id])
    );
END
GO

-- t_tip_maintenance : 용접기 팁 교환 및 드레싱 이력. 작업 유형, 발생 시각, 근거 PLC 디바이스
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_tip_maintenance' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_tip_maintenance] (
        [maintenance_id] INT IDENTITY(1,1) NOT NULL,
        [weld_machine_id] INT NOT NULL,
        [maintenance_type] VARCHAR(20) NOT NULL,
        [occurred_at] DATETIME2(3) NOT NULL,
        [tip_count_at_change] INT NULL,
        [worker_memo] VARCHAR(200) NULL,
        [source_device] VARCHAR(30) NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_tip_maintenance_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_tip_maintenance] PRIMARY KEY CLUSTERED ([maintenance_id])
    );
END
GO

-- t_loading_event : 로딩 로봇 동작 이력(LOAD_COMPLETE, UNLOAD_COMPLETE 등). LOT 시작 시각의 근거
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_loading_event' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_loading_event] (
        [loading_event_id] INT IDENTITY(1,1) NOT NULL,
        [lot_id] INT NOT NULL,
        [machine_id] INT NOT NULL,
        [station_id] INT NOT NULL,
        [event_type] VARCHAR(30) NOT NULL,
        [event_time] DATETIME2(3) NOT NULL,
        [source_device] VARCHAR(30) NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_loading_event_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_loading_event] PRIMARY KEY CLUSTERED ([loading_event_id])
    );
END
GO

-- t_vision_inspection : 비전검사 실적 (LOT·카메라 단위). 검사 시작/종료 시각과 종합 판정
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_vision_inspection' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_vision_inspection] (
        [vision_inspection_id] INT IDENTITY(1,1) NOT NULL,
        [lot_id] INT NOT NULL,
        [machine_id] INT NOT NULL,
        [inspection_start_time] DATETIME2(3) NULL,
        [inspection_end_time] DATETIME2(3) NULL,
        [overall_result] VARCHAR(10) NOT NULL CONSTRAINT [df_t_vision_inspection_overall_result] DEFAULT ('PENDING'),
        [start_source_device] VARCHAR(30) NULL,
        [result_source_device] VARCHAR(30) NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_vision_inspection_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_vision_inspection] PRIMARY KEY CLUSTERED ([vision_inspection_id])
    );
END
GO

-- t_vision_inspection_detail : 비전검사 부위별 상세 판정. 불량 유형은 NG일 때만 기록
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_vision_inspection_detail' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_vision_inspection_detail] (
        [detail_id] INT IDENTITY(1,1) NOT NULL,
        [vision_inspection_id] INT NOT NULL,
        [weld_point_id] INT NOT NULL,
        [result] VARCHAR(10) NOT NULL CONSTRAINT [df_t_vision_inspection_detail_result] DEFAULT ('PENDING'),
        [defect_type] VARCHAR(50) NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_vision_inspection_detail_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_vision_inspection_detail] PRIMARY KEY CLUSTERED ([detail_id]),
        CONSTRAINT [uq_t_vision_inspection_detail_vision_inspection_id_weld_point_id] UNIQUE NONCLUSTERED ([vision_inspection_id], [weld_point_id])
    );
END
GO

-- t_vision_image : 비전검사 이미지 경로, 이미지 파일 자체는 파일서버에 저장하며 DB에는 경로만 기록
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_vision_image' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_vision_image] (
        [image_id] INT IDENTITY(1,1) NOT NULL,
        [vision_inspection_id] INT NOT NULL,
        [detail_id] INT NULL,
        [image_path] VARCHAR(500) NOT NULL,
        [image_type] VARCHAR(10) NULL,
        [captured_time] DATETIME2(3) NOT NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_vision_image_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_vision_image] PRIMARY KEY CLUSTERED ([image_id]),
        CONSTRAINT [ck_t_vision_image_image_type] CHECK ([image_type] IN ('RAW', 'OK', 'NG', 'OVERLAY'))
    );
END
GO

-- t_alarm_event : 설비 알람 이력. 발생/해제/확인 시각과 확인자 기록 (불량 원인 역추적 용도)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_alarm_event' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_alarm_event] (
        [alarm_id] INT IDENTITY(1,1) NOT NULL,
        [lot_id] INT NULL,
        [machine_id] INT NOT NULL,
        [alarm_code] VARCHAR(30) NOT NULL,
        [alarm_desc] VARCHAR(200) NOT NULL,
        [occurred_time] DATETIME2(3) NOT NULL,
        [resolved_time] DATETIME2(3) NULL,
        [source_device] VARCHAR(30) NULL,
        [ack_time] DATETIME2(3) NULL,
        [ack_user_id] INT NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_alarm_event_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_alarm_event] PRIMARY KEY CLUSTERED ([alarm_id])
    );
END
GO

-- t_alarm_action : 알람 조치 사항. 조치 담당자, 내용, 입력 시각
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_alarm_action' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_alarm_action] (
        [action_id] INT IDENTITY(1,1) NOT NULL,
        [alarm_id] INT NOT NULL,
        [worker_name] VARCHAR(50) NOT NULL,
        [action_desc] VARCHAR(500) NOT NULL,
        [action_time] DATETIME2(3) NOT NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_alarm_action_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_alarm_action] PRIMARY KEY CLUSTERED ([action_id])
    );
END
GO

-- t_user_login_history : 로그인 시도 이력(성공/실패/잠금). 보안 감사 및 잠금 판단 근거
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N't_user_login_history' AND SCHEMA_NAME(schema_id) = N'dbo')
BEGIN
    CREATE TABLE [dbo].[t_user_login_history] (
        [login_history_id] INT IDENTITY(1,1) NOT NULL,
        [user_id] INT NULL,
        [attempted_login_id] VARCHAR(50) NOT NULL,
        [login_result] VARCHAR(20) NOT NULL,
        [ip_address] VARCHAR(45) NULL,
        [login_time] DATETIME2(3) NOT NULL,
        [created_at] DATETIME2(3) NOT NULL CONSTRAINT [df_t_user_login_history_created_at] DEFAULT (DATEADD(HOUR, 9, SYSUTCDATETIME())),
        CONSTRAINT [pk_t_user_login_history] PRIMARY KEY CLUSTERED ([login_history_id])
    );
END
GO

/* ---------------------------------------------------------------------------
   1-2. 기존 DB 보강: 이미 만들어진 테이블에 updated_at 추가 (신규 생성분은 위에서 이미 포함)
   --------------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.m_weld_point', N'updated_at') IS NULL ALTER TABLE [dbo].[m_weld_point] ADD [updated_at] DATETIME2(3) NULL;
IF COL_LENGTH(N'dbo.m_parameter', N'updated_at') IS NULL ALTER TABLE [dbo].[m_parameter] ADD [updated_at] DATETIME2(3) NULL;
IF COL_LENGTH(N'dbo.m_recipe', N'updated_at') IS NULL ALTER TABLE [dbo].[m_recipe] ADD [updated_at] DATETIME2(3) NULL;
IF COL_LENGTH(N'dbo.m_recipe_target', N'updated_at') IS NULL ALTER TABLE [dbo].[m_recipe_target] ADD [updated_at] DATETIME2(3) NULL;
GO

/* ---------------------------------------------------------------------------
   2. 외래키 (관계 36개)
      - 부모(1) → 자식(N), 삭제/수정 제약은 NO ACTION
      - 부모 데이터를 먼저 삭제할 수 없으므로 기준정보 삭제는 사용 중인지 확인 후 진행
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_station_line_id_m_line')
    ALTER TABLE [dbo].[m_station] WITH CHECK ADD CONSTRAINT [fk_m_station_line_id_m_line]
        FOREIGN KEY ([line_id]) REFERENCES [dbo].[m_line] ([line_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_machine_station_id_m_station')
    ALTER TABLE [dbo].[m_machine] WITH CHECK ADD CONSTRAINT [fk_m_machine_station_id_m_station]
        FOREIGN KEY ([station_id]) REFERENCES [dbo].[m_station] ([station_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_weld_point_weld_machine_id_m_weld_machine')
    ALTER TABLE [dbo].[m_weld_point] WITH CHECK ADD CONSTRAINT [fk_m_weld_point_weld_machine_id_m_weld_machine]
        FOREIGN KEY ([weld_machine_id]) REFERENCES [dbo].[m_weld_machine] ([weld_machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_weld_point_vision_machine_id_m_machine')
    ALTER TABLE [dbo].[m_weld_point] WITH CHECK ADD CONSTRAINT [fk_m_weld_point_vision_machine_id_m_machine]
        FOREIGN KEY ([vision_machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_machine_spec_machine_id_m_machine')
    ALTER TABLE [dbo].[m_machine_spec] WITH CHECK ADD CONSTRAINT [fk_m_machine_spec_machine_id_m_machine]
        FOREIGN KEY ([machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_machine_spec_parameter_id_m_parameter')
    ALTER TABLE [dbo].[m_machine_spec] WITH CHECK ADD CONSTRAINT [fk_m_machine_spec_parameter_id_m_parameter]
        FOREIGN KEY ([parameter_id]) REFERENCES [dbo].[m_parameter] ([parameter_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_recipe_product_id_m_product')
    ALTER TABLE [dbo].[m_recipe] WITH CHECK ADD CONSTRAINT [fk_m_recipe_product_id_m_product]
        FOREIGN KEY ([product_id]) REFERENCES [dbo].[m_product] ([product_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_recipe_target_recipe_id_m_recipe')
    ALTER TABLE [dbo].[m_recipe_target] WITH CHECK ADD CONSTRAINT [fk_m_recipe_target_recipe_id_m_recipe]
        FOREIGN KEY ([recipe_id]) REFERENCES [dbo].[m_recipe] ([recipe_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_recipe_target_weld_point_id_m_weld_point')
    ALTER TABLE [dbo].[m_recipe_target] WITH CHECK ADD CONSTRAINT [fk_m_recipe_target_weld_point_id_m_weld_point]
        FOREIGN KEY ([weld_point_id]) REFERENCES [dbo].[m_weld_point] ([weld_point_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_recipe_target_parameter_id_m_parameter')
    ALTER TABLE [dbo].[m_recipe_target] WITH CHECK ADD CONSTRAINT [fk_m_recipe_target_parameter_id_m_parameter]
        FOREIGN KEY ([parameter_id]) REFERENCES [dbo].[m_parameter] ([parameter_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_weld_machine_machine_id_m_machine')
    ALTER TABLE [dbo].[m_weld_machine] WITH CHECK ADD CONSTRAINT [fk_m_weld_machine_machine_id_m_machine]
        FOREIGN KEY ([machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_m_weld_tip_status_weld_machine_id_m_weld_machine')
    ALTER TABLE [dbo].[m_weld_tip_status] WITH CHECK ADD CONSTRAINT [fk_m_weld_tip_status_weld_machine_id_m_weld_machine]
        FOREIGN KEY ([weld_machine_id]) REFERENCES [dbo].[m_weld_machine] ([weld_machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_lot_line_id_m_line')
    ALTER TABLE [dbo].[t_lot] WITH CHECK ADD CONSTRAINT [fk_t_lot_line_id_m_line]
        FOREIGN KEY ([line_id]) REFERENCES [dbo].[m_line] ([line_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_lot_product_id_m_product')
    ALTER TABLE [dbo].[t_lot] WITH CHECK ADD CONSTRAINT [fk_t_lot_product_id_m_product]
        FOREIGN KEY ([product_id]) REFERENCES [dbo].[m_product] ([product_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_lot_recipe_id_m_recipe')
    ALTER TABLE [dbo].[t_lot] WITH CHECK ADD CONSTRAINT [fk_t_lot_recipe_id_m_recipe]
        FOREIGN KEY ([recipe_id]) REFERENCES [dbo].[m_recipe] ([recipe_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_weld_event_lot_id_t_lot')
    ALTER TABLE [dbo].[t_weld_event] WITH CHECK ADD CONSTRAINT [fk_t_weld_event_lot_id_t_lot]
        FOREIGN KEY ([lot_id]) REFERENCES [dbo].[t_lot] ([lot_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_weld_event_weld_point_id_m_weld_point')
    ALTER TABLE [dbo].[t_weld_event] WITH CHECK ADD CONSTRAINT [fk_t_weld_event_weld_point_id_m_weld_point]
        FOREIGN KEY ([weld_point_id]) REFERENCES [dbo].[m_weld_point] ([weld_point_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_sensor_reading_lot_id_t_lot')
    ALTER TABLE [dbo].[t_sensor_reading] WITH CHECK ADD CONSTRAINT [fk_t_sensor_reading_lot_id_t_lot]
        FOREIGN KEY ([lot_id]) REFERENCES [dbo].[t_lot] ([lot_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_sensor_reading_machine_id_m_machine')
    ALTER TABLE [dbo].[t_sensor_reading] WITH CHECK ADD CONSTRAINT [fk_t_sensor_reading_machine_id_m_machine]
        FOREIGN KEY ([machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_sensor_reading_weld_point_id_m_weld_point')
    ALTER TABLE [dbo].[t_sensor_reading] WITH CHECK ADD CONSTRAINT [fk_t_sensor_reading_weld_point_id_m_weld_point]
        FOREIGN KEY ([weld_point_id]) REFERENCES [dbo].[m_weld_point] ([weld_point_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_sensor_reading_parameter_id_m_parameter')
    ALTER TABLE [dbo].[t_sensor_reading] WITH CHECK ADD CONSTRAINT [fk_t_sensor_reading_parameter_id_m_parameter]
        FOREIGN KEY ([parameter_id]) REFERENCES [dbo].[m_parameter] ([parameter_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_tip_maintenance_weld_machine_id_m_weld_machine')
    ALTER TABLE [dbo].[t_tip_maintenance] WITH CHECK ADD CONSTRAINT [fk_t_tip_maintenance_weld_machine_id_m_weld_machine]
        FOREIGN KEY ([weld_machine_id]) REFERENCES [dbo].[m_weld_machine] ([weld_machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_loading_event_lot_id_t_lot')
    ALTER TABLE [dbo].[t_loading_event] WITH CHECK ADD CONSTRAINT [fk_t_loading_event_lot_id_t_lot]
        FOREIGN KEY ([lot_id]) REFERENCES [dbo].[t_lot] ([lot_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_loading_event_machine_id_m_machine')
    ALTER TABLE [dbo].[t_loading_event] WITH CHECK ADD CONSTRAINT [fk_t_loading_event_machine_id_m_machine]
        FOREIGN KEY ([machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_loading_event_station_id_m_station')
    ALTER TABLE [dbo].[t_loading_event] WITH CHECK ADD CONSTRAINT [fk_t_loading_event_station_id_m_station]
        FOREIGN KEY ([station_id]) REFERENCES [dbo].[m_station] ([station_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_vision_inspection_lot_id_t_lot')
    ALTER TABLE [dbo].[t_vision_inspection] WITH CHECK ADD CONSTRAINT [fk_t_vision_inspection_lot_id_t_lot]
        FOREIGN KEY ([lot_id]) REFERENCES [dbo].[t_lot] ([lot_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_vision_inspection_machine_id_m_machine')
    ALTER TABLE [dbo].[t_vision_inspection] WITH CHECK ADD CONSTRAINT [fk_t_vision_inspection_machine_id_m_machine]
        FOREIGN KEY ([machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_vision_inspection_detail_vision_inspection_id_t_vision_inspection')
    ALTER TABLE [dbo].[t_vision_inspection_detail] WITH CHECK ADD CONSTRAINT [fk_t_vision_inspection_detail_vision_inspection_id_t_vision_inspection]
        FOREIGN KEY ([vision_inspection_id]) REFERENCES [dbo].[t_vision_inspection] ([vision_inspection_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_vision_inspection_detail_weld_point_id_m_weld_point')
    ALTER TABLE [dbo].[t_vision_inspection_detail] WITH CHECK ADD CONSTRAINT [fk_t_vision_inspection_detail_weld_point_id_m_weld_point]
        FOREIGN KEY ([weld_point_id]) REFERENCES [dbo].[m_weld_point] ([weld_point_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_vision_image_vision_inspection_id_t_vision_inspection')
    ALTER TABLE [dbo].[t_vision_image] WITH CHECK ADD CONSTRAINT [fk_t_vision_image_vision_inspection_id_t_vision_inspection]
        FOREIGN KEY ([vision_inspection_id]) REFERENCES [dbo].[t_vision_inspection] ([vision_inspection_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_vision_image_detail_id_t_vision_inspection_detail')
    ALTER TABLE [dbo].[t_vision_image] WITH CHECK ADD CONSTRAINT [fk_t_vision_image_detail_id_t_vision_inspection_detail]
        FOREIGN KEY ([detail_id]) REFERENCES [dbo].[t_vision_inspection_detail] ([detail_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_alarm_event_lot_id_t_lot')
    ALTER TABLE [dbo].[t_alarm_event] WITH CHECK ADD CONSTRAINT [fk_t_alarm_event_lot_id_t_lot]
        FOREIGN KEY ([lot_id]) REFERENCES [dbo].[t_lot] ([lot_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_alarm_event_machine_id_m_machine')
    ALTER TABLE [dbo].[t_alarm_event] WITH CHECK ADD CONSTRAINT [fk_t_alarm_event_machine_id_m_machine]
        FOREIGN KEY ([machine_id]) REFERENCES [dbo].[m_machine] ([machine_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_alarm_event_ack_user_id_m_user')
    ALTER TABLE [dbo].[t_alarm_event] WITH CHECK ADD CONSTRAINT [fk_t_alarm_event_ack_user_id_m_user]
        FOREIGN KEY ([ack_user_id]) REFERENCES [dbo].[m_user] ([user_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_alarm_action_alarm_id_t_alarm_event')
    ALTER TABLE [dbo].[t_alarm_action] WITH CHECK ADD CONSTRAINT [fk_t_alarm_action_alarm_id_t_alarm_event]
        FOREIGN KEY ([alarm_id]) REFERENCES [dbo].[t_alarm_event] ([alarm_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_t_user_login_history_user_id_m_user')
    ALTER TABLE [dbo].[t_user_login_history] WITH CHECK ADD CONSTRAINT [fk_t_user_login_history_user_id_m_user]
        FOREIGN KEY ([user_id]) REFERENCES [dbo].[m_user] ([user_id]) ON UPDATE NO ACTION ON DELETE NO ACTION;
GO

/* ---------------------------------------------------------------------------
   3. 인덱스 (조회 성능용, 7개)
      - LOT 목록, 알람 이력, 센서 조회 기간 검색에 사용
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_lot_index_0' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot'))
    CREATE NONCLUSTERED INDEX [t_lot_index_0] ON [dbo].[t_lot] ([lot_end_time]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_loading_event_index_0' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event'))
    CREATE NONCLUSTERED INDEX [t_loading_event_index_0] ON [dbo].[t_loading_event] ([lot_id], [event_type]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_vision_inspection_index_0' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection'))
    CREATE NONCLUSTERED INDEX [t_vision_inspection_index_0] ON [dbo].[t_vision_inspection] ([lot_id], [inspection_end_time]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_sensor_reading_index_0' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading'))
    CREATE NONCLUSTERED INDEX [t_sensor_reading_index_0] ON [dbo].[t_sensor_reading] ([lot_id], [weld_point_id], [parameter_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_alarm_event_index_0' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event'))
    CREATE NONCLUSTERED INDEX [t_alarm_event_index_0] ON [dbo].[t_alarm_event] ([occurred_time]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_alarm_event_index_1' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event'))
    CREATE NONCLUSTERED INDEX [t_alarm_event_index_1] ON [dbo].[t_alarm_event] ([resolved_time]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N't_weld_event_index_0' AND object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event'))
    CREATE NONCLUSTERED INDEX [t_weld_event_index_0] ON [dbo].[t_weld_event] ([lot_id]);
GO

/* ---------------------------------------------------------------------------
   4. 테이블·컬럼 설명 (MS_Description)
      - SSMS 의 '속성 > 설명'으로 표시되는 DB 내장 문서
      - 설계 변경 시 이 설명도 함께 갱신한다
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'라인 기준정보', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND name = N'line_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 라인 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line', @level2type = N'COLUMN', @level2name = N'line_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND name = N'line_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'라인 코드 (예: HW01)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line', @level2type = N'COLUMN', @level2name = N'line_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND name = N'line_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'라인 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line', @level2type = N'COLUMN', @level2name = N'line_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_line') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_line', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'공정 구역 기준정보', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'station_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 공정구역 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'station_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'line_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'라인 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'line_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'station_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'공정구역 코드 (예: LOAD-01, WELD-01)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'station_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'station_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'공정구역 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'station_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'station_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'공정구역 유형 LOAD, WELD, VISION, UNLOAD, COMPOSITE', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'station_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'sequence_no'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'라인 내 공정 순번', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'sequence_no';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_station') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_station', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 기준정보 (모든 설비)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 설비 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'station_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'공정구역 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'station_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'machine_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 코드', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'machine_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'machine_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'machine_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'machine_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 유형 (예: VISION, PLC, SENSOR_HUB, WELDER, ROBOT_LOAD. 신규 유형은 값만 추가)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'machine_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'model_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'모델명', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'model_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'manufacturer'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'제조사', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'manufacturer';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'install_date'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설치일', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'install_date';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위 기준정보 (부위 수 제한 없음)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'weld_point_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 용접부위 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'weld_point_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'weld_machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접기 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'weld_machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'weld_point_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위 코드', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'weld_point_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'weld_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접 유형 NUT or BOLT', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'weld_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'sequence_no'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접 순번', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'sequence_no';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'position_desc'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'도면상 부위 설명', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'position_desc';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'vision_machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'이 용접부위를 검사하는 비전 카메라', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'vision_machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_point') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'파라미터(센서 항목) 기준정보', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'parameter_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 파라미터 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'parameter_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'parameter_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'파라미터 코드', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'parameter_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'parameter_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'파라미터 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'parameter_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'unit'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'단위', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'unit';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'data_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'데이터 타입 (NUMERIC, INT, BOOLEAN, STRING) CHECK 제약: NUMERIC, INT, BOOLEAN, STRING 외 저장 불가', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'data_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_parameter') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비별 정격값 이력', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'spec_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 정격 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'spec_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'parameter_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'파라미터 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'parameter_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'rated_value'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'정격값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'rated_value';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'rated_min'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'정격 하한값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'rated_min';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'rated_max'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'정격 상한값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'rated_max';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'effective_from'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'기준값 적용 시작일', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'effective_from';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'effective_to'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'기준값 적용 종료일', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'effective_to';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_machine_spec') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_machine_spec', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'제품 기준정보', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'product_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 제품 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'product_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'product_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'제품 코드', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'product_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'product_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'제품 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'product_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'car_type_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'차종 코드', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'car_type_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_product') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_product', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'레시피 기준정보', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'recipe_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 레시피 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'recipe_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'recipe_no'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'업무용 레시피 번호', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'recipe_no';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'product_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'제품 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'product_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'version'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'레시피 버전', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'version';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'effective_from'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'적용 시작일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'effective_from';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'effective_to'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'적용 종료일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'effective_to';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'레시피별 용접부위 파라미터 목표값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'recipe_target_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 레시피 목표값 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'recipe_target_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'recipe_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'레시피 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'recipe_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'weld_point_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'weld_point_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'parameter_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'파라미터 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'parameter_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'target_value'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'목표값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'target_value';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'upper_limit'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'상한값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'upper_limit';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'lower_limit'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'하한값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'lower_limit';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_recipe_target') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접기 전용 스펙', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'weld_machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 용접기 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'weld_machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 ID (WELDER만 해당)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'electrode_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'전극 유형', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'electrode_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'tip_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'팁 유형', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'tip_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'tip_change_cycle'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'팁 교환 기준 타점수', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'tip_change_cycle';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'tip_dress_cycle'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'드레싱 기준 타점수', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'tip_dress_cycle';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_machine') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_machine', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접기 팁 현재 상태 (카운터, 교환 및 드레싱 누적)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'tip_status_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 팁 상태 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'tip_status_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'weld_machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접기 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'weld_machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'current_tip_count'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'현재 누적 타점수 (교환 시 0 초기화)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'current_tip_count';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'current_dress_count'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'드레싱 후 누적 타점수 (드레싱 시 0 초기화)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'current_dress_count';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'total_tip_change_cnt'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'총 팁 교환 횟수 (누적)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'total_tip_change_cnt';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'total_dress_cnt'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'총 드레싱 횟수 (누적)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'total_dress_cnt';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'last_tip_changed_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'마지막 팁 교환일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'last_tip_changed_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'last_dressed_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'마지막 드레싱일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'last_dressed_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_weld_tip_status') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_tip_status', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용자 계정 기준정보', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'user_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 사용자 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'user_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'login_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'로그인 아이디', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'login_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'password_hash'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비밀번호 해시값 (bcrypt/argon2, 평문 저장 금지)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'password_hash';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'user_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용자 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'user_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'role_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'권한 등급 (ADMIN, MANAGER, OPERATOR)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'role_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'department'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'소속 부서', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'department';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'email'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'이메일 주소', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'email';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'phone'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'연락처', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'phone';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'password_changed_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비밀번호 마지막 변경일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'password_changed_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'force_change_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'다음 로그인 시 비밀번호 변경 강제 여부 Y/N', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'force_change_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'failed_login_count'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'연속 로그인 실패 횟수', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'failed_login_count';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'locked_until'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'계정 잠금 해제 시각 (NULL이면 미잠금)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'locked_until';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'last_login_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'마지막 로그인 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'last_login_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'use_yn'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용여부 Y/N (퇴사자 등)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'use_yn';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N'm_user') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_user', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Lot(제품 1개) 생산 실적', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'lot_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, Lot ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'lot_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'lot_no'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'업무용 Lot 번호', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'lot_no';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'line_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'라인 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'line_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'product_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'제품 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'product_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'recipe_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'레시피 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'recipe_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'car_type_snapshot'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'생성 시점 차종 코드 스냅샷', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'car_type_snapshot';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'lot_start_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'로딩 완료 시각. 해당 LOT의 첫 LOAD_COMPLETE 이벤트(t_loading_event.event_time)를 LOT 생성 시 기록', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'lot_start_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'lot_end_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'최종 사이클 종료 시각. 해당 LOT의 비전검사(t_vision_inspection.inspection_end_time) 중 가장 늦은 시각을 비전검사 완료 시 기록 (완료 전에는 NULL)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'lot_end_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'final_result'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'최종 판정 OK, NG, PENDING', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'final_result';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'created_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_lot') AND name = N'updated_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_lot', @level2type = N'COLUMN', @level2name = N'updated_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위별 용접 실적', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'weld_event_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 용접 실적 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'weld_event_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'lot_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Lot ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'lot_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'weld_point_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'weld_point_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'weld_start_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접 시작 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'weld_start_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'weld_end_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접 완료 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'weld_end_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'weld_result'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접 결과 OK, NG, PENDING', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'weld_result';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'source_device'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'완료 판단 PLC 디바이스', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'source_device';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_weld_event') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_weld_event', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'센서값 로그', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'reading_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 센서값 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'reading_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'lot_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Lot ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'lot_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'weld_point_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위 ID (부위 단위 값만, 그 외 NULL)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'weld_point_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'parameter_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'파라미터 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'parameter_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'reading_value'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'측정값', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'reading_value';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'reading_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'측정 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'reading_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_sensor_reading') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_sensor_reading', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접기 팁 교환 및 드레싱 이력', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'maintenance_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 팁 이력 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'maintenance_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'weld_machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접기 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'weld_machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'maintenance_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'작업 유형 TIP_CHANGE, TIP_DRESS', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'maintenance_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'occurred_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'작업 발생 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'occurred_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'tip_count_at_change'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'작업 시점 누적 타점수', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'tip_count_at_change';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'worker_memo'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'작업자 메모 (선택 입력)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'worker_memo';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'source_device'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'근거 PLC 디바이스', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'source_device';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_tip_maintenance') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_tip_maintenance', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'로딩 로봇 동작 이력', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'loading_event_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 로딩 이력 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'loading_event_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'lot_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Lot ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'lot_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 ID (로딩 로봇만 해당)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'station_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'스테이션 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'station_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'event_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'이벤트 유형 LOAD_COMPLETE, UNLOAD_COMPLETE, GRIP, RELEASE', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'event_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'event_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'이벤트 발생 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'event_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'source_device'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'근거 PLC 디바이스', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'source_device';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_loading_event') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_loading_event', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비전검사 실적 (LOT·카메라 단위)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'vision_inspection_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 비전검사 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'vision_inspection_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'lot_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Lot ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'lot_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 ID (비전 카메라만 해당)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'inspection_start_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'검사 시작 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'inspection_start_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'inspection_end_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'검사 종료 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'inspection_end_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'overall_result'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'종합 판정 OK, NG, PENDING', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'overall_result';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'start_source_device'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'시작 판단 PLC 디바이스', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'start_source_device';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'result_source_device'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'판정 판단 PLC 디바이스', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'result_source_device';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비전검사 부위별 상세 판정', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND name = N'detail_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 비전검사 부위 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail', @level2type = N'COLUMN', @level2name = N'detail_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND name = N'vision_inspection_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비전검사 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail', @level2type = N'COLUMN', @level2name = N'vision_inspection_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND name = N'weld_point_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'용접부위 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail', @level2type = N'COLUMN', @level2name = N'weld_point_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND name = N'result'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'부위별 판정 OK, NG, PENDING', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail', @level2type = N'COLUMN', @level2name = N'result';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND name = N'defect_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'불량 유형 (NG일 때)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail', @level2type = N'COLUMN', @level2name = N'defect_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_inspection_detail') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_inspection_detail', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비전검사 이미지 경로', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'image_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 이미지 경로 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'image_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'vision_inspection_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비전검사 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'vision_inspection_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'detail_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'비전검사 상세 ID (부위 이미지인 경우만)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'detail_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'image_path'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'이미지 저장 경로 (파일서버)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'image_path';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'image_type'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'이미지 유형 (RAW, OK, NG, OVERLAY) CHECK 제약: RAW, OK, NG, OVERLAY 외 저장 불가', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'image_type';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'captured_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'촬영 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'captured_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_vision_image') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_vision_image', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 알람 이력', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'alarm_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 알람 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'alarm_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'lot_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Lot ID (설비 단독 알람은 NULL)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'lot_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'machine_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'설비 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'machine_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'alarm_code'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'알람 코드', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'alarm_code';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'alarm_desc'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'알람 내용', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'alarm_desc';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'occurred_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'알람 발생 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'occurred_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'resolved_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'알람 해제 시각 (미해제 시 NULL)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'resolved_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'source_device'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'근거 PLC 디바이스', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'source_device';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'ack_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'확인 시각 (확인 버튼 또는 조치 등록 시 기록)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'ack_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'ack_user_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'확인자', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'ack_user_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_event') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_event', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'알람 조치 사항', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND name = N'action_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 조치 사항 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action', @level2type = N'COLUMN', @level2name = N'action_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND name = N'alarm_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'알람 ID', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action', @level2type = N'COLUMN', @level2name = N'alarm_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND name = N'worker_name'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'조치 담당자 이름', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action', @level2type = N'COLUMN', @level2name = N'worker_name';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND name = N'action_desc'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'조치 내용', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action', @level2type = N'COLUMN', @level2name = N'action_desc';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND name = N'action_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'조치 입력 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action', @level2type = N'COLUMN', @level2name = N'action_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_alarm_action') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_alarm_action', @level2type = N'COLUMN', @level2name = N'created_at';
GO
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND minor_id = 0 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'로그인 시도 이력', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'login_history_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'PK, 로그인 이력 ID (IDENTITY)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'login_history_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'user_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'사용자 ID (로그인 실패 시 NULL 가능)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'user_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'attempted_login_id'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'시도한 로그인 아이디 (원본 그대로 기록)', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'attempted_login_id';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'login_result'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'결과 SUCCESS, FAIL_PW, FAIL_LOCKED, FAIL_NO_USER', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'login_result';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'ip_address'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'접속 IP', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'ip_address';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'login_time'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'시도 시각', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'login_time';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND minor_id = (SELECT column_id FROM sys.columns WHERE object_id = (SELECT object_id FROM sys.tables WHERE name = N't_user_login_history') AND name = N'created_at'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'등록일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N't_user_login_history', @level2type = N'COLUMN', @level2name = N'created_at';
GO

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = OBJECT_ID(N'dbo.m_weld_point') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.m_weld_point'), N'updated_at', 'ColumnId'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_weld_point', @level2type = N'COLUMN', @level2name = N'updated_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = OBJECT_ID(N'dbo.m_parameter') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.m_parameter'), N'updated_at', 'ColumnId'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_parameter', @level2type = N'COLUMN', @level2name = N'updated_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = OBJECT_ID(N'dbo.m_recipe') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.m_recipe'), N'updated_at', 'ColumnId'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe', @level2type = N'COLUMN', @level2name = N'updated_at';
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND name = N'MS_Description' AND major_id = OBJECT_ID(N'dbo.m_recipe_target') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.m_recipe_target'), N'updated_at', 'ColumnId'))
    EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'수정일시', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'm_recipe_target', @level2type = N'COLUMN', @level2name = N'updated_at';
GO

PRINT N'AJIN QMS 스키마 생성 완료: 테이블 23 · FK 36 · INDEX 7';
GO