"""Lot 조회 화면용 API. 매핑 기준: 정의서 [화면_DB매핑] 시트의 'LOT 조회' 행.

- 목록 날짜/정렬 = t_lot.lot_end_time (종료되지 않은 LOT은 조회 대상 아님)
- 파트 = m_weld_point.sequence_no (use_yn = 'Y')
- 같은 부위 결과가 여러 건이면 가장 최근 1건, 비전은 가장 최근 검사 1건
"""
from datetime import datetime, timedelta

from fastapi import APIRouter, Query

from backend.common import DT_RE, time_range
from backend.db import query
from backend.sqldialect import FIRST_ROW, chunks

router = APIRouter(prefix="/api", tags=["lots"])

# 비전판정: 카메라(machine_id)별로 가장 최근 검사만 보고, 하나라도 NG면 NG / 진행 중이면 PENDING / 전부 OK면 OK
VISION_RESULT_SQL = """(SELECT CASE WHEN COUNT(*) = 0 THEN NULL
                                    WHEN SUM(CASE WHEN v.overall_result = 'NG' THEN 1 ELSE 0 END) > 0 THEN 'NG'
                                    WHEN SUM(CASE WHEN v.overall_result = 'PENDING' THEN 1 ELSE 0 END) > 0 THEN 'PENDING' ELSE 'OK' END
                        FROM t_vision_inspection v
                        WHERE v.lot_id = l.lot_id AND v.inspection_end_time = (
                              SELECT MAX(v2.inspection_end_time) FROM t_vision_inspection v2
                              WHERE v2.lot_id = v.lot_id AND v2.machine_id = v.machine_id))"""


@router.get("/parts")
def list_parts():
    """용접부위 필터 버튼/목록 열: use_yn = 'Y' 인 sequence_no 오름차순."""
    return query("SELECT DISTINCT sequence_no AS part_no FROM m_weld_point WHERE use_yn = 'Y' ORDER BY part_no")


@router.get("/lots")
def list_lots(
    date: str | None = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$", description="종료일 YYYY-MM-DD (없으면 전체)"),
    dt_from: str | None = Query(None, alias="from", pattern=DT_RE, description="종료 일시 구간 시작 YYYY-MM-DD HH:MM"),
    dt_to: str | None = Query(None, alias="to", pattern=DT_RE, description="종료 일시 구간 끝(생략 = 현재까지)"),
    lot_no: str | None = Query(None, pattern=r"^\d{1,50}$", description="Lot 번호(숫자만) 부분 일치"),
    part: int | None = Query(None, ge=1, le=99, description="판정 필터를 적용할 파트(없으면 종합판정)"),
    result: str | None = Query(None, pattern="^(OK|NG)$", description="판정 필터"),
    page: int = Query(1, ge=1, description="페이지 번호 (1부터)"),
    per_page: int = Query(50, ge=10, le=100, description="페이지당 건수 (10·20·50·100)"),
):
    where, params = ["l.lot_end_time IS NOT NULL"], []
    if dt_from:
        s, e, _, _ = time_range(None, dt_from, dt_to)
        where.append("l.lot_end_time >= ? AND l.lot_end_time < ?")
        params += [s, e]
    elif date:
        try:
            next_day = (datetime.strptime(date, "%Y-%m-%d") + timedelta(days=1)).strftime("%Y-%m-%d")
        except ValueError:   # 존재하지 않는 날짜(예: 2월 31일)는 결과 없음
            where.append("1 = 0")
        else:
            where.append("l.lot_end_time >= ? AND l.lot_end_time < ?")
            params += [date, next_day]
    if lot_no:
        where.append("l.lot_no LIKE ?")
        params.append(f"%{lot_no}%")

    rows = query(
        f"""SELECT l.lot_id, l.lot_no, l.lot_end_time, l.final_result,
                   {VISION_RESULT_SQL} AS vision_result
            FROM t_lot l WHERE {' AND '.join(where)}
            ORDER BY l.lot_end_time DESC""",
        tuple(params),
    )

    # 부위별 용접/비전 결과 조인
    parts: dict[int, dict[int, str]] = {}
    vparts: dict[int, dict[int, str]] = {}
    if rows:
        for ids in chunks(r["lot_id"] for r in rows):   # MSSQL 파라미터 한도(2100) 때문에 나눠서 조회
            marks = ",".join("?" * len(ids))
            for e in query(
                f"""SELECT e.lot_id, w.sequence_no AS part_no, e.weld_result
                    FROM t_weld_event e JOIN m_weld_point w ON w.weld_point_id = e.weld_point_id
                    WHERE e.lot_id IN ({marks}) ORDER BY e.weld_start_time""",
                tuple(ids),
            ):
                parts.setdefault(e["lot_id"], {})[e["part_no"]] = e["weld_result"]
            for e in query(
                f"""SELECT v.lot_id, w.sequence_no AS part_no, d.result
                    FROM t_vision_inspection_detail d
                    JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
                    JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
                    WHERE v.lot_id IN ({marks}) ORDER BY v.inspection_end_time, v.vision_inspection_id""",
                tuple(ids),
            ):
                vparts.setdefault(e["lot_id"], {})[e["part_no"]] = e["result"]
    for r in rows:
        r["parts"] = parts.get(r["lot_id"], {})
        r["visionParts"] = vparts.get(r["lot_id"], {})

    # 판정 필터
    def verdict(r):
        if not part:
            return r["final_result"]
        got = [x for x in (r["parts"].get(part), r["visionParts"].get(part)) if x in ("OK", "NG")]
        return "NG" if "NG" in got else ("OK" if got else None)

    if result:
        rows = [r for r in rows if verdict(r) == result]

    total = len(rows)
    offset = (page - 1) * per_page
    items = rows[offset: offset + per_page]

    return {"total": total, "page": page, "per_page": per_page, "items": items}


@router.get("/lots/{lot_id}")
def get_lot_detail(lot_id: int):
    """상세: 부위별 용접 결과 + 센서값(parameter_code별 최신 1건) + 비전(최근 검사)."""
    from fastapi import HTTPException
    lot = query("SELECT lot_id, lot_no, lot_end_time, final_result FROM t_lot WHERE lot_id = ?", (lot_id,))
    if not lot:
        raise HTTPException(status_code=404, detail="Lot not found")

    part_rows = query(
        """SELECT w.weld_point_id, w.sequence_no AS part_no, w.weld_point_code,
                  (SELECT e.weld_result FROM t_weld_event e
                    WHERE e.lot_id = ? AND e.weld_point_id = w.weld_point_id
                    ORDER BY e.weld_start_time DESC""" + FIRST_ROW + """) AS result
           FROM m_weld_point w WHERE w.use_yn = 'Y' ORDER BY w.sequence_no""",
        (lot_id,),
    )

    by_point: dict[int, dict] = {}
    for s in query(
        """SELECT s.weld_point_id, p.parameter_code, p.unit, s.reading_value
           FROM t_sensor_reading s JOIN m_parameter p ON p.parameter_id = s.parameter_id
           WHERE s.lot_id = ? AND s.weld_point_id IS NOT NULL
           ORDER BY s.reading_time, s.reading_id""",
        (lot_id,),
    ):
        by_point.setdefault(s["weld_point_id"], {})[s["parameter_code"]] = {"value": s["reading_value"], "unit": s["unit"]}
    for p in part_rows:
        p["readings"] = by_point.get(p["weld_point_id"], {})

    latest = query(
        """SELECT v.vision_inspection_id, v.overall_result FROM t_vision_inspection v
           WHERE v.lot_id = ? AND v.inspection_end_time = (
                 SELECT MAX(v2.inspection_end_time) FROM t_vision_inspection v2
                 WHERE v2.lot_id = v.lot_id AND v2.machine_id = v.machine_id)""",
        (lot_id,),
    )
    vision = None
    if latest:
        results = {v["overall_result"] for v in latest}
        overall = "NG" if "NG" in results else "PENDING" if "PENDING" in results else "OK"
        reason = "결함 미검출"
        if overall != "OK":
            marks = ",".join("?" * len(latest))
            defects = [d["defect_type"] for d in query(
                f"""SELECT DISTINCT defect_type FROM t_vision_inspection_detail
                    WHERE vision_inspection_id IN ({marks}) AND result = 'NG' AND defect_type IS NOT NULL""",
                tuple(v["vision_inspection_id"] for v in latest),
            )]
            reason = ", ".join(defects) or None
        img = query(f"""SELECT image_id FROM t_vision_image WHERE detail_id IS NULL AND image_type = 'OVERLAY'
                        AND vision_inspection_id IN ({",".join("?" * len(latest))}) ORDER BY image_id""" + FIRST_ROW,
                    tuple(v["vision_inspection_id"] for v in latest))
        vision = {"overall_result": overall, "reason": reason, "imageId": img[0]["image_id"] if img else None}

    return {"lot": lot[0], "parts": part_rows, "vision": vision}