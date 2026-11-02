"""데이터 추출 API: POST /api/export/{weld|vision|lot|alarm}?format=pdf|xlsx|csv

· 파일 내용은 서버가 DB에서 직접 조회해 만든다(화면에 떠 있는 값을 받지 않음 → 데이터 무결성).
  화면 API 함수를 그대로 재사용하므로 화면 숫자와 파일 숫자가 항상 같다.
· 화면에서 받는 것은 '조회 조건'과 '차트 이미지'(흰 배경 · 2배 해상도로 다시 그린 PNG)뿐.
· 출력자/출력 일시/조건은 서버 로그에 남긴다(추출 이력 추적).
"""
from __future__ import annotations

import base64
import logging
import re
import statistics
ALL_ROWS = 10_000_000  # 내보내기는 페이지 나눔 없이 전체를 가져온다 (목록 함수는 파이썬에서 자르므로 DB 부담 없음)
from datetime import datetime
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field

from backend.common import DATE_RE, DT_RE, time_range
from backend.config import EXPORT_SYNC_LIMIT
from backend.db import query
from backend.sqldialect import FIRST_ROW
from backend.report import Col, Meta, Report, Table, total_rows, write_csv, write_pdf, write_xlsx
from backend.routers.alarm import list_alarms
from backend.routers.lots import list_lots, list_parts
from backend.routers.vision import vision as vision_api
from backend.routers.weld import weld as weld_api
from backend.security import require_user

router = APIRouter(prefix="/api/export", tags=["export"])
log = logging.getLogger("qms.export")

UNIT = {"C": "°C"}
DEC = {"WELD_CURRENT": 2, "WELD_PRESS": 3, "COOLANT_TEMP": 1, "WELD_TIME": 0}


def _unit(u):
    return UNIT.get(u, u)


def _line() -> str:
    r = query("SELECT line_code, line_name FROM m_line WHERE use_yn = 'Y' ORDER BY line_id" + FIRST_ROW)
    return f"{r[0]['line_code']} ({r[0]['line_name']})" if r else "-"


def _stamp(rng: dict) -> str:
    """파일명용 조회 구간: 202610140000-202610141337"""
    f = lambda s: re.sub(r"\D", "", s)[:12]   # noqa: E731
    return f"{f(rng['from'])}-{f(rng['to'])}"


def _part(p) -> str:
    return f"{p}번 파트" if p else "전체"


def _number(rows: list[list]) -> list[list]:
    for i, r in enumerate(rows, 1):
        r[0] = i
    return rows


def _chunks(ids, n=900):
    ids = list(ids)
    for i in range(0, len(ids), n):
        yield ids[i:i + n]


# ───────────────────────── ① 용접 현황 · 센서 트렌드 ─────────────────────────
def build_weld(f: dict) -> Report:
    params = f.get("parameters") or []
    d = weld_api(date=f.get("date"), dt_from=f.get("from"), dt_to=f.get("to"), part=f.get("part"), parameters=",".join(params) if params else None)
    day, lo_hi = d["date"], {}
    raw, summary, n_all, over_all, lots = [], [], 0, 0, set()
    for p in d["parameters"]:
        lo, hi, u, dec = p["limitLower"], p["limitUpper"], _unit(p["unit"]), DEC.get(p["code"], 2)
        lo_hi[p["code"]] = (lo, hi)
        allv = []
        for s in p["series"]:
            vals = [q["value"] for q in s["points"]]
            allv += vals
            over = sum(1 for v in vals if lo is not None and (v < lo or v > hi))
            if vals:
                summary.append([p["name"], u, f"{s['partNo']}번", len(vals), round(min(vals), dec), round(max(vals), dec),
                                round(statistics.fmean(vals), dec), round(statistics.pstdev(vals), dec + 1), lo, hi, over,
                                "NG" if over else "OK"])
            for q in s["points"]:
                bad = lo is not None and (q["value"] < lo or q["value"] > hi)
                raw.append([None, q["time"], q["lotNo"], s["partNo"], p["code"], p["name"], q["value"], u, lo, hi,
                            ("NG" if bad else "OK") if lo is not None else ""])
                lots.add(q["lotNo"])
        n_all += len(allv)
        over_all += sum(1 for v in allv if lo is not None and (v < lo or v > hi))
    raw.sort(key=lambda r: (r[1], r[3], r[4]))
    _number(raw)

    # LOT·파트별 측정값(가로형): 파라미터마다 열을 나누고 단위는 헤더에만
    pcols = [(p["code"], p["name"], _unit(p["unit"])) for p in d["parameters"]]
    wide: dict[tuple, dict] = {}
    for r in raw:
        key = (r[2], r[3])
        w = wide.setdefault(key, {"time": r[1], "vals": {}, "ng": False})
        w["vals"].setdefault(r[4], r[6])            # 같은 LOT·파트·파라미터의 첫 측정값
        w["ng"] |= r[10] == "NG"
    wide_rows = _number([[None, w["time"], k[0], k[1], *[w["vals"].get(c) for c, _, _ in pcols], "NG" if w["ng"] else "OK"]
                         for k, w in sorted(wide.items(), key=lambda kv: (kv[1]["time"], kv[0][1]))])

    al = list_alarms(date=f.get("date"), dt_from=f.get("from"), dt_to=f.get("to"), category="welder", part=f.get("part"),
                    priority=None, page=1, per_page=ALL_ROWS)["items"]
    alarm_rows = _number([[None, a["occurredAt"], a["partNo"], a["lotNo"], a["message"], a["verdict"] or "", a["status"], a["worker"] or ""]
                          for a in sorted(al, key=lambda a: a["occurredAt"])])

    names = ", ".join(p["name"] for p in d["parameters"]) or "-"
    return Report(
        title=f"[{_line().split(' ')[0]}] 용접 센서 트렌드 분석 리포트",
        file_stem=f"용접현황_센서트렌드_{_stamp(d['range'])}",
        filters=[("조회 기간", d["range"]["label"]), ("라인", _line()), ("파트", _part(f.get("part"))),
                 ("파라미터", names), ("샘플링", "Raw (측정 이벤트 단위 · 평균/구간화 없음)"), ("판정 기준", "레시피 상·하한 (m_recipe_target)")],
        kpis=[("측정 건수", f"{n_all:,}건"), ("기준 이탈", f"{over_all:,}건"),
              ("이탈률", f"{over_all / n_all * 100:.2f}%" if n_all else "-"), ("대상 LOT", f"{len(lots):,}개"),
              ("용접 알람", f"{len(al):,}건")],
        summary=Table("파라미터 통계 요약", [
            Col("파라미터", width=14), Col("단위", width=7), Col("파트", width=7), Col("측정 건수", kind="int", width=9),
            Col("최소", kind="num", width=9), Col("최대", kind="num", width=9), Col("평균", kind="num", width=9),
            Col("표준편차", kind="num", width=9), Col("하한(LCL)", kind="num", width=9), Col("상한(UCL)", kind="num", width=9),
            Col("이탈 건수", kind="int", width=9), Col("판정", kind="verdict", width=7)], summary),
        details=[
            Table("측정 Raw", [
                Col("No", kind="int", width=7), Col("측정 일시", kind="datetime", width=22), Col("LOT 번호", width=22),
                Col("파트", kind="int", width=6), Col("파라미터 코드", width=15), Col("파라미터", width=12),
                Col("측정값(PV)", kind="num", width=11), Col("단위", width=7), Col("하한(LCL)", kind="num", width=10),
                Col("상한(UCL)", kind="num", width=10), Col("판정", kind="verdict", width=7)], raw,
                note="측정값은 단위 열을 기준으로 해석합니다. 파라미터별 비교는 'LOT별 측정값' 시트를 사용하세요."),
            Table("LOT별 측정값", [
                Col("No", kind="int", width=7), Col("측정 일시", kind="datetime", width=22), Col("LOT 번호", width=22), Col("파트", kind="int", width=6),
                *[Col(n, unit=u, kind="num", dec=DEC.get(c, 2), width=12) for c, n, u in pcols], Col("판정", kind="verdict", width=7)], wide_rows),
            Table("용접 알람", [
                Col("No", kind="int", width=7), Col("발생 일시", kind="datetime", width=22), Col("파트", kind="int", width=6),
                Col("LOT 번호", width=22), Col("알람 내용", width=30), Col("LOT 판정", kind="verdict", width=9),
                Col("상태", width=9), Col("조치자", width=10)], alarm_rows),
        ],
    )


# ───────────────────────── ③ 비전 검사 ─────────────────────────
def build_vision(f: dict) -> Report:
    v = vision_api(date=f.get("date"), dt_from=f.get("from"), dt_to=f.get("to"), part=f.get("part"), result=None, page=1, per_page=ALL_ROWS)
    start, end = v["range"]["from"], v["range"]["to"]
    sql = """SELECT v.inspection_end_time AS t, l.lot_no, w.sequence_no AS part_no, m.machine_code AS camera,
                    d.result, d.defect_type, v.overall_result
             FROM t_vision_inspection_detail d
             JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
             JOIN t_lot l ON l.lot_id = v.lot_id
             JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
             LEFT JOIN m_machine m ON m.machine_id = v.machine_id
             WHERE v.inspection_end_time >= ? AND v.inspection_end_time < ?"""
    args: list = [start, end]
    if f.get("part"):
        sql += " AND w.sequence_no = ?"
        args.append(f["part"])
    if f.get("result"):
        sql += " AND d.result = ?"
        args.append(f["result"])
    rows = _number([[None, r["t"], r["lot_no"], r["part_no"], r["camera"] or "", r["result"], r["defect_type"] or "", r["overall_result"]]
                    for r in query(sql + " ORDER BY v.inspection_end_time, w.sequence_no", tuple(args))])
    k = v["kpi"]
    return Report(
        title=f"[{_line().split(' ')[0]}] 비전 검사 결과 성적서",
        file_stem=f"비전검사_결과_{_stamp(v['range'])}",
        filters=[("조회 기간", v["range"]["label"]), ("라인", _line()), ("파트", _part(f.get("part"))),
                 ("판정 필터", f.get("result") or "전체"), ("검사 단위", "LOT × 파트 (부위별 최근 검사)")],
        kpis=[("검사 수량", f"{k['inspectionCount']:,}건"), ("합격률", f"{k['okRate']}%"), ("불량률", f"{k['ngRate']}%"),
              ("추출 행 수", f"{len(rows):,}건")],
        summary=Table("불량 유형 분포 (상위 5개 + 기타)", [Col("불량 유형", width=20), Col("LOT 수", kind="int", width=10),
                                                    Col("비율", unit="%", kind="num", dec=1, width=10)],
                      [[x["label"], x["count"], x["ratio"]] for x in v["defectTypes"]]),
        details=[Table("검사 상세", [
            Col("No", kind="int", width=7), Col("검사 일시", kind="datetime", width=22), Col("LOT 번호", width=22),
            Col("파트", kind="int", width=6), Col("카메라", width=12), Col("파트 판정", kind="verdict", width=9),
            Col("불량 유형", width=16), Col("LOT 비전 판정", kind="verdict", width=11)], rows)],
    )


# ───────────────────────── ③ LOT 품질 이력 (추적성) ─────────────────────────
def build_lot(f: dict) -> Report:
    parts = [p["part_no"] for p in list_parts()]
    items = list_lots(date=f.get("date"), dt_from=f.get("from"), dt_to=f.get("to"), lot_no=f.get("lot_no"), part=f.get("part"), result=f.get("result"), page=1, per_page=ALL_ROWS)["items"]
    main = _number([[None, r["lot_end_time"], r["lot_no"], *[r["parts"].get(n) or r["parts"].get(str(n)) or "" for n in parts],
                     *[(r.get("visionParts") or {}).get(n) or (r.get("visionParts") or {}).get(str(n)) or "" for n in parts], r["final_result"]]
                    for r in sorted(items, key=lambda r: r["lot_end_time"])])

    # 파트별 측정값: 같은 LOT·파트·파라미터의 가장 최근 값 (Lot 상세 패널과 같은 규칙)
    prm = query("SELECT parameter_code, parameter_name, unit FROM m_parameter WHERE use_yn = 'Y' ORDER BY parameter_id")
    ids = {r["lot_id"]: r for r in items}
    vals: dict[tuple, dict] = {}
    defects: dict[tuple, str] = {}
    for chunk in _chunks(ids):
        marks = ",".join("?" * len(chunk))
        for x in query(f"""SELECT s.lot_id, w.sequence_no AS part_no, p.parameter_code AS code, s.reading_value AS v
                           FROM t_sensor_reading s JOIN m_weld_point w ON w.weld_point_id = s.weld_point_id
                           JOIN m_parameter p ON p.parameter_id = s.parameter_id
                           WHERE s.lot_id IN ({marks}) ORDER BY s.reading_time, s.reading_id""", tuple(chunk)):
            vals.setdefault((x["lot_id"], x["part_no"]), {})[x["code"]] = x["v"]
        for x in query(f"""SELECT v.lot_id, w.sequence_no AS part_no, d.defect_type FROM t_vision_inspection_detail d
                           JOIN t_vision_inspection v ON v.vision_inspection_id = d.vision_inspection_id
                           JOIN m_weld_point w ON w.weld_point_id = d.weld_point_id
                           WHERE v.lot_id IN ({marks}) ORDER BY v.inspection_end_time""", tuple(chunk)):
            defects[(x["lot_id"], x["part_no"])] = x["defect_type"] or ""
    per = []
    for r in sorted(items, key=lambda r: r["lot_end_time"]):
        for n in parts:
            m = vals.get((r["lot_id"], n), {})
            per.append([None, r["lot_no"], n, *[m.get(p["parameter_code"]) for p in prm],
                        r["parts"].get(n) or r["parts"].get(str(n)) or "",
                        (r.get("visionParts") or {}).get(n) or (r.get("visionParts") or {}).get(str(n)) or "",
                        defects.get((r["lot_id"], n), "")])
    _number(per)
    ok = sum(1 for r in items if r["final_result"] == "OK")
    ng = sum(1 for r in items if r["final_result"] == "NG")
    if f.get("from") or f.get("date"):
        s, e, _, label = time_range(f.get("date"), f.get("from"), f.get("to"))
        period, stem = label, _stamp({"from": s, "to": e})
    else:
        period, stem = "전체 기간", "전체"
    return Report(
        title=f"[{_line().split(' ')[0]}] LOT 품질 이력 (추적성) 리포트",
        file_stem=f"Lot조회_품질이력_{stem}",
        filters=[("조회 기준", "LOT 종료 일시 (진행 중 LOT 제외)"), ("조회 기간", period),
                 ("LOT 번호 검색", f.get("lot_no") or "-"), ("파트", _part(f.get("part"))),
                 ("판정 필터", f.get("result") or "전체"), ("라인", _line())],
        kpis=[("조회 LOT", f"{len(items):,}개"), ("종합 OK", f"{ok:,}개"), ("종합 NG", f"{ng:,}개"),
              ("불량률", f"{ng / len(items) * 100:.2f}%" if items else "-")],
        details=[
            Table("LOT 목록", [Col("No", kind="int", width=7), Col("종료 일시", kind="datetime", width=22), Col("LOT 번호", width=22),
                             *[Col(f"용접 {n}번", kind="verdict", width=9) for n in parts],
                             *[Col(f"비전 {n}번", kind="verdict", width=9) for n in parts],
                             Col("종합 판정", kind="verdict", width=10)], main),
            Table("파트별 측정값", [Col("No", kind="int", width=7), Col("LOT 번호", width=22), Col("파트", kind="int", width=6),
                                *[Col(p["parameter_name"], unit=_unit(p["unit"]), kind="num", dec=DEC.get(p["parameter_code"], 2), width=12) for p in prm],
                                Col("용접 판정", kind="verdict", width=9), Col("비전 판정", kind="verdict", width=9),
                                Col("불량 유형", width=16)], per),
        ],
    )


# ───────────────────────── 알람 이력 ─────────────────────────
def build_alarm(f: dict) -> Report:
    cat = f.get("category") or "all"
    d = list_alarms(date=f.get("date"), dt_from=f.get("from"), dt_to=f.get("to"), category=cat, part=f.get("part"), priority=None, page=1, per_page=ALL_ROWS)
    items = sorted(d["items"], key=lambda a: a["occurredAt"])
    ids = sorted({a["alarmId"] for a in items})
    ev, acts = {}, []
    for chunk in _chunks(ids):
        marks = ",".join("?" * len(chunk))
        for x in query(f"""SELECT a.alarm_id, a.resolved_time, m.machine_code, m.machine_type FROM t_alarm_event a
                           LEFT JOIN m_machine m ON m.machine_id = a.machine_id WHERE a.alarm_id IN ({marks})""", tuple(chunk)):
            ev[x["alarm_id"]] = x
        acts += query(f"SELECT alarm_id, worker_name, action_desc, action_time FROM t_alarm_action WHERE alarm_id IN ({marks})", tuple(chunk))
    kind = {"VISION": "비전", "WELDER": "용접"}
    PL = {1: "긴급", 2: "경고", 3: "주의"}
    rows = _number([[None, PL.get(a.get("priority"), ""), a["occurredAt"], kind.get((ev.get(a["alarmId"]) or {}).get("machine_type"), "설비"),
                     (ev.get(a["alarmId"]) or {}).get("machine_code") or "", a["partNo"], a["lotNo"] or "", a["message"],
                     a["verdict"] or "", a["status"], (ev.get(a["alarmId"]) or {}).get("resolved_time"), a["worker"] or ""] for a in items])
    act_rows = []
    for x in sorted(acts, key=lambda x: x["action_time"]):   # 저장 형식 '[구분|소속|사번|연락처] 내용' (연락처는 개인정보라 추출 제외)
        desc = x["action_desc"] or ""
        meta, body = (desc[1:desc.index("]")].split("|"), desc[desc.index("]") + 1:].strip()) if desc.startswith("[") and "]" in desc else ([""], desc)
        meta += [""] * (3 - len(meta))
        act_rows.append([None, x["alarm_id"], x["action_time"], x["worker_name"], meta[1], meta[2], meta[0], body])
    _number(act_rows)
    st = {s: sum(1 for a in items if a["status"] == s) for s in ("미해결", "조치중", "해결됨")}
    day = d["date"]
    return Report(
        title=f"[{_line().split(' ')[0]}] 알람 발생 · 조치 이력",
        file_stem=f"알람이력_{_stamp(d['range'])}",
        filters=[("조회 기간", d["range"]["label"]), ("구분", {"all": "전체", "welder": "용접", "vision": "비전"}[cat]),
                 ("파트", _part(f.get("part"))), ("라인", _line())],
        kpis=[("알람 건수", f"{len(items):,}건"), ("미해결", f"{st['미해결']:,}건"), ("조치중", f"{st['조치중']:,}건"),
              ("해결됨", f"{st['해결됨']:,}건")],
        details=[
            Table("알람 목록", [Col("No", kind="int", width=7), Col("등급", width=7), Col("발생 일시", kind="datetime", width=22), Col("구분", width=7),
                             Col("설비", width=12), Col("파트", kind="int", width=6), Col("LOT 번호", width=22), Col("알람 내용", width=28),
                             Col("LOT 판정", kind="verdict", width=9), Col("상태", width=8), Col("해결 일시", kind="datetime", width=22),
                             Col("조치자", width=10)], rows),
            Table("조치 이력", [Col("No", kind="int", width=7), Col("알람 ID", kind="int", width=9), Col("조치 일시", kind="datetime", width=22),
                             Col("작업자", width=10), Col("소속", width=14), Col("사번", width=10), Col("조치 구분", width=10),
                             Col("조치 내용", width=40)], act_rows),
        ],
    )


BUILDERS = {"weld": build_weld, "vision": build_vision, "lot": build_lot, "alarm": build_alarm}
MEDIA = {"pdf": "application/pdf", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "csv": "text/csv; charset=utf-8"}


class ChartIn(BaseModel):
    title: str = Field(max_length=120)
    image: str = Field(max_length=6_000_000)   # data:image/png;base64,...


class ExportBody(BaseModel):
    filters: dict = Field(default_factory=dict)
    charts: list[ChartIn] = Field(default_factory=list, max_length=8)


def _clean_filters(raw: dict) -> dict:
    """화면에서 받은 조건을 검증해서 허용된 값만 남긴다."""
    f: dict = {}
    if isinstance(raw.get("date"), str) and re.fullmatch(DATE_RE, raw["date"]):
        f["date"] = raw["date"]
    try:
        p = int(raw.get("part") or 0)
        if 1 <= p <= 99:
            f["part"] = p
    except (TypeError, ValueError):
        pass
    for k in ("from", "to"):   # 조회 구간 'YYYY-MM-DD HH:MM'
        if isinstance(raw.get(k), str) and re.fullmatch(DT_RE, raw[k]):
            f[k] = raw[k]
    if raw.get("result") in ("OK", "NG"):
        f["result"] = raw["result"]
    if raw.get("category") in ("all", "welder", "vision"):
        f["category"] = raw["category"]
    if isinstance(raw.get("lot_no"), str) and re.fullmatch(r"\d{1,50}", raw["lot_no"]):
        f["lot_no"] = raw["lot_no"]
    if isinstance(raw.get("parameters"), list):
        f["parameters"] = [c for c in raw["parameters"] if isinstance(c, str) and re.fullmatch(r"[A-Z_]{1,40}", c)][:20]
    return f


def _png(data_url: str) -> bytes | None:
    try:
        b = base64.b64decode(data_url.split(",", 1)[-1], validate=True)
        return b if b[:8] == b"\x89PNG\r\n\x1a\n" and len(b) <= 4_000_000 else None
    except ValueError:
        return None


@router.post("/{report}")
def export(body: ExportBody, report: str = Path(pattern="^(weld|vision|lot|alarm)$"),
           format: str = Query(..., pattern="^(pdf|xlsx|csv)$"), user: dict = Depends(require_user)):
    f = _clean_filters(body.filters)
    rep = BUILDERS[report](f)
    n = total_rows(rep)
    if format != "csv" and n > EXPORT_SYNC_LIMIT:   # 대용량은 CSV로 유도 (PDF/Excel 생성 시 서버 메모리 보호)
        raise HTTPException(413, f"추출 대상이 {n:,}건으로 즉시 추출 한도({EXPORT_SYNC_LIMIT:,}건)를 넘습니다. 조회 조건을 좁히거나 CSV로 추출하세요.")
    if format != "csv":
        rep.charts = [(c.title, png) for c in body.charts if (png := _png(c.image))]
    now = datetime.now()
    login = query("SELECT login_id FROM m_user WHERE user_id = ?", (user.get("uid"),))
    meta = Meta(user.get("name", "-"), login[0]["login_id"] if login else "-", now)
    content = write_csv(rep) if format == "csv" else write_xlsx(rep, meta) if format == "xlsx" else write_pdf(rep, meta)
    name = f"{rep.file_stem}_출력{now:%Y%m%d-%H%M%S}.{format}"   # 예: 용접현황_센서트렌드_20261014_출력20261014-133722.xlsx (조회일 + 출력 시각)
    log.info("EXPORT report=%s format=%s rows=%d user=%s filters=%s", report, format, n, meta.login_id, f)
    return Response(content, media_type=MEDIA[format], headers={
        "Content-Disposition": f"attachment; filename=\"qms_export.{format}\"; filename*=UTF-8''{quote(name)}",
        "Cache-Control": "no-store"})
