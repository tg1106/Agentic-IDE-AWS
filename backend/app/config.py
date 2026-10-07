import logging
import os
from pathlib import Path

log = logging.getLogger(__name__)

# ── Auth ──────────────────────────────────────────────────────────────────
AUTH_USER = os.getenv("IDE_USER", "admin")
AUTH_PASS = os.getenv("IDE_PASS", "change-me")

if AUTH_PASS == "change-me":
    log.warning(
        "IDE_PASS is still the insecure default. "
        "Set it in .env or via Secrets Manager before exposing the server."
    )

# ── LLM ───────────────────────────────────────────────────────────────────
LLM_BASE_URL   = os.getenv("LLM_BASE_URL",   "http://127.0.0.1:8000/v1")
LLM_API_KEY    = os.getenv("LLM_API_KEY",    "none")
LLM_MODEL      = os.getenv("LLM_MODEL",      "Qwen/Qwen2.5-Coder-7B-Instruct-AWQ")
LLM_MAX_TOKENS = int(os.getenv("LLM_MAX_TOKENS", "1500"))
LLM_TIMEOUT    = int(os.getenv("LLM_TIMEOUT",    "120"))

# ── Sandbox ───────────────────────────────────────────────────────────────
SANDBOX_IMAGE   = os.getenv("SANDBOX_IMAGE",   "ide-sandbox")
RUN_TIMEOUT     = int(os.getenv("RUN_TIMEOUT",     "5"))
COMPILE_TIMEOUT = int(os.getenv("COMPILE_TIMEOUT", "30"))

# ── Agent ─────────────────────────────────────────────────────────────────
MAX_ITERS = int(os.getenv("AGENT_MAX_ITERS", "5"))

# ── Idle shutdown ─────────────────────────────────────────────────────────
ACTIVITY_FILE = os.getenv("ACTIVITY_FILE", "/tmp/ide_last_activity")

# ── Local workspace fallback (used when S3 is not configured) ─────────────
WORKSPACE = Path(os.getenv("WORKSPACE_DIR", "workspace")).resolve()
WORKSPACE.mkdir(parents=True, exist_ok=True)

# ── AWS / S3 ──────────────────────────────────────────────────────────────
# When S3_BUCKET is set the app stores workspace files in S3.
# When unset it falls back to the local WORKSPACE directory (dev mode).
AWS_REGION = os.getenv("AWS_REGION", "ap-southeast-2")
S3_BUCKET  = os.getenv("S3_BUCKET",  "")   # empty → local fallback

# ── Aurora PostgreSQL ─────────────────────────────────────────────────────
# When DB_HOST is set the app logs every run to Aurora.
# When unset run-logging is silently skipped (dev mode).
DB_HOST = os.getenv("DB_HOST", "")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "agenticide")
DB_USER = os.getenv("DB_USER", "ideadmin")
DB_PASS = os.getenv("DB_PASS", "")
