"""create_client() — returns the right LLMClient based on settings."""

from __future__ import annotations

from eurekaclaw.llm.base import LLMClient


def create_client(
    backend: str | None = None,
    *,
    anthropic_api_key: str | None = None,
    openai_base_url: str | None = None,
    openai_api_key: str | None = None,
    openai_model: str | None = None,
) -> LLMClient:
    """Factory that reads configuration from settings when kwargs are not provided.

    Args:
        backend:          Override for settings.llm_backend  ("anthropic" or "openai_compat").
        anthropic_api_key: Override for settings.anthropic_api_key.
        openai_base_url:  Override for settings.openai_compat_base_url.
        openai_api_key:   Override for settings.openai_compat_api_key.
        openai_model:     Override for settings.openai_compat_model.
    """
    from eurekaclaw.config import settings

    resolved_backend = backend or settings.llm_backend

    if resolved_backend == "openai_compat":
        from eurekaclaw.llm.openai_compat import OpenAICompatAdapter

        base_url = openai_base_url or settings.openai_compat_base_url
        api_key = openai_api_key or settings.openai_compat_api_key
        model = openai_model or settings.openai_compat_model

        if not base_url:
            raise ValueError(
                "OPENAI_COMPAT_BASE_URL must be set when LLM_BACKEND=openai_compat.\n"
                "Examples:\n"
                "  OpenRouter:  https://openrouter.ai/api/v1\n"
                "  vLLM:        http://localhost:8000/v1\n"
                "  SGLang:      http://localhost:30000/v1"
            )

        return OpenAICompatAdapter(
            base_url=base_url,
            api_key=api_key or "EMPTY",
            default_model=model,
        )

    # Default: Anthropic native
    from eurekaclaw.llm.anthropic_adapter import AnthropicAdapter

    key = anthropic_api_key or settings.anthropic_api_key
    return AnthropicAdapter(api_key=key)
