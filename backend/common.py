"""화면 공통 집계 도우미: 날짜 범위, 부위별 판정, 불량 유형 분포."""
from datetime import datetime, timedelta

from backend.db import query
from backend.sqldialect import chunks

FMT = "%Y-%m-%d %H:%M:%S"
DATE_RE = r"^\d{4}-\d{2}-\d{2}$"


def day_range(date: str | None):
    """선택일 0시 이상 ~ 다음날 0시 미만 (기본 오늘). → (시작, 끝, 'YYYY-MM-DD')"""
    d = datetime.strptime(date, "%Y-%m-%d") if date else datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    return d.strftime(FMT), (d + timedelta(days=1)).strftime(FMT), d.strftime("%Y-%m-%d")


DT_RE = r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$"   # 'YYYY-MM-DD HH:MM' (초 생략 가능)


def _parse_dt(s: str) -> datetime:
    s = s.replace("T", " ")
    return datetime.strptime(s, "%Y-%m-%d %H:%M:%S" if s.count(":") == 2 else "%Y-%m-%d %H:%M")


def time_range(date: str | None = None, dt_from: str | None = None, dt_to: str | None = None, max_days: int | None = None):
    """조회 구간 [시작, 끝) → (시작, 끝, 기준일 'YYYY-MM-DD', 표시용 '시작 ~ 종료')

    · from 이 있으면 구간 조회. to 생략 = 현재 시각까지(실시간). 화면의 종료 시각은 '분' 단위로 포함(끝 = 종료 분 + 1분 미만).
    · from 이 없으면 date 하루(00:00 ~ 다음날 00:00), date 도 없으면 오늘.
    """
    from fastapi import HTTPException
    from backend.config import RANGE_MAX_DAYS

    if not dt_from:
        start, end, day = day_range(date)
        return start, end, day, f"{day} 00:00 ~ {day} 23:59"
    now = datetime.now().replace(microsecond=0)
    s = _parse_dt(dt_from)
    if dt_to:
        e = _parse_dt(dt_to)
        end = e + (timedelta(minutes=1) if dt_to.replace("T", " ").count(":") == 1 else timedelta(seconds=1))
        label_to = e.strftime("%Y-%m-%d %H:%M")
    else:
        end = now + timedelta(seconds=1)
        label_to = f"현재({now:%Y-%m-%d %H:%M})"
    if end <= s:
        raise HTTPException(422, "종료 일시는 시작 일시보다 뒤여야 합니다.")
    limit = max_days or RANGE_MAX_DAYS
    if end - s > timedelta(days=limit, minutes=1):
        raise HTTPException(422, f"조회 기간은 최대 {limit}일까지 가능합니다.")
    return s.strftime(FMT), end.strftime(FMT), s.strftime("%Y-%m-%d"), f"{s:%Y-%m-%d %H:%M} ~ {label_to}"


def pct(n: int, d: int, nd: int = 1) -> float:
    return round(n * 100 / d, nd) if d else 0.0


def in_marks(values) -> str:
    return ",".join("?" * len(values))


def part_verdicts(lot_ids: list[int], part_no: int) -> dict[int, str]:
    """LOT별 '부위 종합 판정' = 해당 부위의 용접·비전 결과 중 하나라도 NG면 NG, 둘 다 OK면 OK (PENDING 제외)."""
    if not lot_ids:
        return {}
    ids = tuple(lot_ids)
    weld, vis = {}, {}
    for piece in chunks(ids):   # MSSQL 파라미터 한도(2100) 때문에 나눠서 조회
        m, sub = in_marks(piece), tuple(piece)
        for r in query(f"""SELECT e.lot_id, e.weld_result AS r FROM t_weld_event e JOIN m_weld_point w ON w.weld_point_id = e.weld_point_id
                           WHERE w.sequence_no = ? AND e.lot_id IN ({m}) ORDER BY e.weld_start_time""", (part_no, *sub)):
            weld[r["lot_id"]] = r["r"]
        for r in query(f"""SELECT v.lot_id, d.result AS r FROM t_vision_inspection_detail d
                           JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
                           JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
                           WHERE w.sequence_no = ? AND v.lot_id IN ({m}) ORDER BY v.inspection_end_time""", (part_no, *sub)):
            vis[r["lot_id"]] = r["r"]
    out = {}
    for lot in ids:
        got = [x for x in (weld.get(lot), vis.get(lot)) if x in ("OK", "NG")]
        if got:
            out[lot] = "NG" if "NG" in got else "OK"
    return out


def defect_distribution(start: str, end: str, part: int | None = None) -> list[dict]:
    """불량 유형별 LOT 수 (정의서): t_vision_inspection_detail.defect_type 에 실제로 기록된 값만 집계.
    상위 5개 + 기타(나머지 합산). 발생 건수가 없으면 빈 목록 반환 (임의 0건 막대 없음).
    """
    sql = """SELECT d.defect_type AS label, COUNT(DISTINCT v.lot_id) AS count
             FROM t_vision_inspection_detail d
             JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
             JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
             WHERE d.result = 'NG' AND d.defect_type IS NOT NULL AND v.inspection_end_time >= ? AND v.inspection_end_time < ?"""
    params = [start, end]
    if part:
        sql += " AND w.sequence_no = ?"
        params.append(part)
    rows = query(sql + " GROUP BY d.defect_type ORDER BY count DESC, d.defect_type", tuple(params))
    if not rows:
        return []
    top, rest_rows = rows[:5], rows[5:]
    rest = sum(r["count"] for r in rest_rows)
    total = sum(r["count"] for r in top) + rest
    for r in top:
        r["ratio"] = pct(r["count"], total)
    result = list(top)
    if rest:
        result.append({"label": "기타", "count": rest,
                       "ratio": max(0.0, round(100.0 - sum(r["ratio"] for r in top), 1))})
    return result
