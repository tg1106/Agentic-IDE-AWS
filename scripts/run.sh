#!/usr/bin/env bash
# Builds the React frontend (if needed) and starts the FastAPI backend on
# http://127.0.0.1:8080.  Reach it through an SSH tunnel — no inbound port
# other than SSH is required.
#
# Usage:
#   scripts/run.sh            # production mode
#   scripts/run.sh --reload   # uvicorn auto-reload on Python code changes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ── Safety: refuse to run as root ─────────────────────────────────────────
# Running as root passes --user 0:0 to Docker, defeating the non-root sandbox
# invariant documented in AGENTS.md.
if [ "$(id -u)" = "0" ]; then
  echo "ERROR: Do not run the IDE server as root." >&2
  echo "       Create a non-root user and run this script as that user." >&2
  exit 1
fi

# ── Load .env if present ──────────────────────────────────────────────────
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# ── Activate virtual environment if it exists ─────────────────────────────
if [ -f .venv/bin/activate ]; then
  # shellcheck disable=SC1091
  . .venv/bin/activate
elif ! command -v uvicorn >/dev/null 2>&1; then
  echo "ERROR: uvicorn not found and no .venv directory present." >&2
  echo "       python3 -m venv .venv && . .venv/bin/activate" >&2
  echo "       pip install -r backend/requirements.txt" >&2
  exit 1
fi

# ── Build React frontend ───────────────────────────────────────────────────
# Only rebuilds if dist/ is missing or source files are newer.
FRONTEND_DIR="$REPO_ROOT/frontend"
DIST_DIR="$FRONTEND_DIR/dist"

if [ ! -d "$DIST_DIR" ] || [ -n "$(find "$FRONTEND_DIR/src" -newer "$DIST_DIR/index.html" 2>/dev/null)" ]; then
  echo "Building React frontend…"
  if command -v npm >/dev/null 2>&1; then
    (cd "$FRONTEND_DIR" && npm run build)
  else
    echo "WARNING: npm not found — skipping frontend build." >&2
    echo "         Install Node.js 18+ and run: cd frontend && npm install && npm run build" >&2
  fi
else
  echo "Frontend is up to date (skip build)."
fi

# ── Build sandbox image if not already present ────────────────────────────
if ! docker image inspect ide-sandbox >/dev/null 2>&1; then
  echo "Building sandbox Docker image (first run only)…"
  docker build -t ide-sandbox sandbox/
fi

# ── Start server ──────────────────────────────────────────────────────────
# Single worker: SSE streaming + single-user load doesn't need more.
echo "Starting Agentic IDE on http://127.0.0.1:8080"
exec uvicorn app.main:app \
  --app-dir backend \
  --host 127.0.0.1 \
  --port 8080 \
  "$@"
