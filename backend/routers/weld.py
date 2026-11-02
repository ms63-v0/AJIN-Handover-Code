"""용접 현황 API. 정의서 '용접 현황' 시트: 파라미터별 측정값(그래프/표 공용), 기준 상·하한, 최근 용접 알람."""
from fastapi import APIRouter, Query

from backend.alarms import alarm_rows, limit_info, parse_limit, priority_of
from backend.common import DATE_RE, DT_RE, time_range
from backend.config import WELD_RANGE_MAX_DAYS
from backend.db import query
from backend.sqldialect import paging

router = APIRouter(prefix="/api", tags=["weld"])


@router.get("/weld")
def weld(date: str | None = Query(None, pattern=DATE_RE), dt_from: str | None = Query(None, alias="from", pattern=DT_RE, description="시작 일시 YYYY-MM-DD HH:MM"), dt_to: str | None = Query(None, alias="to", pattern=DT_RE, description="종료 일시(생략 = 현재까지)"), part: int | None = Query(None, ge=1, le=99),
         parameters: str | None = Query(None, pattern=r"^[A-Z_,]{1,200}$", description="파라미터 코드 쉼표 목록(없으면 전체)")):
    start, end, day, label = time_range(date, dt_from, dt_to, WELD_RANGE_MAX_DAYS)
    wanted = set(parameters.split(",")) if parameters else None
    params = [p for p in query("SELECT parameter_id, parameter_code, parameter_name, unit FROM m_parameter WHERE use_yn = 'Y' ORDER BY parameter_id")
              if not wanted or p["parameter_code"] in wanted]

    # 측정값: reading_time 순서 그대로(평균·구간화 없음). 파트(sequence_no)마다 선 1개
    sql = """SELECT s.reading_time AS time, s.reading_value AS value, s.lot_id, l.lot_no, w.sequence_no AS part_no, s.parameter_id
             FROM t_sensor_reading s JOIN m_weld_point w ON w.weld_point_id = s.weld_point_id
             LEFT JOIN t_lot l ON l.lot_id = s.lot_id
             WHERE s.reading_time >= ? AND s.reading_time < ? AND s.reading_value IS NOT NULL"""
    args = [start, end]
    if part:
        sql += " AND w.sequence_no = ?"
        args.append(part)
    readings = query(sql + " ORDER BY s.reading_time, s.reading_id", tuple(args))

    # 기준값: 이 기간 LOT들이 쓴 레시피의 상·하한. 전체 선택 시 가장 큰 상한 / 가장 작은 하한
    # 점별 기준값: 각 측정점의 LOT이 쓴 레시피의 (파라미터, 파트) 상·하한
    lim_sql = """SELECT l.lot_id, t.parameter_id, w.sequence_no AS part_no, t.upper_limit, t.lower_limit
                 FROM m_recipe_target t JOIN m_weld_point w ON w.weld_point_id = t.weld_point_id
                 JOIN t_lot l ON l.recipe_id = t.recipe_id
                 WHERE l.lot_id IN (SELECT DISTINCT s.lot_id FROM t_sensor_reading s
                                    WHERE s.reading_time >= ? AND s.reading_time < ? AND s.lot_id IS NOT NULL)"""
    largs = [start, end]
    if part:
        lim_sql += " AND w.sequence_no = ?"
        largs.append(part)
    point_lim = {}
    for r in query(lim_sql, tuple(largs)):
        point_lim[(r["lot_id"], r["parameter_id"], r["part_no"])] = (r["upper_limit"], r["lower_limit"])

    # 기간 전체 참고값(하위 호환용): 이 기간 레시피들의 최댓값 상한 / 최솟값 하한
    limits = {}
    for (_lot, pid, _pn), (up_, lo_) in point_lim.items():
        cur = limits.setdefault(pid, [up_, lo_])
        cur[0], cur[1] = max(cur[0], up_), min(cur[1], lo_)

    out = []
    for p in params:
        pts = [r for r in readings if r["parameter_id"] == p["parameter_id"]]
        vals = [r["value"] for r in pts]
        series = {}
        for r in pts:
            hi, lo = point_lim.get((r["lot_id"], r["parameter_id"], r["part_no"]), (None, None))
            series.setdefault(r["part_no"], []).append({"time": r["time"], "value": r["value"], "lotId": r["lot_id"], "lotNo": r["lot_no"], "hi": hi, "lo": lo})
        up, lo = limits.get(p["parameter_id"], [None, None])
        out.append({"code": p["parameter_code"], "name": p["parameter_name"], "unit": p["unit"],
                    "limitUpper": up, "limitLower": lo,
                    "stats": {"min": min(vals), "max": max(vals), "avg": sum(vals) / len(vals)} if vals else None,
                    "series": [{"partNo": k, "points": v} for k, v in sorted(series.items())]})

    rows = alarm_rows(start, end, "welder", part)  # ①설비 알람 + ②기준 이탈 알람
    items = []
    for r in rows[:5]:
        info = limit_info(r)
        st = ("오류 발생 후 복귀" if info else "해제") if r["resolved_time"] else "발생"
        items.append({"alarmId": r["alarm_id"], "status": st, "time": r["occurred_time"][11:16], "message": r["message"],
                      "measured": info and info["measured"], "unit": info and info["unit"], "threshold": info and info["threshold"],
                      "recovered": info and info["recovered"], "param": info and info["param"], "acked": bool(r["ack_time"]), "priority": priority_of(r["alarm_code"])})
    # 차트 이벤트 마커(ISA-101 Event Overlay): 오늘 용접 알람 전체 발생 시각. 기준 이탈 알람은 해당 파라미터 차트에만 표시
    events = []
    for r in rows:
        lim = parse_limit(r["alarm_code"])
        events.append({"time": r["occurred_time"], "message": r["message"], "param": lim[1] if lim else None})
    return {"date": day, "range": {"from": start, "to": end, "label": label}, "parameters": out, "alarms": {"count": len(rows), "items": items}, "events": events}


@router.get("/weld/table")
def weld_table(
    date: str | None = Query(None, pattern=DATE_RE),
    dt_from: str | None = Query(None, alias="from", pattern=DT_RE),
    dt_to: str | None = Query(None, alias="to", pattern=DT_RE),
    part: int | None = Query(None, ge=1, le=99),
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=10, le=100),
):
    """표 보기 전용: 용접 이벤트(LOT × 파트) 단위 개별 행 반환 — 서버사이드 페이지네이션."""
    start, end, day, label = time_range(date, dt_from, dt_to, WELD_RANGE_MAX_DAYS)

    params = query("SELECT parameter_id AS id, parameter_code AS code, parameter_name AS name, unit FROM m_parameter WHERE use_yn='Y' ORDER BY parameter_id")

    where = "s.reading_time >= ? AND s.reading_time < ? AND s.reading_value IS NOT NULL AND s.weld_point_id IS NOT NULL"
    args: list = [start, end]
    if part:
        where += " AND w.sequence_no = ?"
        args.append(part)

    # 전체 건수: LOT × 파트 조합 수
    total = query(
        f"""SELECT COUNT(*) AS cnt FROM (
                SELECT DISTINCT s.lot_id, s.weld_point_id
                FROM t_sensor_reading s
                JOIN m_weld_point w ON w.weld_point_id = s.weld_point_id
                WHERE {where}
            ) AS pairs""", tuple(args)
    )[0]["cnt"]

    # 페이지 단위 LOT × 파트 조합
    offset = (page - 1) * per_page
    pg_sql, pg_params = paging(per_page, offset)
    pairs = query(
        f"""SELECT s.lot_id, s.weld_point_id, MAX(w.sequence_no) AS part_no,
                   MAX(s.reading_time) AS reading_time, MAX(l.lot_no) AS lot_no,
                   MAX(e.weld_result) AS weld_result
            FROM t_sensor_reading s
            JOIN m_weld_point w ON w.weld_point_id = s.weld_point_id
            JOIN t_lot l ON l.lot_id = s.lot_id
            LEFT JOIN t_weld_event e ON e.lot_id = s.lot_id AND e.weld_point_id = s.weld_point_id
            WHERE {where}
            GROUP BY s.lot_id, s.weld_point_id
            ORDER BY MAX(s.reading_time) DESC{pg_sql}""",
        tuple(args) + pg_params,
    )

    # 해당 페이지 lot+part 조합의 모든 파라미터 측정값 한 번에 조회
    readings: dict = {}
    if pairs:
        lot_ids = sorted({p_row["lot_id"] for p_row in pairs})
        point_ids = sorted({p_row["weld_point_id"] for p_row in pairs})
        wanted = {(p_row["lot_id"], p_row["weld_point_id"]) for p_row in pairs}
        for r in query(
            f"""SELECT s.lot_id, s.weld_point_id, s.parameter_id, s.reading_value
                FROM t_sensor_reading s
                WHERE s.lot_id IN ({','.join('?' * len(lot_ids))})
                  AND s.weld_point_id IN ({','.join('?' * len(point_ids))})
                  AND s.reading_value IS NOT NULL""",
            tuple(lot_ids) + tuple(point_ids),
        ):
            key = (r["lot_id"], r["weld_point_id"])
            if key in wanted:
                readings.setdefault(key, {})[r["parameter_id"]] = r["reading_value"]

    # 기준값
    lim_sql = """SELECT t.parameter_id, t.upper_limit, t.lower_limit
                 FROM m_recipe_target t JOIN m_weld_point w ON w.weld_point_id = t.weld_point_id
                 WHERE t.recipe_id IN (SELECT DISTINCT l.recipe_id FROM t_sensor_reading s JOIN t_lot l ON l.lot_id = s.lot_id
                                       WHERE s.reading_time >= ? AND s.reading_time < ?)"""
    largs: list = [start, end]
    if part:
        lim_sql += " AND w.sequence_no = ?"
        largs.append(part)
    limits: dict = {}
    for r in query(lim_sql, tuple(largs)):
        cur = limits.setdefault(r["parameter_id"], [r["upper_limit"], r["lower_limit"]])
        cur[0], cur[1] = max(cur[0], r["upper_limit"]), min(cur[1], r["lower_limit"])

    items = []
    for p_row in pairs:
        key = (p_row["lot_id"], p_row["weld_point_id"])
        vals = readings.get(key, {})
        row_ng = False
        param_vals = []
        for p in params:
            v = vals.get(p["id"])
            up, lo = limits.get(p["id"], [None, None])
            ng = v is not None and lo is not None and not (lo <= v <= up)
            row_ng |= ng
            param_vals.append({"code": p["code"], "name": p["name"], "unit": p["unit"], "value": v, "ng": ng})
        items.append({
            "lotNo": p_row["lot_no"],
            "partNo": p_row["part_no"],
            "time": p_row["reading_time"],
            "weldResult": p_row["weld_result"],
            "ng": row_ng,
            "params": param_vals,
        })

    return {
        "total": total, "page": page, "per_page": per_page,
        "params": [{"code": p["code"], "name": p["name"], "unit": p["unit"]} for p in params],
        "items": items,
    }