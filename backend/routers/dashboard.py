"""대시보드 API. 날짜 기준: 반드시 00:00:00 기준(서버 로컬 시각).
KPI / 부위별 / 알람 = 항상 오늘(date 파라미터 무시).
추이 = date 파라미터 있으면 해당 날짜, 없으면 오늘. 30분 단위 눈금.
"""
from datetime import datetime, timedelta

from fastapi import APIRouter, Query

from backend.common import DATE_RE, FMT, defect_distribution, in_marks, part_verdicts, pct
from backend.db import query
from backend.sqldialect import limit_n, seconds_between

router = APIRouter(prefix="/api", tags=["dashboard"])


def _today_range():
    d = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    return d.strftime(FMT), (d + timedelta(days=1)).strftime(FMT), d.strftime("%Y-%m-%d")


@router.get("/dashboard")
def dashboard(
    date: str | None = Query(None, pattern=DATE_RE),
    part: int | None = Query(None, ge=1, le=99),
):
    now = datetime.now()
    t0, t1, today_str = _today_range()

    # KPI: 오늘 00:00 ~ 내일 00:00 엄격 기준
    lots = query(
        "SELECT lot_id, final_result FROM t_lot WHERE lot_end_time >= ? AND lot_end_time < ? AND final_result != 'PENDING'",
        (t0, t1),
    )
    ok_n = sum(1 for r in lots if r["final_result"] == "OK")
    ng_n = sum(1 for r in lots if r["final_result"] == "NG")
    cyc = query(
        f"""SELECT {seconds_between('s', 'e')} AS sec FROM (
               SELECT (SELECT MIN(event_time) FROM t_loading_event WHERE lot_id = l.lot_id AND event_type = 'LOAD_COMPLETE') AS s,
                      (SELECT MAX(inspection_end_time) FROM t_vision_inspection WHERE lot_id = l.lot_id) AS e
               FROM t_lot l WHERE l.final_result != 'PENDING') AS cyc
           WHERE s IS NOT NULL AND e >= ? AND e < ?""",
        (t0, t1),
    )
    secs = [r["sec"] for r in cyc if r["sec"] is not None and r["sec"] > 0]
    kpi = {
        "production": len(lots), "okCount": ok_n, "ngCount": ng_n,
        "okRate": pct(ok_n, len(lots), 2), "ngRate": pct(ng_n, len(lots), 2),
        "cycle": {"avg": round(sum(secs)/len(secs),1),"min": round(min(secs),1),"max": round(max(secs),1)} if secs else None,
    }

    # 추이: 30분 단위, 선택일 00:00 ~ 현재(오늘) 또는 선택일 23:30(과거)
    sel_date = date if date else today_str
    s_dt = datetime.strptime(sel_date, "%Y-%m-%d")
    e_dt = s_dt + timedelta(days=1)
    is_today = sel_date == today_str

    dlots = query(
        "SELECT lot_id, final_result, lot_end_time FROM t_lot WHERE lot_end_time >= ? AND lot_end_time < ? AND final_result != 'PENDING'",
        (s_dt.strftime(FMT), e_dt.strftime(FMT)),
    )
    if part:
        pv = part_verdicts([r["lot_id"] for r in dlots], part)
        dlots = [{**r, "final_result": pv[r["lot_id"]]} for r in dlots if r["lot_id"] in pv]

    trend, ok_cum, ng_cum, m = [], 0, 0, 0
    while m < 24 * 60:
        tick = s_dt + timedelta(minutes=m)
        next_tick = tick + timedelta(minutes=30)
        if is_today and tick > now:
            break
        upto = min(next_tick, now) if is_today else next_tick
        seg = [r for r in dlots if tick.strftime(FMT) <= r["lot_end_time"] < upto.strftime(FMT)]
        oc = sum(1 for r in seg if r["final_result"] == "OK")
        nc = sum(1 for r in seg if r["final_result"] == "NG")
        ok_cum += oc; ng_cum += nc
        trend.append({
            "time": f"{tick.hour:02d}:{tick.minute:02d}",
            "ts": int(tick.timestamp() * 1000),   # 프론트에서 연속 x 좌표 계산용
            "okCount": oc, "ngCount": nc,
            # 구간별 독립 집계(누적 아님): 해당 30분 구간의 생산 수량과 불량률. 생산 0이면 불량률 0 (0 나누기 방지)
            "production": oc + nc, "ngRate": pct(nc, oc + nc, 2),
            "isCurrent": is_today and tick <= now < next_tick,
            "tooltip": {"okCumulative": ok_cum, "ngCumulative": ng_cum, "defectRate": pct(ng_cum, ok_cum+ng_cum, 2)},
        })
        m += 30

    ids = [r["lot_id"] for r in lots]
    processes = []
    for p in query("SELECT sequence_no, weld_point_code FROM m_weld_point WHERE use_yn = 'Y' ORDER BY sequence_no"):
        pv2 = part_verdicts(ids, p["sequence_no"])
        o, n_ = sum(1 for x in pv2.values() if x == "OK"), sum(1 for x in pv2.values() if x == "NG")
        processes.append({"partNo": p["sequence_no"], "code": p["weld_point_code"],
                          "okCount": o, "ngCount": n_, "okRate": pct(o, o+n_), "ngRate": pct(n_, o+n_)})

    alarms = query(
        "SELECT alarm_id, alarm_desc AS message, occurred_time, resolved_time FROM t_alarm_event WHERE occurred_time >= ? AND occurred_time < ? ORDER BY occurred_time DESC, alarm_id DESC" + limit_n(5),
        (t0, t1),
    )
    return {
        "date": sel_date, "kpi": kpi, "trend": trend,
        "defectTypes": defect_distribution(s_dt.strftime(FMT), e_dt.strftime(FMT)),
        "processes": processes,
        "alarms": [{"alarmId": a["alarm_id"], "status": "해제" if a["resolved_time"] else "발생",
                    "time": a["occurred_time"][11:16], "message": a["message"]} for a in alarms],
    }
