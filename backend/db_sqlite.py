"""SQLite 드라이버. 기존 db.py 와 동작이 같다. (DB_BACKEND=sqlite 일 때 사용)"""
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "factory.db"


def query(sql: str, params: tuple = ()) -> list[dict]:
    """요청마다 연결을 열고 닫는다. SQL 값은 반드시 ? 바인딩으로 전달할 것(SQL 인젝션 방지)."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        return [dict(r) for r in conn.execute(sql, params).fetchall()]
    finally:
        conn.close()


def execute(sql: str, params: tuple = ()) -> int:
    """INSERT/UPDATE 1건을 실행하고 커밋한다. 마지막 rowid 반환."""
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        cur = conn.execute(sql, params)
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()
