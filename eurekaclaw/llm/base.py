"""Abstract LLMClient — identical call surface to anthropic.AsyncAnthropic.messages."""

from __future__ import annotations

import asyncio
import logging
from abc import ABC, abstractmethod
from typing import Any

from eurekaclaw.llm.types import NormalizedMessage

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Global token counter — accumulated by every client.messages.create() call
# regardless of which agent or sub-component initiated it.
# ---------------------------------------------------------------------------
_GLOBAL_TOKENS: dict[str, int] = {"input": 0, "output": 0}


def get_global_tokens() -> dict[str, int]:
    """Return a snapshot copy of cumulative token usage across all LLM calls."""
    return dict(_GLOBAL_TOKENS)


def reset_global_tokens() -> None:
    """Reset the global counter. Call at the start of each top-level session."""
    _GLOBAL_TOKENS["input"] = 0
    _GLOBAL_TOKENS["output"] = 0

# Substrings in the exception message that indicate a transient error worth retrying.
_RETRYABLE_FRAGMENTS = (
    "429", "rate limit", "rate_limit",
    "overloaded", "529",
    "timeout", "timed out",
    "empty content",
    "service unavailable", "502", "503",
)


class _MessagesNamespace:
    """Provides the `client.messages.create(...)` call surface."""

    def __init__(self, owner: "LLMClient") -> None:
        self._owner = owner

    async def create(
        self,
        *,
        model: str,
        max_tokens: int,
        messages: list[dict[str, Any]],
        system: str = "",
        tools: list[dict[str, Any]] | None = None,
        **kwargs: Any,
    ) -> NormalizedMessage:
        from eurekaclaw.config import settings

        attempts = max(1, settings.llm_retry_attempts)
        wait_min = settings.llm_retry_wait_min
        wait_max = settings.llm_retry_wait_max

        last_exc: Exception = RuntimeError("unreachable")
        for attempt in range(attempts):
            try:
                response = await self._owner._create(
                    model=model,
                    max_tokens=max_tokens,
                    messages=messages,
                    system=system,
                    tools=tools,
                    **kwargs,
                )
                if not response.content:
                    raise ValueError("LLM returned empty content list")
                # Accumulate into the global counter regardless of caller.
                _GLOBAL_TOKENS["input"] += response.usage.input_tokens
                _GLOBAL_TOKENS["output"] += response.usage.output_tokens
                return response
            except Exception as exc:
                last_exc = exc
                err_str = str(exc).lower()
                is_retryable = any(frag in err_str for frag in _RETRYABLE_FRAGMENTS)
                if not is_retryable or attempt == attempts - 1:
                    raise
                wait = min(wait_min * (2 ** attempt), wait_max)
                logger.warning(
                    "LLM call failed (attempt %d/%d, retrying in %ds): %s",
                    attempt + 1, attempts, wait, exc,
                )
                await asyncio.sleep(wait)

        raise last_exc  # unreachable but satisfies type checker


class LLMClient(ABC):
    """Unified LLM client.  All backends expose `.messages.create(...)`.

    Usage (identical to the raw Anthropic client):
        response = await client.messages.create(
            model="...", max_tokens=4096, system="...", messages=[...], tools=[...]
        )
        text = response.content[0].text
    """

    def __init__(self) -> None:
        self.messages = _MessagesNamespace(self)

    async def close(self) -> None:
        """Optional async cleanup hook for clients with network transports."""
        return None

    @abstractmethod
    async def _create(
        self,
        *,
        model: str,
        max_tokens: int,
        messages: list[dict[str, Any]],
        system: str = "",
        tools: list[dict[str, Any]] | None = None,
        **kwargs: Any,
    ) -> NormalizedMessage:
        ...
