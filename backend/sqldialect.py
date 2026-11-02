"""DB 마다 문법이 다른 SQL 조각을 한곳에 모은다. (SQLite / MSSQL)

원칙
- 라우터는 DB 이름을 직접 확인하지 않고, 여기의 조각만 SQL 에 끼워 넣는다.
- SQLite 일 때는 기존에 쓰던 SQL 과 글자 그대로 같은 조각이 나온다 (동작 변경 없음).
- 새 쿼리를 만들 때 LIMIT / julianday / strftime 을 직접 쓰지 말고 아래 함수를 쓴다.
"""
from backend.db import BACKEND

MSSQL = BACKEND == "mssql"


def limit_n(n: int) -> str:
    """쿼리 맨 뒤(또는 서브쿼리 닫는 괄호 앞)에 붙이는 'n건만'. 쿼리에 ORDER BY 가 이미 있어야 한다."""
    return f" OFFSET 0 ROWS FETCH NEXT {int(n)} ROWS ONLY" if MSSQL else f" LIMIT {int(n)}"


FIRST_ROW = limit_n(1)  # '정렬 후 첫 1건'
LIMIT_PARAM = " OFFSET 0 ROWS FETCH NEXT ? ROWS ONLY" if MSSQL else " LIMIT ?"  # 건수를 ? 로 받는 경우 (파라미터 1개)


def first_row_any(order_by: str) -> str:
    """ORDER BY 가 없는 쿼리에서 '아무 1건'. MSSQL 의 OFFSET/FETCH 는 ORDER BY 가 필수라서 order_by 를 붙인다.
    SQLite 에서는 기존과 같이 ' LIMIT 1' 만 붙는다."""
    return f" ORDER BY {order_by} OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY" if MSSQL else " LIMIT 1"


def paging(limit: int, offset: int) -> tuple[str, tuple]:
    """페이징: (SQL 조각, 파라미터). 파라미터 순서가 DB 마다 다르다 (SQLite: 건수,시작 / MSSQL: 시작,건수).
    ORDER BY 뒤에 붙인다."""
    if MSSQL:
        return " OFFSET ? ROWS FETCH NEXT ? ROWS ONLY", (offset, limit)
    return " LIMIT ? OFFSET ?", (limit, offset)


def age_seconds(expr: str) -> str:
    """'지금 - expr' 의 초 단위 경과 시간. expr 은 DB 에 저장된 시각(created_at 등)."""
    if MSSQL:
        return f"DATEDIFF(SECOND, {expr}, DATEADD(HOUR, 9, SYSUTCDATETIME()))"   # 한국 시간 기준(UTC+9)
    return f"(julianday('now', '+9 hours') - julianday({expr})) * 86400"   # 한국 시간 기준(UTC+9)


def seconds_between(start: str, end: str) -> str:
    """두 시각 컬럼(또는 식)의 차이(초). end - start."""
    if MSSQL:
        return f"DATEDIFF(SECOND, {start}, {end})"
    return f"strftime('%s', {end}) - strftime('%s', {start})"


def chunks(seq, n: int = 900):
    """IN (?, ?, ...) 목록을 나눈다. MSSQL 은 쿼리 1개에 파라미터를 2100개까지만 허용한다."""
    seq = list(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]