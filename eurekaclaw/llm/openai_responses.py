"""OpenAI Codex backend via the ChatGPT backend API.

When the user authenticates via the Codex CLI (``codex auth login``), the OAuth
token is issued for the ChatGPT backend (``chatgpt.com/backend-api``), **not**
the standard OpenAI API (``api.openai.com``).  The token's scopes
(``api.connectors.invoke``) only grant access to the Codex endpoint at
``/codex/responses``, which mirrors the Responses API format but is served by
the ChatGPT backend and billed against the ChatGPT subscription.

Key differences from the standard Responses API:
  - Base URL:  ``https://chatgpt.com/backend-api``  (not api.openai.com)
  - Endpoint:  ``POST /codex/responses``
  - Header:    ``ChatGPT-Account-Id: <account_id>``  (from auth.json)
  - Required:  ``stream: true``  (non-streaming is not supported)
  - Forbidden: ``max_output_tokens``  (not accepted by this endpoint)
  - Models:    Codex-specific models only (``gpt-5.1-codex-mini``, etc.)

Anthropic → ChatGPT Codex translations:
  system kwarg          → ``instructions`` parameter
  messages list         → ``input`` array (messages + function_call items)
  tool definitions      → ``{"type":"function", "name":…, "parameters":…}``
  tool_use blocks       → ``function_call`` input items
  tool_result blocks    → ``function_call_output`` input items

ChatGPT Codex → NormalizedMessage translations:
  SSE stream → collect ``response.completed`` event
  output[].message.content[].output_text  → NormalizedTextBlock
  output[].function_call                  → NormalizedToolUseBlock
  status / incomplete_details             → stop_reason
  usage.input/output_tokens               → NormalizedUsage
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

_CHATGPT_BACKEND = "https://chatgpt.com/backend-api"

# Default model for ChatGPT Codex endpoint (must be a codex-specific model)
_DEFAULT_CODEX_MODEL = "gpt-5.1-codex-mini"


class OpenAIResponsesAdapter(LLMClient):
    """Backend that calls the ChatGPT Codex endpoint (``/codex/responses``).

    Designed for Codex OAuth tokens obtained via ``codex auth login``.
    These tokens are billed against the ChatGPT Plus/Pro subscription.
    """

    def __init__(
        self,
        api_key: str,
        default_model: str = "",
        account_id: str = "",
    ) -> None:
        super().__init__()
        try:
            import httpx  # noqa: F401
        except ImportError as exc:
            raise ImportError(
                "The 'httpx' package is required for the Codex backend. "
                "Install it with:  pip install httpx"
            ) from exc

        import httpx

        self._client = httpx.AsyncClient(
            base_url=_CHATGPT_BACKEND,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                **({"ChatGPT-Account-Id": account_id} if account_id else {}),
            },
            timeout=httpx.Timeout(180.0, connect=15.0),
        )
        self._default_model = default_model or _DEFAULT_CODEX_MODEL

    async def close(self) -> None:
        await self._client.aclose()

    # ------------------------------------------------------------------
    # Core request (streaming — required by ChatGPT backend)
    # ------------------------------------------------------------------

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
        input_items = self._to_responses_input(messages)

        body: dict[str, Any] = {
            "model": self._default_model or model,
            "input": input_items,
            "store": False,
            "stream": True,  # Required by ChatGPT backend
        }
        if system:
            body["instructions"] = system
        if tools:
            body["tools"] = self._to_responses_tools(tools)

        # Forward select kwargs that the endpoint accepts
        for k in ("temperature", "top_p", "truncation"):
            if k in kwargs:
                body[k] = kwargs[k]

        import httpx

        try:
            full_response: dict[str, Any] | None = None

            async with self._client.stream("POST", "/codex/responses", json=body) as resp:
                if resp.status_code >= 400:
                    error_body = (await resp.aread()).decode()
                    try:
                        err_detail = json.loads(error_body).get("detail", error_body)
                    except (json.JSONDecodeError, AttributeError):
                        err_detail = error_body
                    raise RuntimeError(
                        f"ChatGPT Codex API error ({resp.status_code}): {err_detail}"
                    )

                async for line in resp.aiter_lines():
                    if not line.strip():
                        continue
                    if line.startswith("data: "):
                        data_str = line[6:]
                        if data_str == "[DONE]":
                            break
                        try:
                            event = json.loads(data_str)
                            if event.get("type") == "response.completed":
                                full_response = event.get("response", {})
                        except json.JSONDecodeError:
                            continue

        except httpx.HTTPStatusError as exc:
            raise RuntimeError(
                f"ChatGPT Codex API error ({exc.response.status_code})"
            ) from exc

        if not full_response:
            raise RuntimeError(
                "ChatGPT Codex API: no response.completed event received"
            )

        # Check for API-level failure
        status = full_response.get("status", "completed")
        if status == "failed":
            error = full_response.get("error", {})
            raise RuntimeError(
                f"ChatGPT Codex API returned status=failed: "
                f"{error.get('message', 'unknown error') if isinstance(error, dict) else error}"
            )

        normalized = self._normalize(full_response)
        if not normalized.content:
            raise RuntimeError("ChatGPT Codex API returned no content blocks")
        return normalized

    # ------------------------------------------------------------------
    # Anthropic → Responses API input translation
    # ------------------------------------------------------------------

    @staticmethod
    def _to_responses_input(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Convert Anthropic-style message list to Responses API input items."""
        items: list[dict[str, Any]] = []

        for msg in messages:
            role = msg["role"]
            content = msg["content"]

            if role == "user":
                if isinstance(content, str):
                    items.append({"role": "user", "content": content})
                elif isinstance(content, list):
                    text_parts: list[str] = []
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "tool_result":
                            if text_parts:
                                items.append({"role": "user", "content": " ".join(text_parts)})
                                text_parts = []
                            items.append({
                                "type": "function_call_output",
                                "call_id": block.get("tool_use_id", ""),
                                "output": _coerce_to_str(block.get("content", "")),
                            })
                        elif isinstance(block, dict) and block.get("type") == "text":
                            text_parts.append(block.get("text", ""))
                        elif isinstance(block, str):
                            text_parts.append(block)
                        else:
                            text_parts.append(str(block))
                    if text_parts:
                        items.append({"role": "user", "content": " ".join(text_parts)})
                else:
                    items.append({"role": "user", "content": str(content)})

            elif role == "assistant":
                if isinstance(content, str):
                    items.append({"role": "assistant", "content": content})
                elif isinstance(content, list):
                    text_parts_a: list[str] = []
                    for block in content:
                        if not isinstance(block, dict):
                            text_parts_a.append(str(block))
                            continue
                        if block.get("type") == "text":
                            text_parts_a.append(block.get("text", ""))
                        elif block.get("type") == "tool_use":
                            if text_parts_a:
                                items.append({
                                    "role": "assistant",
                                    "content": " ".join(text_parts_a),
                                })
                                text_parts_a = []
                            items.append({
                                "type": "function_call",
                                "call_id": block["id"],
                                "name": block["name"],
                                "arguments": json.dumps(block.get("input", {})),
                            })
                    if text_parts_a:
                        items.append({
                            "role": "assistant",
                            "content": " ".join(text_parts_a),
                        })
                else:
                    items.append({"role": "assistant", "content": str(content)})

        return items

    # ------------------------------------------------------------------
    # Tool definition translation
    # ------------------------------------------------------------------

    @staticmethod
    def _to_responses_tools(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Anthropic tool defs → Responses API function tools."""
        result: list[dict[str, Any]] = []
        for t in tools:
            schema = t.get("input_schema") or t.get("parameters") or {}
            result.append({
                "type": "function",
                "name": t["name"],
                "description": t.get("description", ""),
                "parameters": schema,
            })
        return result

    # ------------------------------------------------------------------
    # Responses API output → NormalizedMessage
    # ------------------------------------------------------------------

    @staticmethod
    def _normalize(data: dict[str, Any]) -> NormalizedMessage:
        """Parse response.completed payload into a NormalizedMessage."""
        content: list[NormalizedTextBlock | NormalizedToolUseBlock] = []
        has_function_calls = False

        for item in data.get("output", []):
            item_type = item.get("type", "")

            if item_type == "message":
                for c in item.get("content", []):
                    if c.get("type") == "output_text":
                        text = c.get("text", "")
                        if text:
                            content.append(NormalizedTextBlock(text=text))

            elif item_type == "function_call":
                has_function_calls = True
                try:
                    parsed_input = json.loads(item.get("arguments", "{}"))
                except (json.JSONDecodeError, TypeError):
                    parsed_input = {}
                content.append(NormalizedToolUseBlock(
                    id=item.get("call_id", item.get("id", "")),
                    name=item.get("name", ""),
                    input=parsed_input,
                ))

        # Determine stop_reason
        status = data.get("status", "completed")
        if has_function_calls:
            stop_reason = "tool_use"
        elif status == "completed":
            stop_reason = "end_turn"
        elif status == "incomplete":
            reason = (data.get("incomplete_details") or {}).get("reason", "")
            stop_reason = "max_tokens" if reason == "max_output_tokens" else "end_turn"
        else:
            stop_reason = "end_turn"

        usage_data = data.get("usage", {})
        usage = NormalizedUsage(
            input_tokens=usage_data.get("input_tokens", 0),
            output_tokens=usage_data.get("output_tokens", 0),
        )

        return NormalizedMessage(content=content, stop_reason=stop_reason, usage=usage)


def _coerce_to_str(value: Any) -> str:
    """Coerce tool_result content to a plain string."""
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
