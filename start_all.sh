#!/bin/bash
# 아침 기동: SQL Server → DB 확인 → 백엔드 → 시뮬레이터
# 사용: up            (시뮬레이터 포함)
#       bash start_all.sh --no-sim   (시뮬레이터 제외)

: "${FA00_PASSWORD:?새 터미널을 열고 FA00_PASSWORD를 먼저 설정하세요}"
SQL="docker exec ajin-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U fa00 -P Wlsalstn0603@ -C"
APP=/workspaces/ms_sql_prove/app
RUN_SIM=1
[ "${1:-}" = "--no-sim" ] && RUN_SIM=0

echo "== [1] SQL Server 컨테이너 =="
if docker ps --filter name=^ajin-mssql$ --format '{{.Names}}' | grep -q ajin-mssql; then
  echo "이미 실행 중"
elif docker ps -a --filter name=^ajin-mssql$ --format '{{.Names}}' | grep -q ajin-mssql; then
  docker start ajin-mssql >/dev/null 2>&1 || { echo "!! docker start 실패 (RWLayer 손상 가능) → 재생성 필요"; exit 1; }
  echo "컨테이너 시작"
else
  echo "!! 컨테이너 없음 → 재생성 필요"; exit 1
fi

echo "== [2] SQL Server 준비 대기 =="
for i in $(seq 1 30); do
  $SQL -Q "SELECT 1" >/dev/null 2>&1 && { echo "준비 완료"; break; }
  sleep 2
  [ "$i" = 30 ] && { echo "!! 60초 내 응답 없음 → docker logs ajin-mssql 확인"; exit 1; }
done

echo "== [3] DB 상태 =="
$SQL -h -1 -W -Q "SET NOCOUNT ON; SELECT name, state_desc FROM sys.databases WHERE name = N'factory_db_test'" | tr -d '\r' | sed '/^\s*$/d'

echo "== [4] 백엔드 (백그라운드) =="
pkill -f "uvicorn backend.main:app" 2>/dev/null; sleep 1
cd $APP && nohup uvicorn backend.main:app --host 127.0.0.1 --port 8000 > /tmp/backend.log 2>&1 &
for i in $(seq 1 15); do
  curl -s http://127.0.0.1:8000/health | grep -q '"ok"' && { echo "백엔드 정상: $(curl -s http://127.0.0.1:8000/health)"; break; }
  sleep 2
  [ "$i" = 15 ] && { echo "!! 백엔드 응답 없음 → tail -30 /tmp/backend.log 확인"; exit 1; }
done

if [ "$RUN_SIM" = 1 ]; then
  echo "== [5] 시뮬레이터 (백그라운드) =="
  pkill -f "collector/simulator.py" 2>/dev/null; sleep 1
  cd $APP && nohup python3 collector/simulator.py > /tmp/simulator.log 2>&1 &
  sleep 3
  tail -2 /tmp/simulator.log
fi

echo
echo "완료. 로그: /tmp/backend.log , /tmp/simulator.log"
echo "로컬 PC: Codespaces 연결 창(포트 8000) 확인 후 serve_ui.py 실행"
