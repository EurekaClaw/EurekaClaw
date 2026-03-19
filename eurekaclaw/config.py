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
    eurekaclaw_model: str = Field(default="claude-sonnet-4-6", alias="EUREKACLAW_MODEL")
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
        default="auto", alias="GATE_MODE"
    )
    theory_max_iterations: int = Field(default=10, alias="THEORY_MAX_ITERATIONS")
    use_docker_sandbox: bool = Field(default=False, alias="USE_DOCKER_SANDBOX")
    # Output format for the generated paper: "latex" (default) or "markdown"
    output_format: str = Field(default="latex", alias="OUTPUT_FORMAT")

    # ---- Token-efficiency knobs --------------------------------------------
    context_compress_after_turns: int = Field(default=6, alias="CONTEXT_COMPRESS_AFTER_TURNS")
    auto_verify_confidence: float = Field(default=0.85, alias="AUTO_VERIFY_CONFIDENCE")
    stagnation_window: int = Field(default=3, alias="STAGNATION_WINDOW")
    experiment_mode: Literal["auto", "true", "false"] = Field(
        default="auto", alias="EXPERIMENT_MODE"
    )

    # ---- Token limits per call type ----------------------------------------
    max_tokens_agent: int = Field(default=8192, alias="MAX_TOKENS_AGENT")
    max_tokens_prover: int = Field(default=4096, alias="MAX_TOKENS_PROVER")
    max_tokens_planner: int = Field(default=4096, alias="MAX_TOKENS_PLANNER")
    max_tokens_decomposer: int = Field(default=2048, alias="MAX_TOKENS_DECOMPOSER")
    max_tokens_formalizer: int = Field(default=2048, alias="MAX_TOKENS_FORMALIZER")
    max_tokens_verifier: int = Field(default=1024, alias="MAX_TOKENS_VERIFIER")
    max_tokens_compress: int = Field(default=512, alias="MAX_TOKENS_COMPRESS")

    # ---- Agent loop tuning --------------------------------------------------
    survey_max_turns: int = Field(default=8, alias="SURVEY_MAX_TURNS")
    theory_stage_max_turns: int = Field(default=6, alias="THEORY_STAGE_MAX_TURNS")
    writer_max_turns: int = Field(default=4, alias="WRITER_MAX_TURNS")
    arxiv_max_results: int = Field(default=10, alias="ARXIV_MAX_RESULTS")
    llm_retry_attempts: int = Field(default=5, alias="LLM_RETRY_ATTEMPTS")
    llm_retry_wait_min: int = Field(default=4, alias="LLM_RETRY_WAIT_MIN")
    llm_retry_wait_max: int = Field(default=90, alias="LLM_RETRY_WAIT_MAX")

    # ---- Proof quality ------------------------------------------------------
    # When True, writer enforces step-by-step proof rules and highlights
    # low-confidence lemmas with \textcolor{orange} in the PDF output.
    enforce_proof_style: bool = Field(default=True, alias="ENFORCE_PROOF_STYLE")

    # ---- Paths -------------------------------------------------------------
    metaclaw_dir: Path = Field(default=Path.home() / ".metaclaw", alias="METACLAW_DIR")
    lean4_bin: str = Field(default="lean", alias="LEAN4_BIN")
    latex_bin: str = Field(default="pdflatex", alias="LATEX_BIN")

    @field_validator("metaclaw_dir", mode="before")
    @classmethod
    def expand_home(cls, v: str | Path) -> Path:
        return Path(v).expanduser()

    @property
    def fast_model(self) -> str:
        """Return the fast model name, falling back to the main model if unset.

        Allows users to leave EUREKACLAW_FAST_MODEL empty (or omit it) when
        the fast model is not available (e.g. self-hosted endpoints that only
        serve one model).  All code should call ``settings.fast_model`` instead
        of ``settings.eurekaclaw_fast_model`` directly.
        """
        return self.eurekaclaw_fast_model or self.eurekaclaw_model

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
