"""Runs untrusted C++/Python in a locked-down, throwaway Docker container.

Every execution result is logged to Aurora via db.log_run (no-op when
DB_HOST is not configured).
"""
import os
import subprocess
import tempfile
import threading
import uuid

from . import config, db

_ROOT_WARNING_EMITTED = False

FILES = {"cpp": "main.cpp", "python": "main.py"}

# compile_timeout is separate from run_timeout: g++ can take several seconds
# even for small files on a cold container.
CMDS = {
    "cpp":    "ulimit -f 100000; timeout {c} g++ -O2 -std=c++17 main.cpp -o main && timeout {t} ./main",
    "python": "ulimit -f 100000; timeout {t} python3 main.py",
}


def run_code(
    language: str,
    code: str,
    stdin: str = "",
    timeout: int | None = None,
    *,
    log_passed: bool | None = None,
    log_attempt: int | None = None,
) -> dict:
    """Execute *code* in the sandbox and return a result dict.

    Args:
        language:    'cpp' or 'python'
        code:        source code string
        stdin:       data piped to the program's stdin
        timeout:     per-run time limit (seconds); defaults to config.RUN_TIMEOUT
        log_passed:  passed=True/False/None to record in run_logs (agent use)
        log_attempt: attempt number to record in run_logs (agent use)

    Returns:
        {stdout, stderr, exit_code, timed_out}
    """
    if language not in FILES:
        raise ValueError("language must be 'cpp' or 'python'")

    global _ROOT_WARNING_EMITTED
    if os.getuid() == 0 and not _ROOT_WARNING_EMITTED:
        import logging
        logging.getLogger(__name__).warning(
            "Server is running as root (UID 0). "
            "The sandbox container will also run as root, weakening isolation."
        )
        _ROOT_WARNING_EMITTED = True

    t = timeout or config.RUN_TIMEOUT
    c = config.COMPILE_TIMEOUT
    name = f"ide-run-{uuid.uuid4().hex[:8]}"

    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, FILES[language]), "w") as f:
            f.write(code)

        cmd = [
            "docker", "run", "--rm", "-i", "--name", name,
            "--network",      "none",
            "--memory",       "256m",
            "--cpus",         "1",
            "--pids-limit",   "64",
            "--read-only",
            "--tmpfs",        "/tmp:size=64m",
            "--cap-drop",     "ALL",
            "--security-opt", "no-new-privileges",
            "--user",         f"{os.getuid()}:{os.getgid()}",
            "-v",             f"{d}:/work",
            "-w",             "/work",
            config.SANDBOX_IMAGE,
            "sh", "-c", CMDS[language].format(t=t, c=c),
        ]

        try:
            p = subprocess.run(
                cmd,
                input=stdin,
                capture_output=True,
                text=True,
                timeout=t + c + 45,
            )
            result = {
                "stdout":    p.stdout[-10_000:],
                "stderr":    p.stderr[-4_000:],
                "exit_code": p.returncode,
                "timed_out": p.returncode == 124,
            }
        except FileNotFoundError:
            result = {
                "stdout":    "",
                "stderr":    "Docker not found. Make sure Docker is installed and running.",
                "exit_code": 1,
                "timed_out": False,
            }
        except subprocess.TimeoutExpired:
            subprocess.run(["docker", "kill", name], capture_output=True)
            result = {
                "stdout":    "",
                "stderr":    "Killed: exceeded time limit.",
                "exit_code": 124,
                "timed_out": True,
            }

    # Log to Aurora (silently skipped when DB_HOST is unset)
    # Fire-and-forget: Aurora may be resuming from auto-pause, which must not delay the response.
    threading.Thread(
        target=db.log_run,
        kwargs=dict(
            language=language,
            exit_code=result["exit_code"],
            timed_out=result["timed_out"],
            stdout=result["stdout"],
            stderr=result["stderr"],
            passed=log_passed,
            attempt=log_attempt,
        ),
        daemon=True,
    ).start()

    return result
