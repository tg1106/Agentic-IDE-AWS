"""Write -> run -> fix loop. Plain code-block protocol (no tool-calling) so small models cope."""
import asyncio
import re

from . import config, llm, sandbox

SYSTEM = (
    "You are a competitive programming assistant. Reply with ONE fenced code block holding the "
    "complete solution. It must read from stdin and write to stdout. No text outside the block."
)


def extract_code(text: str) -> tuple[str, bool]:
    """Return (code, found) where found=False means no fenced block was detected."""
    m = re.search(r"```(?:\w+)?\n(.*?)```", text, re.S)
    if m:
        return m.group(1).strip(), True
    return text.strip(), False


def same(got: str, expected: str) -> bool:
    """Whitespace-insensitive comparison, matching most competitive-programming judges."""
    return got.split() == expected.split()


async def _run_test(language: str, code: str, test: dict, n: int) -> str | None:
    """Run one test case in the sandbox. Returns a failure string or None on pass."""
    r = await asyncio.to_thread(sandbox.run_code, language, code, test["input"])
    if r["exit_code"] == 0 and same(r["stdout"], test["expected"]):
        return None
    why = "time limit exceeded" if r["timed_out"] else r["stderr"][:500]
    return (
        f"Test {n}\ninput:\n{test['input']}\nexpected:\n{test['expected']}\n"
        f"got:\n{r['stdout'][:300]}\nerror: {why}"
    )


async def solve(problem: str, language: str, tests: list[dict]):
    lang = "C++17" if language == "cpp" else "Python 3"
    msgs = [
        {"role": "system", "content": SYSTEM},
        {"role": "user",   "content": f"Language: {lang}\n\nProblem:\n{problem}"},
    ]

    for i in range(1, config.MAX_ITERS + 1):
        yield {"type": "status", "msg": f"Attempt {i}: asking the model"}

        try:
            reply = await llm.chat(msgs)
        except asyncio.TimeoutError:
            yield {
                "type": "done", "passed": False,
                "msg": f"Model did not respond within {config.LLM_TIMEOUT} s. "
                       "Is vLLM running? Check with: curl http://127.0.0.1:8000/v1/models",
            }
            return

        code, found = extract_code(reply)
        if not found:
            yield {"type": "status", "msg": "No fenced code block in model reply — retrying"}
            # Feed the raw reply back and ask again so the model self-corrects.
            msgs += [
                {"role": "assistant", "content": reply},
                {"role": "user",      "content":
                    "Your reply did not contain a fenced code block. "
                    "Reply with ONLY a fenced code block containing the full solution."},
            ]
            continue

        yield {"type": "code", "code": code}

        if not tests:
            yield {
                "type": "done", "passed": None,
                "msg": "No tests provided — solution not verified.",
            }
            return

        # Run all tests in parallel to save time on problems with many cases.
        results = await asyncio.gather(
            *[_run_test(language, code, t, n) for n, t in enumerate(tests, 1)]
        )
        failures = [r for r in results if r is not None]
        passed = len(tests) - len(failures)
        yield {"type": "result", "passed": passed, "total": len(tests)}

        if not failures:
            yield {"type": "done", "passed": True, "msg": f"All {len(tests)} tests passed."}
            return

        msgs += [
            {"role": "assistant", "content": reply},
            {
                "role": "user",
                "content": (
                    "Your solution failed:\n\n"
                    + "\n\n".join(failures[:3])
                    + "\n\nFix it. Reply with the full corrected solution in one code block."
                ),
            },
        ]

    yield {"type": "done", "passed": False, "msg": f"Gave up after {config.MAX_ITERS} attempts."}
