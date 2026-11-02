/* ============================================================================
   test.sql : 화면 연동 확인용 테스트 데이터 (m_line 에 TEST_0426 / 123)
   대상      : factory_db_test (실 DB에서 실행 금지)
   실행      : VS Code SQL Server 확장 또는 SSMS 에서 전체 실행 (F5)
   확인      : 마지막 SELECT 에 행 1건이 보여야 한다 (line_name = 123)
   ============================================================================ */
USE factory_db_test;
GO

IF EXISTS (SELECT 1 FROM m_line WHERE line_code = N'TEST_0426')
    UPDATE m_line
       SET line_name  = N'123',
           use_yn     = 'Y',
           updated_at = DATEADD(HOUR, 9, SYSUTCDATETIME())
     WHERE line_code  = N'TEST_0426';
ELSE
    INSERT INTO m_line (line_code, line_name, use_yn)
    VALUES (N'TEST_0426', N'123', 'Y');
GO

SELECT line_id, line_code, line_name, use_yn, created_at, updated_at
FROM m_line
WHERE line_code = N'TEST_0426';
GO