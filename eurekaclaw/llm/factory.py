"""create_client() — returns the right LLMClient based on settings."""

from __future__ import annotations

from eurekaclaw.llm.base import LLMClient

# Named shortcuts for LLM_BACKEND values
# "openrouter" → openai_compat with https://openrouter.ai/api/v1
# "local"      → openai_compat with http://localhost:8000/v1 (vLLM default)
_BACKEND_ALIASES: dict[str, tuple[str, str]] = {
    "openrouter": ("openai_compat", "https://openrouter.ai/api/v1"),
    "local": ("openai_compat", "http://localhost:8000/v1"),
}


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
        backend:           Override for settings.llm_backend.
                           Values: "anthropic" (default), "openai_compat",
                                   "openrouter" (shortcut), "local" (shortcut).
        anthropic_api_key: Override for settings.anthropic_api_key.
        openai_base_url:   Override for settings.openai_compat_base_url.
        openai_api_key:    Override for settings.openai_compat_api_key.
        openai_model:      Override for settings.openai_compat_model.
    """
    from eurekaclaw.config import settings

    resolved_backend = backend or settings.llm_backend

    # Resolve named shortcuts to openai_compat with preset base URLs
    default_base_url = ""
    if resolved_backend in _BACKEND_ALIASES:
        resolved_backend, default_base_url = _BACKEND_ALIASES[resolved_backend]

    if resolved_backend == "openai_compat":
        from eurekaclaw.llm.openai_compat import OpenAICompatAdapter

        base_url = openai_base_url or settings.openai_compat_base_url or default_base_url
        api_key = openai_api_key or settings.openai_compat_api_key
        model = openai_model or settings.openai_compat_model

        if not base_url:
            raise ValueError(
                "OPENAI_COMPAT_BASE_URL must be set when LLM_BACKEND=openai_compat.\n"
                "Examples:\n"
                "  OpenRouter:  LLM_BACKEND=openrouter  OPENAI_COMPAT_API_KEY=sk-or-...\n"
                "  vLLM:        LLM_BACKEND=local        OPENAI_COMPAT_MODEL=Qwen/...\n"
                "  Custom:      LLM_BACKEND=openai_compat OPENAI_COMPAT_BASE_URL=http://..."
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
