"""기준정보 조회 API (라인 / 스테이션 / 설비)."""
from fastapi import APIRouter

from backend.db import query
from backend.sqldialect import age_seconds

router = APIRouter(prefix="/api", tags=["master"])


@router.get("/lines")
def get_lines():
    return query("SELECT * FROM m_line ORDER BY line_code")


@router.get("/lines/{line_id}/stations")
def get_stations(line_id: int):
    return query("SELECT * FROM m_station WHERE line_id = ? ORDER BY sequence_no", (line_id,))


@router.get("/machines")
def get_machines():
    return query(
        """SELECT m.*, s.station_code, s.station_name
           FROM m_machine m JOIN m_station s ON s.station_id = m.station_id
           ORDER BY m.machine_code"""
    )


@router.get("/status")
def process_status():
    """공정 연결 상태: 용접부위(use_yn='Y')별 가장 최근 용접 실적이 N분 이내면 연결됨. (created_at = DB 시각 기준)"""
    from backend.config import VISION_LIVE_MIN
    rows = query(f"""SELECT w.sequence_no AS part_no,
                           (SELECT {age_seconds('MAX(e.created_at)')} FROM t_weld_event e WHERE e.weld_point_id = w.weld_point_id) AS age
                    FROM m_weld_point w WHERE w.use_yn = 'Y' ORDER BY w.sequence_no""")
    return {"parts": [{"partNo": r["part_no"], "connected": r["age"] is not None and r["age"] < VISION_LIVE_MIN * 60} for r in rows]}
