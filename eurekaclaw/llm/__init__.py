"""LLM backend abstraction — Anthropic native, OpenRouter, vLLM/SGLang."""

from eurekaclaw.llm.base import LLMClient
from eurekaclaw.llm.factory import create_client

__all__ = ["LLMClient", "create_client"]
