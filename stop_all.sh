#!/bin/bash
# 퇴근 시: 백업 → 백엔드·시뮬레이터 종료
: "${MSSQL_SA_PASSWORD:?새 터미널을 열고 MSSQL_SA_PASSWORD를 먼저 설정하세요}"
SQL="docker exec ajin-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P Wlsalstn0603@ -C"
pkill -f collector/simulator.py 2>/dev/null && echo "시뮬레이터 종료"
pkill -f "uvicorn backend.main:app" 2>/dev/null && echo "백엔드 종료"
$SQL -Q "BACKUP DATABASE factory_db_test TO DISK = N'/var/opt/mssql/data/factory_db_test.bak' WITH INIT" >/dev/null 2>&1 \
  && echo "DB 백업 완료" || echo "!! DB 백업 실패 (컨테이너 상태 확인)"
