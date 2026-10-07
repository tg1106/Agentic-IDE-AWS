"""Model gateway: one place to point at vLLM on EC2 or any fallback provider."""
import asyncio

from openai import AsyncOpenAI

from . import config

_client = AsyncOpenAI(base_url=config.LLM_BASE_URL, api_key=config.LLM_API_KEY)


async def chat(messages: list[dict]) -> str:
    """Send a chat request and return the assistant reply text.

    Raises asyncio.TimeoutError if the model takes longer than config.LLM_TIMEOUT seconds,
    which the caller (agent.solve) catches and surfaces as a user-visible error.
    """
    async def _call() -> str:
        r = await _client.chat.completions.create(
            model=config.LLM_MODEL,
            messages=messages,
            temperature=0.2,
            max_tokens=config.LLM_MAX_TOKENS,
        )
        return r.choices[0].message.content or ""

    return await asyncio.wait_for(_call(), timeout=config.LLM_TIMEOUT)
