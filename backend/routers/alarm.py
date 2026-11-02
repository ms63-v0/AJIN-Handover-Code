"""알람 이력 조회 API. 정의서 '알람 이력 조회' 시트: 목록 / 상세 / 조치 등록."""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from backend.alarms import BASE_SQL, PRIORITY_LABEL, alarm_rows, cleared_at, duration_text, expand, guide_of, kind_of, limit_info, parse_limit
from backend.common import DATE_RE, DT_RE, FMT, time_range
from backend.config import ACTION_CATEGORIES
from backend.db import execute, query
from backend.security import require_user

router = APIRouter(prefix="/api/alarms", tags=["alarms"])


@router.get("")
def list_alarms(
    date: str | None = Query(None, pattern=DATE_RE),
    dt_from: str | None = Query(None, alias="from", pattern=DT_RE, description="시작 일시 YYYY-MM-DD HH:MM"),
    dt_to: str | None = Query(None, alias="to", pattern=DT_RE, description="종료 일시(생략 = 현재까지)"),
    category: str = Query("all", pattern="^(all|welder|vision)$"),
    part: int | None = Query(None, ge=1, le=99),
    priority: int | None = Query(None, ge=1, le=3, description="우선순위 필터 (1 긴급 / 2 경고 / 3 주의)"),
    page: int = Query(1, ge=1, description="페이지 번호"),
    per_page: int = Query(50, ge=10, le=100, description="페이지당 건수"),
):
    import re as _re
    start, end, day, label = time_range(date, dt_from, dt_to)
    rows = alarm_rows(start, end, category, part)
    all_items = [{"key": f"{r['alarm_id']}-{r['part_no'] or 0}", "alarmId": r["alarm_id"], "partNo": r["part_no"], "occurredAt": r["occurred_time"],
                  "resolvedAt": r["resolved_time"], "priority": r["priority"], "category": r["category"], "machine": r["machine_code"],
                  "verdict": r["final_result"], "message": r["message"], "lotNo": r["lot_no"], "worker": r["worker"], "status": r["status"], "acked": bool(r.get("ack_time")), "ackAt": r.get("ack_time"), "ackBy": r.get("ack_user")} for r in rows]

    # KPI: 전체 건수 기반 집계 (페이지/우선순위 필터 적용 전)
    by_prio = {1: 0, 2: 0, 3: 0}
    for r in all_items:
        by_prio[r["priority"]] = by_prio.get(r["priority"], 0) + 1
    open_cnt = sum(1 for r in all_items if r["status"] != "해결됨")
    done = [r for r in all_items if r["resolvedAt"]]
    if done:
        total_ms = sum(
            (datetime.strptime(r["resolvedAt"], "%Y-%m-%d %H:%M:%S") - datetime.strptime(r["occurredAt"], "%Y-%m-%d %H:%M:%S")).total_seconds()
            for r in done
        )
        mttr = total_ms / len(done) / 60
    else:
        mttr = None
    msg_cnt: dict = {}
    for r in all_items:
        k = _re.sub(r"^\d+번 파트 ", "", r["message"])
        msg_cnt[k] = msg_cnt.get(k, 0) + 1
    top = sorted(msg_cnt.items(), key=lambda x: -x[1])[0] if msg_cnt else None
    unacked = sum(1 for r in all_items if not r["acked"])   # 미확인: 확인 버튼을 아직 누르지 않은 알람 (기간 내)
    kpi = {"byPriority": by_prio, "open": open_cnt, "unacked": unacked, "mttr": mttr,
           "top": {"message": top[0], "count": top[1]} if top else None}

    # 우선순위 필터 (KPI 집계 후 적용)
    if priority:
        all_items = [r for r in all_items if r["priority"] == priority]

    total = len(all_items)
    offset = (page - 1) * per_page
    items = all_items[offset: offset + per_page]

    return {"date": day, "range": {"from": start, "to": end, "label": label},
            "total": total, "page": page, "per_page": per_page, "items": items, "kpi": kpi}


@router.get("/unresolved")
def unresolved(limit: int = Query(8, ge=1, le=50)):
    """헤더 알림: 미해결(조치 미등록) 건수 · 미확인(확인 버튼 전) 건수 · 최근 목록. 두 값은 의미가 다르다."""
    rows = query(BASE_SQL + " WHERE a.resolved_time IS NULL ORDER BY a.occurred_time DESC, a.alarm_id DESC")
    items = [x for r in rows for x in expand(r)]
    unacked = sum(1 for r in rows if not r["ack_time"] for _ in expand(r))
    return {"count": len(items), "unacked": unacked,
            "items": [{"alarmId": r["alarm_id"], "partNo": r["part_no"], "time": r["occurred_time"], "category": r["category"],
                       "message": r["message"], "status": r["status"], "acked": bool(r["ack_time"])} for r in items[:limit]]}


ACK_ROLES = ("OPERATOR", "MANAGER", "ADMIN")


@router.post("/{alarm_id}/ack")
def ack_alarm(alarm_id: int, user: dict = Depends(require_user)):
    """알람 확인: 작업자가 알람을 봤다는 표시. 해결(조치 등록)과 별개. 이미 확인된 알람은 처음 확인자·시각을 유지한다."""
    if user.get("role") not in ACK_ROLES:
        raise HTTPException(status_code=403, detail="알람 확인 권한이 없습니다.")
    if not query("SELECT 1 FROM t_alarm_event WHERE alarm_id = ?", (alarm_id,)):
        raise HTTPException(status_code=404, detail="Alarm not found")
    now_str = datetime.now().strftime(FMT)
    execute("UPDATE t_alarm_event SET ack_time = COALESCE(ack_time, ?), ack_user_id = COALESCE(ack_user_id, ?) WHERE alarm_id = ?",
            (now_str, user["uid"], alarm_id))
    row = query("SELECT a.ack_time, u.user_name AS ack_user FROM t_alarm_event a LEFT JOIN m_user u ON u.user_id = a.ack_user_id WHERE a.alarm_id = ?", (alarm_id,))[0]
    return {"alarmId": alarm_id, "ackAt": row["ack_time"], "ackBy": row["ack_user"]}


def build_detail(alarm_id: int, part: int | None) -> dict:
    base = query(BASE_SQL + " WHERE a.alarm_id = ?", (alarm_id,))
    if not base:
        raise HTTPException(status_code=404, detail="Alarm not found")
    rows = expand(base[0])
    r = next((x for x in rows if x["part_no"] == part), rows[0])
    acts = query("""SELECT x.action_id, x.worker_name, x.action_desc, x.action_time, u.department FROM t_alarm_action x
                    LEFT JOIN m_user u ON u.user_name = x.worker_name WHERE x.alarm_id = ? ORDER BY x.action_time DESC, x.action_id DESC""", (alarm_id,))
    history = []
    for a in acts:  # 저장 형식 '[구분|소속|사번|연락처] 내용' (이전 형식 '[구분] 내용' 도 읽는다)
        d = a["action_desc"]
        meta, body = (d[1:d.index("]")].split("|"), d[d.index("]") + 1:].strip()) if d.startswith("[") and "]" in d else (["기타"], d)
        meta += [""] * (4 - len(meta))
        history.append({"worker": a["worker_name"], "department": meta[1] or a["department"], "employeeNo": meta[2], "phone": meta[3],
                        "category": meta[0] or "기타", "content": body, "time": a["action_time"]})
    machine = f"{r['machine_code']} ({r['part_no']}번 파트)" if r["part_no"] else r["machine_code"]
    kind, lim = kind_of(r), limit_info(r, always=True)
    clr = cleared_at(r, r["part_no"], lim)
    # 상세 내용: 알람 유형별로 '무엇이 어디서 어떻게' 를 구조화 (DB 원문 alarm_desc 는 맨 아래 참고로)
    if kind == "VISION":
        facts = [("알람 유형", "비전 검사 불량 (NG)"), ("불량 유형", r.get("defect_type") or "-"),
                 ("검사 부위", f"{r['part_no']}번 파트" if r["part_no"] else "-"), ("검사 카메라", r["machine_code"])]
    elif kind == "LIMIT":
        k, code, _ = parse_limit(r["alarm_code"])
        pn = query("SELECT parameter_name FROM m_parameter WHERE parameter_code = ?", (code,))
        facts = [("알람 유형", "레시피 기준 이탈"), ("파라미터", pn[0]["parameter_name"] if pn else code),
                 ("이탈 방향", "상한(UCL) 초과" if k == "HI" else "하한(LCL) 미만"), ("용접 부위", f"{r['part_no']}번 파트")]
    else:
        facts = [("알람 유형", "용접기 설비 알람 (PLC)"), ("알람 코드", (r["alarm_code"] or "").split(":")[0]),
                 ("신호 출처", r.get("source_device") or "-"), ("관련 부위", f"{r['part_no']}번 파트" if r["part_no"] else "설비 전체")]
    return {
        "alarmId": alarm_id, "partNo": r["part_no"], "lotNo": r["lot_no"], "category": r["category"], "status": r["status"],
        "occurredAt": r["occurred_time"], "resolvedAt": r["resolved_time"], "machine": machine, "message": r["message"],
        "description": r["alarm_desc"], "duration": duration_text(r["occurred_time"], r["resolved_time"]),
        "priority": r["priority"], "priorityLabel": PRIORITY_LABEL[r["priority"]], "kind": kind,
        "acked": bool(r["ack_time"]), "ackAt": r["ack_time"], "ackBy": r["ack_user"],
        "facts": [{"label": a, "value": b} for a, b in facts], "guide": guide_of(r), "clearedAt": clr,
        # ISA-18.2 생애주기 (DB 근거가 있는 단계만): 발생 → 현장 복구 → 조치 완료(종결)
        "steps": [{"name": "발생", "done": True, "time": r["occurred_time"]},
                  {"name": "현장 복구", "done": bool(clr), "time": clr, "na": kind == "EQUIP"},
                  {"name": "조치 완료", "done": bool(r["resolved_time"]), "time": r["resolved_time"]}],
        "limit": lim, "actions": history, "canAct": not r["resolved_time"],
    }


@router.get("/{alarm_id}")
def alarm_detail(alarm_id: int, part: int | None = Query(None, ge=0, le=99)):
    return build_detail(alarm_id, part or None)


class ActionBody(BaseModel):
    category: str
    content: str = Field(min_length=1, max_length=400)
    worker_name: str = Field(min_length=1, max_length=50)    # 작업자 이름: 로그인 사용자가 아니라 직접 입력
    department: str = Field(min_length=1, max_length=40)
    employee_no: str = Field(min_length=1, max_length=20)
    phone: str | None = Field(None, max_length=20)
    part: int | None = None


def _clean(v: str | None) -> str:
    """구분자(| ] 줄바꿈)를 제거해 저장 형식이 깨지지 않게 한다."""
    return " ".join((v or "").replace("|", " ").replace("]", " ").replace("[", " ").split())


@router.post("/{alarm_id}/actions")
def register_action(alarm_id: int, body: ActionBody, user: dict = Depends(require_user)):
    """조치 등록: t_alarm_action INSERT 후 t_alarm_event.resolved_time 을 현재 시각으로 채운다 → 상태 = 해결됨.
    소속·사번·연락처는 전용 컬럼이 없어 action_desc 앞 '[구분|소속|사번|연락처]' 에 함께 저장한다(컬럼이 생기면 분리)."""
    if body.category not in ACTION_CATEGORIES:
        raise HTTPException(status_code=422, detail="조치 구분이 올바르지 않습니다.")
    if not body.content.strip():
        raise HTTPException(status_code=422, detail="조치 내용을 입력하세요.")
    if not query("SELECT 1 FROM t_alarm_event WHERE alarm_id = ?", (alarm_id,)):
        raise HTTPException(status_code=404, detail="Alarm not found")
    name = _clean(body.worker_name)
    if not name or not _clean(body.department) or not _clean(body.employee_no):
        raise HTTPException(status_code=422, detail="작업자 이름·소속·사번을 입력하세요.")
    meta = "|".join([body.category, _clean(body.department), _clean(body.employee_no), _clean(body.phone)])
    now_str = datetime.now().strftime(FMT)
    execute("INSERT INTO t_alarm_action (alarm_id, worker_name, action_desc, action_time) VALUES (?, ?, ?, ?)",
            (alarm_id, name, f"[{meta}] {body.content.strip()}", now_str))
    # 조치 등록 = 해결됨: resolved_time 을 현재 시각으로 채운다
    execute("UPDATE t_alarm_event SET resolved_time = ?, ack_time = COALESCE(ack_time, ?), ack_user_id = COALESCE(ack_user_id, ?) WHERE alarm_id = ? AND resolved_time IS NULL",
            (now_str, now_str, user["uid"], alarm_id))
    return build_detail(alarm_id, body.part)