"""DB 연결 스위치. 라우터는 여기의 query()/execute()만 사용한다 (기존과 동일).

DB_BACKEND 값으로 드라이버를 고른다. 값은 프로젝트 최상위의 .env 또는 환경변수에서 읽는다.
  DB_BACKEND=sqlite   → 로컬 SQLite 파일 (기본값, 개발·테스트)
  DB_BACKEND=mssql    → 실 DB (MSSQL, pyodbc). 연결 정보는 .env 의 MSSQL_* 값.
알 수 없는 값이면 시작 시 오류로 멈춘다 (조용히 SQLite로 떨어지지 않도록).
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load_env(path: Path) -> None:
    """.env 를 읽어 환경변수로 설정한다. 이미 설정된 환경변수는 덮어쓰지 않는다. 외부 패키지 불필요."""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_env(ROOT / ".env")

BACKEND = os.getenv("DB_BACKEND", "sqlite").strip().lower()

if BACKEND == "sqlite":
    from backend.db_sqlite import DB_PATH, execute, query
elif BACKEND == "mssql":
    from backend.db_mssql import execute, query
    DB_PATH = None  # MSSQL 에는 파일 경로가 없다 (main.py 헬스 체크는 DB_PATH 가 None 이면 서버 이름을 표시)
else:
    raise RuntimeError(f"DB_BACKEND 값이 올바르지 않습니다: {BACKEND!r} (sqlite 또는 mssql)")

class _Row:
    """MSSQL 결과 행: 번호(row[0])와 이름(row['col']) 둘 다로 읽는다 (sqlite3.Row 와 같은 사용법)."""
    __slots__ = ("_names", "_vals")

    def __init__(self, names, vals):
        self._names, self._vals = names, tuple(vals)

    def __getitem__(self, k):
        return self._vals[k] if isinstance(k, int) else self._vals[self._names.index(k)]

    def __iter__(self):
        return iter(self._vals)

    def __len__(self):
        return len(self._vals)

    def keys(self):
        return list(self._names)


class Session:
    """쓰기 작업(시뮬레이터 등)용 연결. SQLite / MSSQL 어느 쪽이든 같은 방식으로 쓴다.
    사용: db = connect(); db.execute(sql, params).fetchone(); db.execute(INSERT).lastrowid; db.commit()
    """

    def __init__(self):
        if BACKEND == "mssql":
            from backend.db_mssql import _connect, _convert
            self._conn, self._mssql, self._convert = _connect(), True, _convert
        else:
            import sqlite3
            self._conn = sqlite3.connect(DB_PATH, timeout=10)
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA foreign_keys = ON")
            self._mssql = False
        self._rows, self._pos, self._lastrowid = [], 0, None

    def execute(self, sql, params=()):
        if self._mssql:
            cur = self._conn.cursor()
            self._lastrowid = None
            if sql.lstrip().upper().startswith("INSERT"):
                # SCOPE_IDENTITY() 는 같은 실행 묶음(batch) 안의 값만 돌려준다.
                # 그래서 INSERT 와 조회를 한 번에 실행하고, 결과 묶음을 넘겨서 값을 읽는다.
                cur.execute(sql.rstrip().rstrip(";") + "; SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS new_id", tuple(params))
                while cur.description is None and cur.nextset():
                    pass
                row = cur.fetchone() if cur.description else None
                self._lastrowid = int(row[0]) if row and row[0] is not None else None
                self._rows = []
            else:
                cur.execute(sql, tuple(params))
                if cur.description:
                    names = [c[0] for c in cur.description]
                    self._rows = [_Row(names, [self._convert(v) for v in r]) for r in cur.fetchall()]
                else:
                    self._rows = []
        else:
            cur = self._conn.execute(sql, params)
            self._rows = cur.fetchall() if cur.description else []
            self._lastrowid = cur.lastrowid
        self._pos = 0
        return self

    def fetchone(self):
        if self._pos < len(self._rows):
            self._pos += 1
            return self._rows[self._pos - 1]
        return None

    def fetchall(self):
        rest = self._rows[self._pos:]
        self._pos = len(self._rows)
        return rest

    def __iter__(self):
        return iter(self.fetchall())

    @property
    def lastrowid(self):
        return self._lastrowid

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        self._conn.close()


def connect() -> Session:
    """현재 DB_BACKEND 에 맞는 쓰기 연결을 만든다."""
    return Session()


__all__ = ["BACKEND", "DB_PATH", "query", "execute", "connect"]
