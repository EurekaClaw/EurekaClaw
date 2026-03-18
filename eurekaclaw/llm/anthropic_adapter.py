"""Anthropic native backend — thin wrapper around anthropic.AsyncAnthropic."""

from __future__ import annotations

import os
from typing import Any

import anthropic

from eurekaclaw.llm.base import LLMClient
from eurekaclaw.llm.types import (
    NormalizedMessage,
    NormalizedTextBlock,
    NormalizedToolUseBlock,
    NormalizedUsage,
)


class AnthropicAdapter(LLMClient):
    """Wraps anthropic.AsyncAnthropic and normalizes responses."""

    def __init__(self, api_key: str) -> None:
        super().__init__()
        # Prefer the live environment value over the settings-time value.
        # ccproxy sets ANTHROPIC_API_KEY="ccproxy-oauth" *after* the settings
        # singleton is loaded, so settings.anthropic_api_key may be "" even
        # though the env var is now populated.
        effective_key = os.environ.get("ANTHROPIC_API_KEY") or api_key
        if not effective_key:
            raise ValueError(
                "ANTHROPIC_API_KEY is not set. Either add it to .env or "
                "configure OAuth via ANTHROPIC_AUTH_MODE=oauth."
            )
        self._client = anthropic.AsyncAnthropic(api_key=effective_key)

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
        call_kwargs: dict[str, Any] = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": messages,
        }
        if system:
            call_kwargs["system"] = system
        if tools:
            call_kwargs["tools"] = tools
        call_kwargs.update(kwargs)

        resp = await self._client.messages.create(**call_kwargs)
        return self._normalize(resp)

    @staticmethod
    def _normalize(resp: anthropic.types.Message) -> NormalizedMessage:
        content: list[NormalizedTextBlock | NormalizedToolUseBlock] = []
        for block in resp.content:
            if block.type == "text":
                content.append(NormalizedTextBlock(text=block.text))
            elif block.type == "tool_use":
                content.append(NormalizedToolUseBlock(
                    id=block.id,
                    name=block.name,
                    input=block.input,
                ))
        usage = NormalizedUsage(
            input_tokens=resp.usage.input_tokens if resp.usage else 0,
            output_tokens=resp.usage.output_tokens if resp.usage else 0,
        )
        return NormalizedMessage(
            content=content,
            stop_reason=resp.stop_reason or "end_turn",
            usage=usage,
        )
