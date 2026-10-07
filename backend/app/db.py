"""Aurora PostgreSQL integration.

Provides:
  - init_db()   — called once at startup; creates the run_logs table if absent.
  - log_run()   — inserts one row after every sandbox execution.

When DB_HOST is not configured (local dev), both functions are no-ops so the
rest of the app works without any database.
"""
import logging
from datetime import datetime, timezone

log = logging.getLogger(__name__)

# psycopg2 is only required when Aurora is configured. Import lazily so local
# dev without the driver installed doesn't break on import.
_pool = None   # connection pool, initialised by init_db()
_table_ready = False   # set once run_logs exists; log_run retries init_db until then


def _get_pool():
    """Return the connection pool, creating it on first call."""
    global _pool
    if _pool is not None:
        return _pool

    from . import config
    if not config.DB_HOST:
        return None

    try:
        from psycopg2 import pool as pg_pool
        _pool = pg_pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=5,
            host=config.DB_HOST,
            port=config.DB_PORT,
            dbname=config.DB_NAME,
            user=config.DB_USER,
            password=config.DB_PASS,
            connect_timeout=30,   # allows Aurora to resume from auto-pause
            sslmode="require",   # Aurora always supports SSL
        )
        log.info("Aurora connection pool created (host=%s)", config.DB_HOST)
    except Exception as exc:
        log.error("Could not create Aurora connection pool: %s", exc)
        _pool = None

    return _pool


def init_db() -> None:
    """Create the run_logs table if it doesn't exist. Called at app startup."""
    global _table_ready
    pool = _get_pool()
    if pool is None:
        log.info("DB_HOST not set — Aurora logging disabled.")
        return

    create_sql = """
    CREATE TABLE IF NOT EXISTS run_logs (
        id          BIGSERIAL PRIMARY KEY,
        ts          TIMESTAMPTZ NOT NULL DEFAULT now(),
        language    VARCHAR(16)  NOT NULL,
        exit_code   INTEGER      NOT NULL,
        timed_out   BOOLEAN      NOT NULL,
        passed      BOOLEAN,          -- NULL when no tests were provided
        attempt     SMALLINT,         -- NULL for manual runs
        stdout_len  INTEGER      NOT NULL,
        stderr_len  INTEGER      NOT NULL
    );
    """
    conn = pool.getconn()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(create_sql)
        log.info("run_logs table ready.")
        _table_ready = True
    except Exception as exc:
        log.error("init_db failed: %s", exc)
    finally:
        pool.putconn(conn)


def log_run(
    *,
    language: str,
    exit_code: int,
    timed_out: bool,
    stdout: str,
    stderr: str,
    passed: bool | None = None,
    attempt: int | None = None,
) -> None:
    """Insert one run-log row. Silently skips if Aurora is not configured."""
    pool = _get_pool()
    if pool is None:
        return
    if not _table_ready:
        init_db()   # Aurora may not have been ready at app startup

    sql = """
    INSERT INTO run_logs
        (ts, language, exit_code, timed_out, passed, attempt, stdout_len, stderr_len)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """
    conn = pool.getconn()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(sql, (
                    datetime.now(timezone.utc),
                    language,
                    exit_code,
                    timed_out,
                    passed,
                    attempt,
                    len(stdout),
                    len(stderr),
                ))
    except Exception as exc:
        # Never let a logging failure break the user-facing response.
        log.warning("log_run failed (non-fatal): %s", exc)
    finally:
        pool.putconn(conn)
