"""알람 조회 공통 로직 (대시보드 / 용접 현황 / 비전 검사 현황 / 알람 이력 화면이 공유).

알람 3종은 모두 t_alarm_event 에 저장된다.
 ① 설비 알람   : 용접기 알람 (alarm_code 예: A-001)
 ② 기준 이탈   : 센서값이 레시피 상·하한을 벗어난 첫 값 → alarm_code = 'LIM_HI|LIM_LO:{파라미터코드}:{파트번호}'
 ③ 비전 알람   : 카메라 NG 판정 → alarm_code = 'VIS_NG' (NG 부위마다 화면 1행으로 펼침)
"""
from datetime import datetime

from backend.common import FMT
from backend.config import ALARM_GUIDES, ALARM_PRIORITY_DEFAULT, ALARM_PRIORITY_RULES
from backend.db import query
from backend.sqldialect import FIRST_ROW, first_row_any

BASE_SQL = """SELECT a.alarm_id, a.lot_id, a.machine_id, a.alarm_code, a.alarm_desc, a.occurred_time, a.resolved_time, a.source_device, a.ack_time, a.ack_user_id, ua.user_name AS ack_user,
       m.machine_code, m.machine_type, l.lot_no, l.final_result, l.recipe_id,
       (SELECT COUNT(*) FROM t_alarm_action x WHERE x.alarm_id = a.alarm_id) AS action_count,
       (SELECT x.worker_name FROM t_alarm_action x WHERE x.alarm_id = a.alarm_id ORDER BY x.action_time DESC, x.action_id DESC""" + FIRST_ROW + """) AS worker
    FROM t_alarm_event a JOIN m_machine m ON m.machine_id = a.machine_id LEFT JOIN t_lot l ON l.lot_id = a.lot_id LEFT JOIN m_user ua ON ua.user_id = a.ack_user_id"""


def status_of(r: dict) -> str:
    """resolved_time 있으면 해결됨 / 조치 1건 이상 조치중 / 없으면 미해결 (정의서)."""
    return "해결됨" if r["resolved_time"] else ("조치중" if r["action_count"] else "미해결")


def parse_limit(code: str):
    """'LIM_HI:WELD_CURRENT:2' → ('HI', 'WELD_CURRENT', 2) / 해당 없으면 None"""
    p = (code or "").split(":")
    if len(p) == 3 and p[0] in ("LIM_HI", "LIM_LO") and p[2].isdigit():
        return p[0][4:], p[1], int(p[2])
    return None


PRIORITY_LABEL = {1: "긴급", 2: "경고", 3: "주의"}


def priority_of(code: str | None) -> int:
    """ISA-18.2 우선순위 (1 긴급 / 2 경고 / 3 주의) — config.ALARM_PRIORITY_RULES 의 코드 앞부분 규칙"""
    for prefix, level in ALARM_PRIORITY_RULES:
        if (code or "").startswith(prefix):
            return level
    return ALARM_PRIORITY_DEFAULT


def kind_of(r: dict) -> str:
    """알람 유형: VISION(비전 NG) / LIMIT(레시피 기준 이탈) / EQUIP(용접기 설비 알람)"""
    return "VISION" if r["machine_type"] == "VISION" else ("LIMIT" if parse_limit(r["alarm_code"]) else "EQUIP")


def guide_of(r: dict) -> list[str]:
    k = kind_of(r)
    if k == "VISION":
        return ALARM_GUIDES.get("VISION", [])
    if k == "LIMIT":
        return ALARM_GUIDES.get(f"LIM:{parse_limit(r['alarm_code'])[1]}") or ALARM_GUIDES.get("LIM", [])
    return ALARM_GUIDES.get((r["alarm_code"] or "").split(":")[0]) or ALARM_GUIDES.get("EQUIP", [])


def cleared_at(r: dict, part: int | None, lim: dict | None) -> str | None:
    """현장 복구(Cleared) 시각 — 조치 등록과 별개로 공정값이 정상으로 돌아온 시점 (DB에서 판단)
       · 기준 이탈: 이탈 이후 기준 범위 안으로 돌아온 첫 센서값 시각
       · 비전 NG : 같은 카메라·같은 파트의 다음 검사가 OK 인 시각
       · 설비 알람: PLC 해제 신호를 저장하는 곳이 없어 판단 불가 → None"""
    k = kind_of(r)
    if k == "LIMIT":
        return (lim or {}).get("recoveredAt")
    if k == "VISION" and part:
        q = query("""SELECT d.result, v.inspection_end_time AS t FROM t_vision_inspection_detail d
                     JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
                     JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
                     WHERE v.machine_id = ? AND w.sequence_no = ? AND v.inspection_end_time > ?
                     ORDER BY v.inspection_end_time""" + FIRST_ROW, (r["machine_id"], part, r["occurred_time"]))
        return q[0]["t"] if q and q[0]["result"] == "OK" else None
    return None


def parse_equip_part(code: str):
    """부위와 연결된 설비 알람 코드 'A-001:2' → 2 (부위 없는 설비 알람 'A-004' 는 None)"""
    p = (code or "").split(":")
    return int(p[1]) if len(p) == 2 and p[0].startswith("A-") and p[1].isdigit() else None


def expand(r: dict) -> list[dict]:
    """알람 1건 → 화면 행. 비전 알람은 NG 부위마다 1행(NG 부위가 없으면 1행)."""
    base = {**r, "status": status_of(r), "category": "비전" if r["machine_type"] == "VISION" else "용접",
            "priority": priority_of(r["alarm_code"])}
    if r["machine_type"] == "VISION" and r["lot_id"]:
        ng = query("""SELECT w.sequence_no AS part_no, d.defect_type FROM t_vision_inspection_detail d
                      JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
                      JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
                      WHERE v.lot_id = ? AND v.machine_id = ? AND d.result = 'NG' ORDER BY w.sequence_no""",
                   (r["lot_id"], r["machine_id"]))
        if ng:
            return [{**base, "part_no": n["part_no"], "defect_type": n["defect_type"],
                     "message": f"{n['part_no']}번 파트 {n['defect_type'] or 'NG'}"} for n in ng]
    lim = parse_limit(r["alarm_code"])
    part_no = lim[2] if lim else parse_equip_part(r["alarm_code"])
    return [{**base, "part_no": part_no, "defect_type": None, "message": r["alarm_desc"]}]


def alarm_rows(start: str, end: str, category: str = "all", part: int | None = None) -> list[dict]:
    """기간 내 알람을 발생 시각 내림차순으로. category: all / welder / vision."""
    sql, params = BASE_SQL + " WHERE a.occurred_time >= ? AND a.occurred_time < ?", [start, end]
    if category == "welder":
        sql += " AND m.machine_type = 'WELDER'"
    elif category == "vision":
        sql += " AND m.machine_type = 'VISION'"
    rows = [x for r in query(sql + " ORDER BY a.occurred_time DESC, a.alarm_id DESC", tuple(params)) for x in expand(r)]
    return [x for x in rows if x["part_no"] == part] if part else rows


def limit_info(r: dict, always: bool = False) -> dict | None:
    """기준 이탈 알람의 측정값 / 기준값 / 복구값(해결된 경우). 이탈 알람이 아니면 None."""
    lim = parse_limit(r["alarm_code"])
    if not lim or not r["lot_id"]:
        return None
    kind, code, part = lim
    sel = """FROM t_sensor_reading s JOIN m_parameter p ON p.parameter_id = s.parameter_id
             JOIN m_weld_point w ON w.weld_point_id = s.weld_point_id
             WHERE p.parameter_code = ? AND w.sequence_no = ?"""
    got = query(f"SELECT s.reading_value AS v, p.unit AS unit, s.weld_point_id AS wid, s.parameter_id AS pid {sel} AND s.lot_id = ? ORDER BY s.reading_id DESC{FIRST_ROW}",
                (code, part, r["lot_id"]))
    if not got:
        return None
    t = query("SELECT upper_limit, lower_limit FROM m_recipe_target WHERE recipe_id = ? AND weld_point_id = ? AND parameter_id = ?",
              (r["recipe_id"], got[0]["wid"], got[0]["pid"]))
    # recipe_id 없거나(t가 없어도) lot의 recipe로 재시도
    if not t and r.get("recipe_id"):
        t = query("SELECT upper_limit, lower_limit FROM m_recipe_target WHERE recipe_id = ? AND parameter_id = ?" + first_row_any("weld_point_id"),
                  (r["recipe_id"], got[0]["pid"]))
    out = {"measured": got[0]["v"], "unit": got[0]["unit"], "param": code, "recovered": None, "threshold": None, "limitUpper": None, "limitLower": None}
    if t:
        out["threshold"] = t[0]["upper_limit"] if kind == "HI" else t[0]["lower_limit"]
        out["limitUpper"], out["limitLower"] = t[0]["upper_limit"], t[0]["lower_limit"]
        out["isHigh"] = kind == "HI"
        if r["resolved_time"] or always:  # 이탈 이후 기준 범위 안으로 돌아온 첫 센서값 (always: 상세 화면 '현장 복구' 판단용)
            rec = query(f"SELECT s.reading_value AS v, s.reading_time AS t {sel} AND s.reading_time > ? AND s.reading_value BETWEEN ? AND ? ORDER BY s.reading_time{FIRST_ROW}",
                        (code, part, r["occurred_time"], t[0]["lower_limit"], t[0]["upper_limit"]))
            out["recovered"] = rec[0]["v"] if rec else None
            out["recoveredAt"] = rec[0]["t"] if rec else None
    else:
        # m_machine_spec 에서 설비 정격값으로 대체 (레시피 목표값이 없는 파라미터)
        spec = query("""SELECT s.rated_max AS upper_limit, s.rated_min AS lower_limit
                        FROM m_machine_spec s JOIN m_parameter p ON p.parameter_id = s.parameter_id
                        WHERE s.machine_id = ? AND p.parameter_code = ?
                        ORDER BY s.effective_from DESC""" + FIRST_ROW,
                     (got[0].get("wid") or r["machine_id"], code))
        if spec:
            out["threshold"] = spec[0]["upper_limit"] if kind == "HI" else spec[0]["lower_limit"]
            out["limitUpper"], out["limitLower"] = spec[0]["upper_limit"], spec[0]["lower_limit"]
        out["isHigh"] = kind == "HI"
    return out


def duration_text(occurred: str, resolved: str | None) -> str:
    """지속 시간: 진행 중이면 '진행중 · N분 경과', 해결됐으면 'N분'(1시간 이상은 시간·분)."""
    a = datetime.strptime(occurred, FMT)
    sec = max(0, int(((datetime.strptime(resolved, FMT) if resolved else datetime.now()) - a).total_seconds()))
    h, m = divmod(sec // 60, 60)
    body = f"{h}시간 {m}분" if h else (f"{m}분" if sec >= 60 else f"{sec}초")
    return f"진행중 · {body} 경과" if not resolved else body