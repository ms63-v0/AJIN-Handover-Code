"""기준정보 관리 API (1차: 라인 / 공정 / 설비 / 용접부위 / 파라미터). ADMIN 전용, 삭제 없음."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from backend.db import execute, query
from backend.security import require_user

router = APIRouter(prefix="/api/admin", tags=["admin"])


def require_admin(user: dict = Depends(require_user)) -> dict:
    if user.get("role") != "ADMIN":
        raise HTTPException(status_code=403, detail="관리자(ADMIN)만 사용할 수 있습니다.")
    return user


def _exists(sql: str, params: tuple) -> bool:
    return bool(query(sql, params))


def _conflict(what: str):
    raise HTTPException(status_code=409, detail=f"이미 등록된 {what}입니다.")


# ── 라인 ─────────────────────────────────────────
class LineIn(BaseModel):
    line_code: str = Field(min_length=1, max_length=20)
    line_name: str = Field(min_length=1, max_length=100)
    use_yn: str = Field(default="Y", pattern="^[YN]$")


class LineUpd(BaseModel):
    line_name: str = Field(min_length=1, max_length=100)
    use_yn: str = Field(pattern="^[YN]$")


@router.post("/lines", status_code=201)
def create_line(body: LineIn, _=Depends(require_admin)):
    if _exists("SELECT 1 FROM m_line WHERE line_code = ?", (body.line_code,)):
        _conflict("라인 코드")
    execute("INSERT INTO m_line (line_code, line_name, use_yn) VALUES (?, ?, ?)",
            (body.line_code, body.line_name, body.use_yn))
    return {"ok": True}


@router.put("/lines/{line_id}")
def update_line(line_id: int, body: LineUpd, _=Depends(require_admin)):
    if not _exists("SELECT 1 FROM m_line WHERE line_id = ?", (line_id,)):
        raise HTTPException(status_code=404, detail="라인을 찾을 수 없습니다.")
    execute("UPDATE m_line SET line_name = ?, use_yn = ?, updated_at = ? WHERE line_id = ?",
            (body.line_name, body.use_yn, _now(), line_id))
    return {"ok": True}


# ── 공정 ─────────────────────────────────────────
class StationIn(BaseModel):
    line_id: int
    station_code: str = Field(min_length=1, max_length=20)
    station_name: str = Field(min_length=1, max_length=100)
    station_type: str = Field(min_length=1, max_length=20)
    sequence_no: int = Field(ge=1)
    use_yn: str = Field(default="Y", pattern="^[YN]$")


class StationUpd(BaseModel):
    station_name: str = Field(min_length=1, max_length=100)
    station_type: str = Field(min_length=1, max_length=20)
    sequence_no: int = Field(ge=1)
    use_yn: str = Field(pattern="^[YN]$")


@router.post("/stations", status_code=201)
def create_station(body: StationIn, _=Depends(require_admin)):
    if _exists("SELECT 1 FROM m_station WHERE station_code = ?", (body.station_code,)):
        _conflict("공정 코드")
    execute("""INSERT INTO m_station (line_id, station_code, station_name, station_type, sequence_no, use_yn)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (body.line_id, body.station_code, body.station_name, body.station_type, body.sequence_no, body.use_yn))
    return {"ok": True}


@router.put("/stations/{station_id}")
def update_station(station_id: int, body: StationUpd, _=Depends(require_admin)):
    if not _exists("SELECT 1 FROM m_station WHERE station_id = ?", (station_id,)):
        raise HTTPException(status_code=404, detail="공정을 찾을 수 없습니다.")
    execute("""UPDATE m_station SET station_name = ?, station_type = ?, sequence_no = ?, use_yn = ?, updated_at = ?
               WHERE station_id = ?""",
            (body.station_name, body.station_type, body.sequence_no, body.use_yn, _now(), station_id))
    return {"ok": True}


# ── 설비 ─────────────────────────────────────────
class MachineIn(BaseModel):
    station_id: int
    machine_code: str = Field(min_length=1, max_length=30)
    machine_name: str = Field(min_length=1, max_length=100)
    machine_type: str = Field(min_length=1, max_length=20)
    model_name: str = Field(min_length=1, max_length=100)
    manufacturer: str = Field(min_length=1, max_length=100)
    install_date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    use_yn: str = Field(default="Y", pattern="^[YN]$")


class MachineUpd(BaseModel):
    machine_name: str = Field(min_length=1, max_length=100)
    model_name: str = Field(min_length=1, max_length=100)
    manufacturer: str = Field(min_length=1, max_length=100)
    install_date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    use_yn: str = Field(pattern="^[YN]$")


@router.post("/machines", status_code=201)
def create_machine(body: MachineIn, _=Depends(require_admin)):
    if _exists("SELECT 1 FROM m_machine WHERE machine_code = ?", (body.machine_code,)):
        _conflict("설비 코드")
    execute("""INSERT INTO m_machine (station_id, machine_code, machine_name, machine_type, model_name,
                                       manufacturer, install_date, use_yn)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (body.station_id, body.machine_code, body.machine_name, body.machine_type, body.model_name,
             body.manufacturer, body.install_date, body.use_yn))
    return {"ok": True}


@router.put("/machines/{machine_id}")
def update_machine(machine_id: int, body: MachineUpd, _=Depends(require_admin)):
    if not _exists("SELECT 1 FROM m_machine WHERE machine_id = ?", (machine_id,)):
        raise HTTPException(status_code=404, detail="설비를 찾을 수 없습니다.")
    execute("""UPDATE m_machine SET machine_name = ?, model_name = ?, manufacturer = ?, install_date = ?,
                                    use_yn = ?, updated_at = ?
               WHERE machine_id = ?""",
            (body.machine_name, body.model_name, body.manufacturer, body.install_date,
             body.use_yn, _now(), machine_id))
    return {"ok": True}


# ── 용접부위 ─────────────────────────────────────
class WeldPointIn(BaseModel):
    weld_machine_id: int
    weld_point_code: str = Field(min_length=1, max_length=30)
    weld_type: str = Field(min_length=1, max_length=10)
    sequence_no: int = Field(ge=1)
    position_desc: str | None = Field(default=None, max_length=200)
    vision_machine_id: int | None = None
    use_yn: str = Field(default="Y", pattern="^[YN]$")


class WeldPointUpd(BaseModel):
    position_desc: str | None = Field(default=None, max_length=200)
    vision_machine_id: int | None = None
    use_yn: str = Field(pattern="^[YN]$")


@router.post("/weld-points", status_code=201)
def create_weld_point(body: WeldPointIn, _=Depends(require_admin)):
    if _exists("SELECT 1 FROM m_weld_point WHERE weld_point_code = ? AND weld_machine_id = ? AND sequence_no = ?",
               (body.weld_point_code, body.weld_machine_id, body.sequence_no)):
        _conflict("용접부위(코드·용접기·순번 조합)")
    execute("""INSERT INTO m_weld_point (weld_machine_id, weld_point_code, weld_type, sequence_no,
                                         position_desc, vision_machine_id, use_yn)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (body.weld_machine_id, body.weld_point_code, body.weld_type, body.sequence_no,
             body.position_desc, body.vision_machine_id, body.use_yn))
    return {"ok": True}


@router.put("/weld-points/{weld_point_id}")
def update_weld_point(weld_point_id: int, body: WeldPointUpd, _=Depends(require_admin)):
    if not _exists("SELECT 1 FROM m_weld_point WHERE weld_point_id = ?", (weld_point_id,)):
        raise HTTPException(status_code=404, detail="용접부위를 찾을 수 없습니다.")
    execute("UPDATE m_weld_point SET position_desc = ?, vision_machine_id = ?, use_yn = ?, updated_at = ? WHERE weld_point_id = ?",
            (body.position_desc, body.vision_machine_id, body.use_yn, _now(), weld_point_id))
    return {"ok": True}


# ── 파라미터 ─────────────────────────────────────
class ParamIn(BaseModel):
    parameter_code: str = Field(min_length=1, max_length=30)
    parameter_name: str = Field(min_length=1, max_length=100)
    unit: str = Field(min_length=1, max_length=20)
    data_type: str = Field(pattern="^(NUMERIC|INT|BOOLEAN|STRING)$")
    use_yn: str = Field(default="Y", pattern="^[YN]$")


class ParamUpd(BaseModel):
    parameter_name: str = Field(min_length=1, max_length=100)
    unit: str = Field(min_length=1, max_length=20)
    data_type: str = Field(pattern="^(NUMERIC|INT|BOOLEAN|STRING)$")
    use_yn: str = Field(pattern="^[YN]$")


@router.post("/parameters", status_code=201)
def create_parameter(body: ParamIn, _=Depends(require_admin)):
    if _exists("SELECT 1 FROM m_parameter WHERE parameter_code = ?", (body.parameter_code,)):
        _conflict("파라미터 코드")
    execute("INSERT INTO m_parameter (parameter_code, parameter_name, unit, data_type, use_yn) VALUES (?, ?, ?, ?, ?)",
            (body.parameter_code, body.parameter_name, body.unit, body.data_type, body.use_yn))
    return {"ok": True}


@router.put("/parameters/{parameter_id}")
def update_parameter(parameter_id: int, body: ParamUpd, _=Depends(require_admin)):
    if not _exists("SELECT 1 FROM m_parameter WHERE parameter_id = ?", (parameter_id,)):
        raise HTTPException(status_code=404, detail="파라미터를 찾을 수 없습니다.")
    execute("UPDATE m_parameter SET parameter_name = ?, unit = ?, data_type = ?, use_yn = ?, updated_at = ? WHERE parameter_id = ?",
            (body.parameter_name, body.unit, body.data_type, body.use_yn, _now(), parameter_id))
    return {"ok": True}


def _now() -> str:
    from datetime import datetime
    from backend.common import FMT
    return datetime.now().strftime(FMT)


# ── 조회 (기준정보 관리 화면용, ADMIN 전용) ───────────
@router.get("/weld-points")
def list_weld_points(_=Depends(require_admin)):
    return query("""SELECT w.*, m.machine_code, m.machine_name
                    FROM m_weld_point w
                    LEFT JOIN m_machine m ON m.machine_id = w.weld_machine_id
                    ORDER BY w.weld_machine_id, w.sequence_no""")


@router.get("/parameters")
def list_parameters(_=Depends(require_admin)):
    return query("SELECT * FROM m_parameter ORDER BY parameter_code")


# ── 제품 (레시피 드롭다운용, 사용 중인 것만) ─────────
@router.get("/products")
def list_products(_=Depends(require_admin)):
    return query("SELECT product_id, product_code, product_name FROM m_product WHERE use_yn = 'Y' ORDER BY product_code")


# ── 레시피 (헤더 + 타겟 표를 한 트랜잭션으로 저장) ──────
from backend.db import connect as _connect
from datetime import date as _date


class RecipeTargetIn(BaseModel):
    weld_point_id: int
    parameter_id: int
    target_value: float
    upper_limit: float
    lower_limit: float


class RecipeIn(BaseModel):
    product_id: int
    recipe_no: str = Field(min_length=1, max_length=30)
    effective_from: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    targets: list[RecipeTargetIn] = Field(min_length=1)


@router.get("/recipes")
def list_recipes(_=Depends(require_admin)):
    return query("""SELECT r.recipe_id, r.recipe_no, r.product_id, p.product_code, p.product_name,
                           r.version, r.effective_from, r.effective_to, r.use_yn
                    FROM m_recipe r JOIN m_product p ON p.product_id = r.product_id
                    ORDER BY r.product_id, r.version DESC""")


@router.get("/recipes/{recipe_id}/targets")
def list_recipe_targets(recipe_id: int, _=Depends(require_admin)):
    return query("""SELECT t.recipe_target_id, t.weld_point_id, w.weld_point_code,
                           t.parameter_id, p.parameter_code, p.parameter_name, p.unit,
                           t.target_value, t.upper_limit, t.lower_limit
                    FROM m_recipe_target t
                    JOIN m_weld_point w ON w.weld_point_id = t.weld_point_id
                    JOIN m_parameter p ON p.parameter_id = t.parameter_id
                    WHERE t.recipe_id = ?
                    ORDER BY w.sequence_no, p.parameter_code""", (recipe_id,))


@router.post("/recipes", status_code=201)
def create_recipe(body: RecipeIn, _=Depends(require_admin)):
    # 상하한 검증: 하한 <= 목표 <= 상한
    for t in body.targets:
        if not (t.lower_limit <= t.target_value <= t.upper_limit):
            raise HTTPException(status_code=422, detail="하한 ≤ 목표값 ≤ 상한 조건을 확인하세요.")

    now = _now()
    db = _connect()
    try:
        # 1) 같은 제품의 현재 유효 버전 찾기 → 새 버전 시작일 전날로 종료
        cur = db.execute("""SELECT recipe_id, version FROM m_recipe
                            WHERE product_id = ? AND effective_to IS NULL
                            ORDER BY version DESC""", (body.product_id,)).fetchall()
        last_version = 0
        for row in cur:
            last_version = max(last_version, row["version"] if isinstance(row, dict) else row[1])
            db.execute("UPDATE m_recipe SET effective_to = ?, updated_at = ? WHERE recipe_id = ?",
                       (body.effective_from, now, row["recipe_id"] if isinstance(row, dict) else row[0]))

        # 2) 새 헤더 저장 (버전 +1)
        new_id = db.execute("""INSERT INTO m_recipe (recipe_no, product_id, version, effective_from, use_yn, updated_at)
                               VALUES (?, ?, ?, ?, 'Y', ?)""",
                            (body.recipe_no, body.product_id, last_version + 1, body.effective_from, now)).lastrowid

        # 3) 타겟 표 저장
        for t in body.targets:
            db.execute("""INSERT INTO m_recipe_target (recipe_id, weld_point_id, parameter_id,
                                                       target_value, upper_limit, lower_limit, updated_at)
                          VALUES (?, ?, ?, ?, ?, ?, ?)""",
                       (new_id, t.weld_point_id, t.parameter_id, t.target_value, t.upper_limit, t.lower_limit, now))

        db.commit()
        return {"ok": True, "recipe_id": new_id, "version": last_version + 1}
    except Exception:
        db.rollback()
        raise


# ── 레시피 사용 여부 변경 (삭제 없음, updated_at 갱신) ──
class RecipeUseIn(BaseModel):
    use_yn: str = Field(pattern="^[YN]$")


@router.put("/recipes/{recipe_id}/use")
def set_recipe_use(recipe_id: int, body: RecipeUseIn, _=Depends(require_admin)):
    if not _exists("SELECT 1 FROM m_recipe WHERE recipe_id = ?", (recipe_id,)):
        raise HTTPException(status_code=404, detail="레시피를 찾을 수 없습니다.")
    execute("UPDATE m_recipe SET use_yn = ?, updated_at = ? WHERE recipe_id = ?",
            (body.use_yn, _now(), recipe_id))
    return {"ok": True}
