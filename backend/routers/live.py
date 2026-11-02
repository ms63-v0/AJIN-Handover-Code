"""실시간 수신용 경량 API (폴링). 전류값·용접결과·비전결과 3종 이벤트만 돌려준다.

cursor = "전류.용접.비전" (각 테이블에서 마지막으로 본 id). 클라이언트는 직전 응답의 cursor를 그대로 다시 보낸다.
첫 호출(after 비어 있음)은 각 테이블의 최근 N건부터 시작한다.
"""
from datetime import datetime

from fastapi import APIRouter, Query

from backend.db import query
from backend.sqldialect import LIMIT_PARAM

router = APIRouter(prefix="/api/live", tags=["live"])

CURRENT_CODE = "WELD_CURRENT"  # 정의서: m_parameter.parameter_code = 전류값 코드
INITIAL_BACKLOG = 4            # 첫 호출 시 테이블별로 되돌아볼 건수

_MAX_SQL = {
    "c": "SELECT COALESCE(MAX(reading_id), 0) AS m FROM t_sensor_reading",
    "w": "SELECT COALESCE(MAX(weld_event_id), 0) AS m FROM t_weld_event",
    "v": "SELECT COALESCE(MAX(vision_inspection_id), 0) AS m FROM t_vision_inspection",
}


@router.get("/feed")
def feed(after: str = Query("", pattern=r"^(\d+\.\d+\.\d+)?$"), limit: int = Query(50, ge=1, le=200)):
    if after:
        c, w, v = (int(x) for x in after.split("."))
    else:
        c, w, v = (max(0, query(_MAX_SQL[k])[0]["m"] - INITIAL_BACKLOG) for k in "cwv")

    current = query(  # 전류값: t_sensor_reading ⨝ m_parameter ⨝ m_weld_point ⨝ t_lot
        """SELECT s.reading_id AS id, s.reading_time AS time, s.lot_id, l.lot_no, w.sequence_no AS part_no,
                  s.reading_value AS value, p.unit
           FROM t_sensor_reading s
           JOIN m_parameter p ON p.parameter_id = s.parameter_id AND p.parameter_code = ?
           JOIN m_weld_point w ON w.weld_point_id = s.weld_point_id
           JOIN t_lot l ON l.lot_id = s.lot_id
           WHERE s.reading_id > ? ORDER BY s.reading_id""" + LIMIT_PARAM,
        (CURRENT_CODE, c, limit),
    )
    welds = query(  # 용접 결과: t_weld_event ⨝ m_weld_point ⨝ t_lot
        """SELECT e.weld_event_id AS id, e.weld_end_time AS time, e.lot_id, l.lot_no, w.sequence_no AS part_no,
                  e.weld_result AS result
           FROM t_weld_event e
           JOIN m_weld_point w ON w.weld_point_id = e.weld_point_id
           JOIN t_lot l ON l.lot_id = e.lot_id
           WHERE e.weld_event_id > ? AND e.weld_result != 'PENDING' ORDER BY e.weld_event_id""" + LIMIT_PARAM,
        (w, limit),
    )
    visions = query(  # 비전 결과: t_vision_inspection ⨝ t_lot ⨝ m_machine(카메라)
        """SELECT v.vision_inspection_id AS id, v.inspection_end_time AS time, v.lot_id, l.lot_no,
                  m.machine_code AS camera, v.overall_result AS result
           FROM t_vision_inspection v JOIN t_lot l ON l.lot_id = v.lot_id
           JOIN m_machine m ON m.machine_id = v.machine_id
           WHERE v.vision_inspection_id > ? AND v.overall_result != 'PENDING' ORDER BY v.vision_inspection_id""" + LIMIT_PARAM,
        (v, limit),
    )

    events = (
        [{"type": "CURRENT", **e} for e in current]
        + [{"type": "WELD", **e} for e in welds]
        + [{"type": "VISION", **e} for e in visions]
    )
    events.sort(key=lambda e: (e["time"] or "", e["id"]))
    last = lambda rows, cur: rows[-1]["id"] if rows else cur  # noqa: E731
    cursor = f"{last(current, c)}.{last(welds, w)}.{last(visions, v)}"
    return {"cursor": cursor, "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "events": events}
