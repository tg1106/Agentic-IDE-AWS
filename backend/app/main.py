import asyncio
import json
import re
import secrets
from base64 import b64decode
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import agent, config, db, sandbox

app = FastAPI(title="Agentic IDE")
NAME  = re.compile(r"^[\w\-]{1,64}\.(cpp|py)$")
LANGS = ("cpp", "python")

# ── S3 client (module-level singleton; None when running locally) ─────────
_s3 = boto3.client("s3", region_name=config.AWS_REGION) if config.S3_BUCKET else None


# ── Startup ───────────────────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    """Initialise Aurora run_logs table (no-op when DB_HOST is unset)."""
    await asyncio.to_thread(db.init_db)


# ── Auth middleware ───────────────────────────────────────────────────────
@app.middleware("http")
async def guard(request: Request, call_next):
    """HTTP Basic Auth for every route + activity stamp for idle-shutdown."""
    try:
        raw = request.headers.get("authorization", "")[6:]
        u, _, p = b64decode(raw).decode().partition(":")
    except Exception:
        u = p = ""

    ok = (
        secrets.compare_digest(u.encode(), config.AUTH_USER.encode())
        and secrets.compare_digest(p.encode(), config.AUTH_PASS.encode())
    )
    if not ok:
        return Response(
            status_code=401,
            headers={"WWW-Authenticate": 'Basic realm="ide"'},
        )
    Path(config.ACTIVITY_FILE).touch()
    return await call_next(request)


# ── Helpers ───────────────────────────────────────────────────────────────
def _validate_name(name: str) -> str:
    """Raise 400 if name is invalid, otherwise return it."""
    if not NAME.match(name):
        raise HTTPException(
            400,
            "File names must use letters, digits, _ or - and end in .cpp or .py",
        )
    return name


# ── S3 helpers ────────────────────────────────────────────────────────────
def _s3_list() -> list[str]:
    resp = _s3.list_objects_v2(Bucket=config.S3_BUCKET)
    return sorted(
        obj["Key"] for obj in resp.get("Contents", [])
        if NAME.match(obj["Key"])
    )

def _s3_get(name: str) -> str:
    try:
        obj = _s3.get_object(Bucket=config.S3_BUCKET, Key=name)
        return obj["Body"].read().decode()
    except ClientError as e:
        if e.response["Error"]["Code"] in ("NoSuchKey", "404"):
            raise HTTPException(404, "File not found")
        raise HTTPException(500, str(e))

def _s3_put(name: str, content: str) -> None:
    _s3.put_object(Bucket=config.S3_BUCKET, Key=name, Body=content.encode())

def _s3_delete(name: str) -> None:
    try:
        _s3.delete_object(Bucket=config.S3_BUCKET, Key=name)
    except ClientError as e:
        if e.response["Error"]["Code"] in ("NoSuchKey", "404"):
            raise HTTPException(404, "File not found")
        raise HTTPException(500, str(e))


# ── Local-filesystem helpers (dev fallback) ───────────────────────────────
def _local_path(name: str) -> Path:
    return config.WORKSPACE / name

def _local_list() -> list[str]:
    return sorted(p.name for p in config.WORKSPACE.iterdir() if NAME.match(p.name))


# ── Request/response models ───────────────────────────────────────────────
class FileBody(BaseModel):
    content: str

class RunBody(BaseModel):
    language: str
    code: str
    stdin: str = ""

class Test(BaseModel):
    input: str
    expected: str

class SolveBody(BaseModel):
    problem: str
    language: str
    tests: list[Test] = []


# ── File API (FR1) ────────────────────────────────────────────────────────
@app.get("/api/files")
async def list_files():
    if _s3:
        return await asyncio.to_thread(_s3_list)
    return _local_list()


@app.get("/api/files/{name}")
async def read_file(name: str):
    _validate_name(name)
    if _s3:
        content = await asyncio.to_thread(_s3_get, name)
        return {"content": content}
    p = _local_path(name)
    if not p.exists():
        raise HTTPException(404, "File not found")
    return {"content": p.read_text()}


@app.put("/api/files/{name}")
async def write_file(name: str, body: FileBody):
    _validate_name(name)
    if _s3:
        await asyncio.to_thread(_s3_put, name, body.content)
    else:
        _local_path(name).write_text(body.content)
    return {"ok": True}


@app.delete("/api/files/{name}")
async def delete_file(name: str):
    _validate_name(name)
    if _s3:
        await asyncio.to_thread(_s3_delete, name)
    else:
        p = _local_path(name)
        if not p.exists():
            raise HTTPException(404, "File not found")
        p.unlink()
    return {"ok": True}


# ── Run endpoint (FR2, FR3) ───────────────────────────────────────────────
@app.post("/api/run")
async def run(b: RunBody):
    if b.language not in LANGS:
        raise HTTPException(400, "language must be 'cpp' or 'python'")
    try:
        result = await asyncio.to_thread(sandbox.run_code, b.language, b.code, b.stdin)
    except ValueError as e:
        raise HTTPException(400, str(e))
    # Aurora logging happens inside sandbox.run_code, so it is not repeated here.
    return result


# ── Agent endpoint (FR4, FR5) ─────────────────────────────────────────────
@app.post("/api/agent/solve")
async def solve(b: SolveBody):
    if b.language not in LANGS:
        raise HTTPException(400, "language must be 'cpp' or 'python'")

    async def stream():
        try:
            async for ev in agent.solve(
                b.problem, b.language, [t.model_dump() for t in b.tests]
            ):
                yield f"data: {json.dumps(ev)}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'type': 'done', 'passed': False, 'msg': f'Server error: {e}'})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


# ── Static frontend ───────────────────────────────────────────────────────
app.mount(
    "/",
    StaticFiles(
        directory=Path(__file__).resolve().parents[2] / "frontend" / "dist",
        html=True,
    ),
    name="ui",
)
