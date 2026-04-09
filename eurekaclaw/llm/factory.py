"""create_client() — returns the right LLMClient based on settings."""

from __future__ import annotations

import os

from eurekaclaw.llm.base import LLMClient

# Named shortcuts for LLM_BACKEND values
# "openrouter" → openai_compat with https://openrouter.ai/api/v1
# "local"      → openai_compat with http://localhost:8000/v1 (vLLM default)
# "minimax"    → openai_compat with https://api.minimaxi.chat/v1
# "codex"      → when CODEX_AUTH_MODE=oauth, uses the Responses API adapter
#                (OAuth tokens are billed via ChatGPT subscription, which
#                 only works with the Responses API, not Chat Completions).
#                When CODEX_AUTH_MODE=api_key, falls through to openai_compat
#                with https://api.openai.com/v1 (regular API billing).
_BACKEND_ALIASES: dict[str, tuple[str, str]] = {
    "openrouter": ("openai_compat", "https://openrouter.ai/api/v1"),
    "local": ("openai_compat", "http://localhost:8000/v1"),
    "minimax": ("openai_compat", "https://api.minimaxi.chat/v1"),
    "codex": ("openai_compat", "https://api.openai.com/v1"),
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
                                   "openrouter" (shortcut), "local" (shortcut),
                                   "minimax" (shortcut), "codex",
                                   "novita".
        anthropic_api_key: Override for settings.anthropic_api_key.
        openai_base_url:   Override for settings.openai_compat_base_url.
        openai_api_key:    Override for settings.openai_compat_api_key.
        openai_model:      Override for settings.openai_compat_model.
    """
    from eurekaclaw.config import settings

    original_backend = backend or settings.llm_backend

    # ── Codex + OAuth → ChatGPT backend Codex adapter ───────────────
    # OAuth tokens from the Codex CLI are scoped for the ChatGPT backend
    # (chatgpt.com/backend-api/codex/responses), not the standard OpenAI API.
    # The Chat Completions API rejects them with 429 "insufficient_quota"
    # and the standard Responses API rejects them with 401 "missing scopes".
    if original_backend == "codex" and settings.codex_auth_mode == "oauth":
        from eurekaclaw.llm.openai_responses import OpenAIResponsesAdapter
        from eurekaclaw.codex_manager import _load_valid_tokens, maybe_setup_codex_auth

        # Ensure the current process has the Codex OAuth token loaded, just as
        # the main CLI path does. This avoids accidentally falling back to an
        # unrelated OPENAI_COMPAT_API_KEY such as an OpenRouter key.
        maybe_setup_codex_auth()

        tokens = _load_valid_tokens() or {}
        api_key = (
            openai_api_key
            or tokens.get("access_token", "")
            or os.environ.get("OPENAI_COMPAT_API_KEY")
        )
        model = openai_model or settings.codex_model

        # Read account_id from Codex CLI credentials (needed for the
        # ChatGPT-Account-Id header that the backend requires).
        account_id = os.environ.get("CODEX_ACCOUNT_ID", "") or tokens.get("account_id", "")

        return OpenAIResponsesAdapter(
            api_key=api_key or "EMPTY",
            default_model=model,
            account_id=account_id,
        )

    if original_backend == "novita":
        from eurekaclaw.llm.novita_adapter import NovitaAdapter

        return NovitaAdapter(
            api_key=openai_api_key or settings.novita_api_key or "EMPTY",
            default_model=openai_model or settings.novita_model,
        )

    # ── Resolve backend aliases ────────────────────────────────────
    resolved_backend = original_backend
    default_base_url = ""
    if resolved_backend in _BACKEND_ALIASES:
        resolved_backend, default_base_url = _BACKEND_ALIASES[resolved_backend]

    if resolved_backend == "openai_compat":
        from eurekaclaw.llm.openai_compat import OpenAICompatAdapter

        # Base URL selection is backend-specific.
        # For Minimax, always prefer the built-in Minimax endpoint unless the
        # caller explicitly overrides it; do not inherit OPENAI_COMPAT_BASE_URL.
        if original_backend == "minimax":
            base_url = openai_base_url or default_base_url
        else:
            # Prefer live env var — codex_manager sets OPENAI_COMPAT_API_KEY at runtime
            # (after the settings singleton is loaded), so we must re-read it here.
            base_url = openai_base_url or settings.openai_compat_base_url or default_base_url

        # Pick the right API key per backend.
        if openai_api_key:
            api_key = openai_api_key
        elif original_backend == "minimax":
            api_key = settings.minimax_api_key
        elif original_backend == "codex":
            api_key = (
                os.environ.get("OPENAI_COMPAT_API_KEY")
                or settings.openai_compat_api_key
            )
        else:
            api_key = settings.openai_compat_api_key

        # Pick the right model per backend.
        if openai_model:
            model = openai_model
        elif original_backend == "minimax":
            model = settings.minimax_model
        elif original_backend == "codex":
            model = settings.codex_model
        else:
            model = settings.openai_compat_model

        if not base_url:
            raise ValueError(
                "OPENAI_COMPAT_BASE_URL must be set when LLM_BACKEND=openai_compat.\n"
                "Examples:\n"
                "  OpenRouter:  LLM_BACKEND=openrouter  OPENAI_COMPAT_API_KEY=sk-or-...\n"
                "  Minimax:     LLM_BACKEND=minimax      MINIMAX_API_KEY=...\n"
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
