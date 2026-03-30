"""OpenAI-compatible backend — supports OpenRouter, vLLM, SGLang, and any
OpenAI-spec endpoint.

Format translation performed at the API boundary so all existing agents
continue to use Anthropic-style message dicts and tool definitions internally.

Anthropic → OpenAI translations applied on every call:
  system kwarg          → prepend {"role":"system","content":"..."} to messages
  input_schema in tools → renamed to parameters
  tool definitions      → wrapped in {"type":"function","function":{...}}
  assistant content list with tool_use blocks
                        → {"tool_calls":[...]} on the assistant message
  user content list of tool_result dicts
                        → split into individual {"role":"tool",...} messages

OpenAI → NormalizedMessage translations applied to every response:
  choices[0].message.content       → NormalizedTextBlock
  choices[0].message.tool_calls    → NormalizedToolUseBlock list
  choices[0].finish_reason         → stop_reason  ("stop"→"end_turn", etc.)
  usage.prompt/completion_tokens   → NormalizedUsage
"""

from __future__ import annotations

import json
import logging
from typing import Any

from eurekaclaw.llm.base import LLMClient
from eurekaclaw.llm.types import (
    NormalizedMessage,
    NormalizedTextBlock,
    NormalizedToolUseBlock,
    NormalizedUsage,
)

logger = logging.getLogger(__name__)


class OpenAICompatAdapter(LLMClient):
    """Backend for any OpenAI-spec endpoint (OpenRouter, vLLM, SGLang, LM Studio…)."""

    def __init__(self, base_url: str, api_key: str, default_model: str = "") -> None:
        super().__init__()
        try:
            from openai import AsyncOpenAI
        except ImportError as exc:
            raise ImportError(
                "The 'openai' package is required for the OpenAI-compatible backend. "
                "Install it with:  pip install openai"
            ) from exc

        self._client = AsyncOpenAI(base_url=base_url, api_key=api_key)
        self._default_model = default_model

    async def close(self) -> None:
        await self._client.close()

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
        oai_messages = self._to_openai_messages(messages, system)
        oai_tools = self._to_openai_tools(tools) if tools else None

        call_kwargs: dict[str, Any] = {
            "model": self._default_model or model,
            "max_tokens": max_tokens,
            "messages": oai_messages,
        }
        if oai_tools:
            call_kwargs["tools"] = oai_tools
            call_kwargs["tool_choice"] = "auto"
        call_kwargs.update(kwargs)

        resp = await self._client.chat.completions.create(**call_kwargs)
        return self._normalize(resp)

    # ------------------------------------------------------------------
    # Anthropic → OpenAI message translation
    # ------------------------------------------------------------------

    @staticmethod
    def _to_openai_messages(
        messages: list[dict[str, Any]], system: str
    ) -> list[dict[str, Any]]:
        """Convert Anthropic-style message list to OpenAI chat format."""
        oai: list[dict[str, Any]] = []

        if system:
            oai.append({"role": "system", "content": system})

        for msg in messages:
            role = msg["role"]
            content = msg["content"]

            if role == "user":
                if isinstance(content, str):
                    oai.append({"role": "user", "content": content})
                elif isinstance(content, list):
                    # May be a list of tool_result dicts
                    tool_results = [
                        b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"
                    ]
                    other = [
                        b for b in content if not (isinstance(b, dict) and b.get("type") == "tool_result")
                    ]
                    # Each tool_result becomes a separate "tool" role message
                    for tr in tool_results:
                        oai.append({
                            "role": "tool",
                            "tool_call_id": tr.get("tool_use_id", ""),
                            "content": _coerce_to_str(tr.get("content", "")),
                        })
                    if other:
                        text = " ".join(
                            b.get("text", str(b)) if isinstance(b, dict) else str(b)
                            for b in other
                        )
                        oai.append({"role": "user", "content": text})
                else:
                    oai.append({"role": "user", "content": str(content)})

            elif role == "assistant":
                if isinstance(content, str):
                    oai.append({"role": "assistant", "content": content})
                elif isinstance(content, list):
                    # Mixed text + tool_use blocks
                    text_parts = [
                        b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text"
                    ]
                    tool_use_blocks = [
                        b for b in content
                        if isinstance(b, dict) and b.get("type") == "tool_use"
                    ]
                    oai_msg: dict[str, Any] = {
                        "role": "assistant",
                        "content": " ".join(text_parts) or None,
                    }
                    if tool_use_blocks:
                        oai_msg["tool_calls"] = [
                            {
                                "id": b["id"],
                                "type": "function",
                                "function": {
                                    "name": b["name"],
                                    "arguments": json.dumps(b.get("input", {})),
                                },
                            }
                            for b in tool_use_blocks
                        ]
                    oai.append(oai_msg)
                else:
                    oai.append({"role": "assistant", "content": str(content)})

        return oai

    # ------------------------------------------------------------------
    # Tool definition translation
    # ------------------------------------------------------------------

    @staticmethod
    def _to_openai_tools(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Anthropic tool defs → OpenAI function tool defs."""
        oai_tools = []
        for t in tools:
            fn: dict[str, Any] = {
                "name": t["name"],
                "description": t.get("description", ""),
            }
            # Anthropic uses "input_schema"; OpenAI uses "parameters"
            schema = t.get("input_schema") or t.get("parameters") or {}
            fn["parameters"] = schema
            oai_tools.append({"type": "function", "function": fn})
        return oai_tools

    # ------------------------------------------------------------------
    # OpenAI response → NormalizedMessage
    # ------------------------------------------------------------------

    @staticmethod
    def _normalize(resp: Any) -> NormalizedMessage:
        choice = resp.choices[0]
        message = choice.message
        content: list[NormalizedTextBlock | NormalizedToolUseBlock] = []

        if message.content is not None:
            content.append(NormalizedTextBlock(text=message.content or ""))

        for tc in message.tool_calls or []:
            try:
                parsed_input = json.loads(tc.function.arguments)
            except (json.JSONDecodeError, AttributeError):
                parsed_input = {}
            content.append(NormalizedToolUseBlock(
                id=tc.id,
                name=tc.function.name,
                input=parsed_input,
            ))

        # Normalize finish_reason to Anthropic conventions
        finish = choice.finish_reason or "stop"
        stop_reason = {
            "stop": "end_turn",
            "tool_calls": "tool_use",
            "length": "max_tokens",
            "content_filter": "stop_sequence",
        }.get(finish, finish)

        usage = NormalizedUsage(
            input_tokens=getattr(resp.usage, "prompt_tokens", 0),
            output_tokens=getattr(resp.usage, "completion_tokens", 0),
        )
        return NormalizedMessage(content=content, stop_reason=stop_reason, usage=usage)


def _coerce_to_str(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                parts.append(item.get("text", str(item)))
            else:
                parts.append(str(item))
        return " ".join(parts)
    return str(value)
