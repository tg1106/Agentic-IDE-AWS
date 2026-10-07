# AGENTS.md

Guidance for AI coding agents working in this repository. Read `PRD.md` first for scope.

## Project
Browser IDE plus an agent that solves LeetCode-style problems in C++ or Python by writing code, running it in a sandbox against tests, and fixing failures. One user, one EC2 box.

## Layout
```
backend/app/main.py      FastAPI app: auth middleware, file API, /api/run, /api/agent/solve (SSE)
backend/app/sandbox.py   Docker-based runner for untrusted code
backend/app/agent.py     write -> run -> fix loop (async generator yielding events)
backend/app/llm.py       model gateway (OpenAI-compatible client)
backend/app/config.py    all settings, read from environment
frontend/index.html      single-file IDE (Monaco from CDN, no build step)
sandbox/Dockerfile       image with g++ and python3
scripts/                 run.sh, start_vllm.sh, idle_shutdown.sh
```

## Commands
- Install: `python3 -m venv .venv && . .venv/bin/activate && pip install -r backend/requirements.txt`
- Build sandbox image: `docker build -t ide-sandbox sandbox/`
- Run API: `scripts/run.sh` (serves http://127.0.0.1:8080)
- Run model server: `scripts/start_vllm.sh` (needs a GPU and vLLM)
- Quick check without a model: `curl -u admin:change-me -X POST localhost:8080/api/run -H 'Content-Type: application/json' -d '{"language":"python","code":"print(1+1)"}'`

## Conventions
- Python 3.11+, type hints on public functions, small functions, no new dependencies without a reason.
- Blocking work (Docker, file IO in handlers) stays out of the event loop: use `asyncio.to_thread`.
- Config comes from `config.py` and environment variables, never hard-coded values or secrets.
- Frontend stays one dependency-light HTML file. Use `textContent`, not `innerHTML`, for any user or model output.
- Keep the UI plain and legible: sentence case, clear error messages that say what to do next.

## Safety invariants (do not change without explicit approval)
1. Sandbox containers keep `--network none`, memory/CPU/pids limits, `--read-only`, `--cap-drop ALL`, `no-new-privileges`, and a non-root user.
2. User or model code is never executed outside `sandbox.run_code`.
3. Only `.cpp` and `.py` files are allowed in the workspace; names are validated by the `NAME` regex.
4. The server binds to `127.0.0.1`; all routes stay behind the auth middleware.
5. Never commit `.env`, credentials, or model weights.

## In-app agent contract
- The model replies with one fenced code block containing a full solution that reads stdin and writes stdout.
- Success means all provided tests pass (whitespace-insensitive comparison). With no tests the result is reported as unverified.
- Maximum attempts come from `AGENT_MAX_ITERS`. Failures (wrong output, error, timeout) are sent back to the model, at most three per round.
- Possible extensions: tool calling (`read_file`, `write_file`), model-generated extra tests, streaming tokens.

## Definition of done
- The change runs locally, and `/api/run` still reports compile errors, runtime errors, and timeouts correctly.
- No safety invariant is weakened.
- `README.md` and `PRD.md` are updated if behavior, setup, or scope changed.
