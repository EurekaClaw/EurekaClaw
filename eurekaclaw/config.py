"""Global configuration via Pydantic Settings (reads from .env / environment)."""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Config(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # ---- LLM backend -------------------------------------------------------
    # "anthropic"    — use Anthropic native API (default)
    # "openai_compat" — use any OpenAI-compatible endpoint (OpenRouter, vLLM, SGLang…)
    llm_backend: str = Field(default="anthropic", alias="LLM_BACKEND")

    # ---- ccproxy / OAuth ---------------------------------------------------
    # "api_key" (default) — use ANTHROPIC_API_KEY directly
    # "oauth"             — route through ccproxy using Claude Code's OAuth tokens
    #                       (requires: pip install 'eurekaclaw[oauth]', then
    #                        ccproxy auth login claude_api)
    anthropic_auth_mode: Literal["api_key", "oauth"] = Field(
        default="api_key", alias="ANTHROPIC_AUTH_MODE"
    )
    ccproxy_port: int = Field(default=8000, alias="CCPROXY_PORT")

    # Anthropic native
    anthropic_api_key: str = Field(default="", alias="ANTHROPIC_API_KEY")
    eurekaclaw_model: str = Field(default="claude-opus-4-6", alias="EUREKACLAW_MODEL")
    eurekaclaw_fast_model: str = Field(
        default="claude-haiku-4-5-20251001", alias="EUREKACLAW_FAST_MODEL"
    )

    # OpenAI-compatible endpoint (OpenRouter / vLLM / SGLang / LM Studio / …)
    openai_compat_base_url: str = Field(default="", alias="OPENAI_COMPAT_BASE_URL")
    openai_compat_api_key: str = Field(default="", alias="OPENAI_COMPAT_API_KEY")
    # Model name sent to the OpenAI-compat endpoint.
    # Overrides EUREKACLAW_MODEL when LLM_BACKEND=openai_compat.
    openai_compat_model: str = Field(default="", alias="OPENAI_COMPAT_MODEL")

    # ---- External APIs -----------------------------------------------------
    brave_search_api_key: str = Field(default="", alias="BRAVE_SEARCH_API_KEY")
    serpapi_key: str = Field(default="", alias="SERPAPI_KEY")
    wolfram_app_id: str = Field(default="", alias="WOLFRAM_APP_ID")
    s2_api_key: str = Field(default="", alias="S2_API_KEY")

    # ---- System behaviour --------------------------------------------------
    eurekaclaw_mode: Literal["skills_only", "rl", "madmax"] = Field(
        default="skills_only", alias="EUREKACLAW_MODE"
    )
    gate_mode: Literal["auto", "human", "none"] = Field(
        default="none", alias="GATE_MODE"
    )
    theory_max_iterations: int = Field(default=10, alias="THEORY_MAX_ITERATIONS")
    use_docker_sandbox: bool = Field(default=False, alias="USE_DOCKER_SANDBOX")
    # Output format for the generated paper: "latex" (default) or "markdown"
    output_format: str = Field(default="latex", alias="OUTPUT_FORMAT")

    # ---- Paths -------------------------------------------------------------
    metaclaw_dir: Path = Field(default=Path.home() / ".metaclaw", alias="METACLAW_DIR")
    lean4_bin: str = Field(default="lean", alias="LEAN4_BIN")
    latex_bin: str = Field(default="pdflatex", alias="LATEX_BIN")

    @field_validator("metaclaw_dir", mode="before")
    @classmethod
    def expand_home(cls, v: str | Path) -> Path:
        return Path(v).expanduser()

    @property
    def skills_dir(self) -> Path:
        return self.metaclaw_dir / "skills"

    @property
    def memory_dir(self) -> Path:
        return self.metaclaw_dir / "memory"

    @property
    def runs_dir(self) -> Path:
        return self.metaclaw_dir / "runs"

    def ensure_dirs(self) -> None:
        for d in (self.skills_dir, self.memory_dir, self.runs_dir):
            d.mkdir(parents=True, exist_ok=True)


# Singleton — import this everywhere
settings = Config()
