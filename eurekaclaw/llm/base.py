"""Abstract LLMClient — identical call surface to anthropic.AsyncAnthropic.messages."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from eurekaclaw.llm.types import NormalizedMessage


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
        return await self._owner._create(
            model=model,
            max_tokens=max_tokens,
            messages=messages,
            system=system,
            tools=tools,
            **kwargs,
        )


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
