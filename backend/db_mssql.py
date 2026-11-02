"""MSSQL 드라이버 (pyodbc). DB_BACKEND=mssql 일 때 사용한다.

설정은 .env 또는 환경변수에서 읽는다:
  MSSQL_SERVER    서버 주소 (예: localhost,1433  또는  192.168.1.100,1433)
  MSSQL_DATABASE  DB 이름 (예: factory_db)
  MSSQL_USER      로그인 계정
  MSSQL_PASSWORD  비밀번호
  MSSQL_DRIVER    ODBC 드라이버 이름 (기본: ODBC Driver 18 for SQL Server)
  MSSQL_TRUST_CERT  yes 이면 서버 인증서 검사를 건너뜀 (테스트 서버 전용, 기본: no)
  MSSQL_CHAR_ENCODING  VARCHAR 한글이 깨져 보일 때만 지정 (예: Windows 에서 cp949). 기본: 지정 안 함

결과 형식은 SQLite 드라이버와 같게 맞춘다:
  - datetime  → 'YYYY-MM-DD HH:MM:SS' 문자열 (밀리초 버림, SQLite 저장값과 같은 형식)
  - date      → 'YYYY-MM-DD' 문자열
  - Decimal   → float
  - 행        → dict (컬럼명 키)
"""
import os
from datetime import date, datetime
from decimal import Decimal

_TS_FMT = "%Y-%m-%d %H:%M:%S"
_DATE_FMT = "%Y-%m-%d"


def _conn_str() -> str:
    server = os.getenv("MSSQL_SERVER", "")
    database = os.getenv("MSSQL_DATABASE", "")
    user = os.getenv("MSSQL_USER", "")
    password = os.getenv("MSSQL_PASSWORD", "")
    driver = os.getenv("MSSQL_DRIVER", "ODBC Driver 18 for SQL Server")
    trust = os.getenv("MSSQL_TRUST_CERT", "no").strip().lower() == "yes"
    missing = [k for k, v in (("MSSQL_SERVER", server), ("MSSQL_DATABASE", database),
                              ("MSSQL_USER", user), ("MSSQL_PASSWORD", password)) if not v]
    if missing:
        raise RuntimeError(f".env 에 다음 값이 필요합니다: {', '.join(missing)}")
    return (f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};"
            f"UID={user};PWD={password};TrustServerCertificate={'yes' if trust else 'no'};")


def _connect():
    conn_str = _conn_str()  # 설정 누락을 먼저 알려준다
    import pyodbc           # 지연 import: SQLite 모드에서는 pyodbc 가 없어도 된다
    conn = pyodbc.connect(conn_str, autocommit=False, timeout=10)
    enc = os.getenv("MSSQL_CHAR_ENCODING", "").strip()
    if enc:  # VARCHAR(비유니코드) 컬럼을 읽을 때 쓰는 문자 인코딩
        conn.setdecoding(pyodbc.SQL_CHAR, encoding=enc)
    return conn


def _convert(value):
    if isinstance(value, datetime):          # datetime 은 date 의 하위 클래스라서 먼저 검사한다
        return value.strftime(_TS_FMT)
    if isinstance(value, date):               # DATE 컬럼 (설치일, 정격 적용일) → 'YYYY-MM-DD'
        return value.strftime(_DATE_FMT)
    if isinstance(value, Decimal):
        return float(value)
    return value


def _rows_to_dicts(cur) -> list[dict]:
    cols = [c[0] for c in cur.description]
    return [{c: _convert(v) for c, v in zip(cols, row)} for row in cur.fetchall()]


def query(sql: str, params: tuple = ()) -> list[dict]:
    """SELECT 실행. 값은 ? 바인딩으로 전달한다."""
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        return _rows_to_dicts(cur) if cur.description else []
    finally:
        conn.close()


def execute(sql: str, params: tuple = ()) -> int | None:
    """INSERT/UPDATE/DELETE 1건을 실행하고 커밋한다.
    INSERT 이면 같은 연결에서 방금 생성된 IDENTITY 값을 돌려준다 (SQLite 의 lastrowid 와 같은 역할)."""
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        new_id = None
        if sql.lstrip().upper().startswith("INSERT"):
            cur.execute("SELECT CAST(SCOPE_IDENTITY() AS BIGINT)")
            row = cur.fetchone()
            new_id = int(row[0]) if row and row[0] is not None else None
        conn.commit()
        return new_id
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
