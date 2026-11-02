"""비전 검사 현황 API + 이미지 전달. 정의서 '비전 검사 현황' 시트."""
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, Response

from backend.alarms import alarm_rows, priority_of
from backend.common import DATE_RE, DT_RE, defect_distribution, pct, time_range
from backend.config import VISION_LIVE_MIN
from backend.db import query
from backend.sqldialect import FIRST_ROW, age_seconds, paging
from backend.vision_image import overlay_svg

router = APIRouter(prefix="/api/vision", tags=["vision"])
IMAGE_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "vision_images"


@router.get("")
def vision(date: str | None = Query(None, pattern=DATE_RE), dt_from: str | None = Query(None, alias="from", pattern=DT_RE, description="시작 일시 YYYY-MM-DD HH:MM"), dt_to: str | None = Query(None, alias="to", pattern=DT_RE, description="종료 일시(생략 = 현재까지)"), part: int | None = Query(None, ge=1, le=99),
           result: str | None = Query(None, pattern=r"^(OK|NG)(,(OK|NG))?$", description="검사 카드에만 적용 (KPI·분포에는 미적용)"),
           page: int = Query(1, ge=1), per_page: int = Query(24, ge=6, le=100)):
    start, end, day, label = time_range(date, dt_from, dt_to)

    # ── KPI: LOT 단위 (재검사는 LOT의 가장 최근 검사 결과). 전체=카메라별 최근 검사 합산, 파트 선택=해당 부위 판정
    verdict: dict[int, str] = {}
    if part:
        for r in query("""SELECT v.lot_id, d.result FROM t_vision_inspection_detail d
                          JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
                          JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
                          WHERE w.sequence_no = ? AND d.result != 'PENDING' AND v.inspection_end_time >= ? AND v.inspection_end_time < ?
                          ORDER BY v.inspection_end_time, v.vision_inspection_id""", (part, start, end)):
            verdict[r["lot_id"]] = r["result"]
    else:
        latest: dict[tuple, dict] = {}
        for r in query("""SELECT lot_id, machine_id, overall_result FROM t_vision_inspection
                          WHERE overall_result != 'PENDING' AND inspection_end_time >= ? AND inspection_end_time < ?
                          ORDER BY inspection_end_time, vision_inspection_id""", (start, end)):
            latest[(r["lot_id"], r["machine_id"])] = r
        for (lot, _), r in latest.items():
            verdict[lot] = "NG" if (r["overall_result"] == "NG" or verdict.get(lot) == "NG") else "OK"
    n, ok = len(verdict), sum(1 for x in verdict.values() if x == "OK")
    ok_rate = pct(ok, n)

    # ── 연동 상태(LIVE): 최신 검사 created_at 이 DB 현재 시각 기준 N분 이내면 live (created_at 은 DB 시각=UTC)
    last = query(f"SELECT created_at, {age_seconds('created_at')} AS age FROM t_vision_inspection ORDER BY vision_inspection_id DESC{FIRST_ROW}")
    live = {"status": "live" if last and last[0]["age"] < VISION_LIVE_MIN * 60 else "idle", "lastDataAt": last[0]["created_at"] if last else None}

    # ── 검사 카드: 용접부위 1건 = 카드 1장 (PENDING 제외, OVERLAY 이미지)
    want = result.split(",") if result else ["OK", "NG"]
    sql = f"""SELECT d.detail_id, d.result, v.inspection_end_time AS time, l.lot_no, w.sequence_no AS part_no,
                     (SELECT i.image_id FROM t_vision_image i WHERE i.detail_id = d.detail_id AND i.image_type = 'OVERLAY' ORDER BY i.image_id{FIRST_ROW}) AS image_id
              FROM t_vision_inspection_detail d JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
              JOIN t_lot l ON l.lot_id = v.lot_id JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
              WHERE v.inspection_end_time >= ? AND v.inspection_end_time < ? AND d.result IN ({','.join('?' * len(want))})"""
    args = [start, end, *want]
    if part:
        sql += " AND w.sequence_no = ?"
        args.append(part)
    count_sql = f"""SELECT COUNT(*) AS cnt
              FROM t_vision_inspection_detail d JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
              JOIN t_lot l ON l.lot_id = v.lot_id JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
              WHERE v.inspection_end_time >= ? AND v.inspection_end_time < ? AND d.result IN ({','.join('?' * len(want))})"""
    count_args = [start, end, *want]
    if part:
        count_sql += " AND w.sequence_no = ?"
        count_args.append(part)
    total_cards = query(count_sql, tuple(count_args))[0]["cnt"]
    offset = (page - 1) * per_page
    pg_sql, pg_params = paging(per_page, offset)
    cards = query(sql + " ORDER BY v.inspection_end_time DESC, w.sequence_no, v.vision_inspection_id DESC, d.detail_id DESC" + pg_sql, (*args, *pg_params))
    cards = [{"imageId": c["image_id"], "result": c["result"], "lotNo": c["lot_no"], "time": c["time"][11:16], "partNo": c["part_no"]} for c in cards]

    # ── 카메라 상태: 용접부위 카드마다 담당 카메라 + 가장 최근 판정이 N분 이내면 '가동중'
    cams = query(f"""SELECT w.sequence_no AS part_no, m.machine_code AS camera,
                           (SELECT {age_seconds('MAX(d.created_at)')} FROM t_vision_inspection_detail d WHERE d.weld_point_id = w.weld_point_id) AS age
                    FROM m_weld_point w LEFT JOIN m_machine m ON m.machine_id = w.vision_machine_id
                    WHERE w.use_yn = 'Y' ORDER BY w.sequence_no""")
    cams = [{"partNo": c["part_no"], "camera": c["camera"] or "", "active": c["age"] is not None and c["age"] < VISION_LIVE_MIN * 60}
            for c in cams if not part or c["part_no"] == part]

    rows = alarm_rows(start, end, "vision", part)  # ③비전 알람 (NG 부위마다 1행)
    alarms = [{"alarmId": r["alarm_id"], "status": "해제" if r["resolved_time"] else "발생", "time": r["occurred_time"][11:16],
               "resolvedTime": r["resolved_time"][11:16] if r["resolved_time"] else None, "partNo": r["part_no"],
               "defectType": r["defect_type"], "lotNo": r["lot_no"], "message": r["message"],
               "acked": bool(r["ack_time"]), "priority": priority_of(r["alarm_code"])} for r in rows[:8]]

    return {"date": day, "range": {"from": start, "to": end, "label": label}, "kpi": {"inspectionCount": n, "okRate": ok_rate, "ngRate": round(100.0 - ok_rate, 1) if n else 0.0},
            "live": live, "total_cards": total_cards, "page": page, "per_page": per_page, "cards": cards, "defectTypes": defect_distribution(start, end, part), "cameras": cams,
            "alarms": {"count": len(rows), "items": alarms}}


@router.get("/images/{image_id}")
def image(image_id: int):
    """이미지 전달. image_path 는 화면/응답에 노출하지 않고 서버가 읽어서 내려준다. 'sim://' = 데모용 생성 이미지."""
    r = query("""SELECT i.image_path, i.image_id, COALESCE(d.result, v.overall_result) AS result, l.lot_no
                 FROM t_vision_image i JOIN t_vision_inspection v ON v.vision_inspection_id = i.vision_inspection_id
                 JOIN t_lot l ON l.lot_id = v.lot_id LEFT JOIN t_vision_inspection_detail d ON d.detail_id = i.detail_id
                 WHERE i.image_id = ?""", (image_id,))
    if not r:
        raise HTTPException(status_code=404, detail="Image not found")
    path = r[0]["image_path"]
    if path.startswith("sim://"):
        return Response(overlay_svg(r[0]["result"], image_id, r[0]["lot_no"]), media_type="image/svg+xml", headers={"Cache-Control": "private, max-age=3600"})
    f = (IMAGE_DIR / path).resolve()
    if IMAGE_DIR.resolve() not in f.parents or not f.is_file():  # 경로 조작(../) 차단
        raise HTTPException(status_code=404, detail="Image not found")
    return FileResponse(f)