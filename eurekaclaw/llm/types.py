"""Normalized response types returned by every LLMClient backend.

These mirror the shape of anthropic.types.Message so existing call-sites
(response.content[0].text, response.stop_reason, response.usage.input_tokens)
work without modification regardless of which backend is active.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class NormalizedUsage:
    input_tokens: int = 0
    output_tokens: int = 0


@dataclass
class NormalizedTextBlock:
    text: str
    type: str = "text"


@dataclass
class NormalizedToolUseBlock:
    id: str
    name: str
    input: dict[str, Any]
    type: str = "tool_use"


# Union type for content blocks — matches Anthropic SDK usage pattern
ContentBlock = NormalizedTextBlock | NormalizedToolUseBlock


@dataclass
class NormalizedMessage:
    """Drop-in replacement for anthropic.types.Message.

    Supports the access patterns used across all agents:
      response.content[0].text
      response.content          (list of blocks)
      response.stop_reason
      response.usage.input_tokens / .output_tokens
    """

    content: list[ContentBlock]
    stop_reason: str
    usage: NormalizedUsage = field(default_factory=NormalizedUsage)
