"""eurekaclaw onboard — interactive .env configuration wizard."""

from __future__ import annotations

import sys
from pathlib import Path

import click
from rich.rule import Rule

from eurekaclaw.console import console

# ── ANSI helpers (used by the arrow-key selector) ─────────────────────────────
_A_BOLD  = "\x1b[1m"
_A_DIM   = "\x1b[2m"
_A_GREEN = "\x1b[32m"
_A_BLUE  = "\x1b[34m"
_A_RESET = "\x1b[0m"
_A_CLRL  = "\x1b[2K\r"   # clear current line, carriage-return
_A_UP    = "\x1b[1A"     # move cursor up one line


def _enable_ansi_windows() -> None:
    """Enable ANSI virtual-terminal processing on Windows consoles."""
    if sys.platform != "win32":
        return
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        # ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004, ENABLE_PROCESSED_OUTPUT = 0x0001
        kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
    except Exception:
        pass


def _load_existing_env(env_path: Path) -> dict[str, str]:
    existing: dict[str, str] = {}
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            existing[k.strip()] = v.strip()
    return existing


def _ask(prompt: str, default: str, secret: bool = False, non_interactive: bool = False) -> str:
    if non_interactive:
        return default
    return click.prompt(prompt, default=default, hide_input=secret)


def _ask_choice(
    prompt: str,
    choices: list[str],
    default: str,
    non_interactive: bool = False,
) -> str:
    if non_interactive:
        return default

    # Use arrow-key selector when stdin is a real TTY
    if sys.stdin.isatty():
        return _arrow_choice(prompt, choices, default)

    # Fallback for piped / redirected input
    parts = "/".join(f"[bold]{c}[/bold]" if c == default else c for c in choices)
    console.print(f"  {prompt}  [{parts}]")
    while True:
        val = click.prompt("  >", default=default)
        if val in choices:
            return val
        console.print(f"  [red]Invalid. Choose one of: {', '.join(choices)}[/red]")


def _arrow_choice(prompt: str, choices: list[str], default: str) -> str:
    """Render an arrow-key navigable list, OpenClaw-style."""
    import readchar  # lazy import — only needed for interactive sessions

    _enable_ansi_windows()

    idx = choices.index(default) if default in choices else 0
    n = len(choices)

    def _row(i: int) -> str:
        if i == idx:
            return f"{_A_CLRL}  {_A_GREEN}●{_A_RESET} {_A_BOLD}{choices[i]}{_A_RESET}"
        return f"{_A_CLRL}  {_A_DIM}○ {choices[i]}{_A_RESET}"

    # Header
    sys.stdout.write(f"\n{_A_BLUE}◆{_A_RESET} {_A_BOLD}{prompt}{_A_RESET}\n")
    # Initial list
    for i in range(n):
        sys.stdout.write(_row(i) + "\n")
    sys.stdout.flush()

    while True:
        key = readchar.readkey()
        if key == readchar.key.UP:
            idx = (idx - 1) % n
        elif key == readchar.key.DOWN:
            idx = (idx + 1) % n
        elif key in (readchar.key.ENTER, "\r", "\n"):
            break
        else:
            continue

        # Redraw list in place
        sys.stdout.write(_A_UP * n)
        for i in range(n):
            sys.stdout.write(_row(i) + "\n")
        sys.stdout.flush()

    # Collapse to single selected line
    sys.stdout.write(_A_UP * n)
    for _ in range(n):
        sys.stdout.write(f"{_A_CLRL}\n")
    sys.stdout.write(_A_UP * n)
    sys.stdout.write(
        f"{_A_CLRL}  {_A_GREEN}●{_A_RESET} {_A_BOLD}{choices[idx]}{_A_RESET}\n"
    )
    sys.stdout.flush()

    return choices[idx]


def _write_env(env_path: Path, merged: dict[str, str]) -> None:
    """Write merged config preserving .env.example structure."""
    env_example = Path(__file__).parent.parent / ".env.example"
    if env_example.exists():
        lines: list[str] = []
        seen: set[str] = set()
        for raw in env_example.read_text(encoding="utf-8").splitlines():
            stripped = raw.strip()
            if stripped.startswith("#") or not stripped:
                lines.append(raw)
                continue
            key = stripped.split("=", 1)[0].strip()
            if key in merged:
                lines.append(f"{key}={merged[key]}")
                seen.add(key)
            else:
                lines.append(raw)
        extras = [f"{k}={v}" for k, v in merged.items() if k not in seen]
        if extras:
            lines.append("")
            lines.append("# ── Additional keys ─────────────────────────────────────────────────────────")
            lines.extend(extras)
        output = "\n".join(lines) + "\n"
    else:
        output = "\n".join(f"{k}={v}" for k, v in merged.items()) + "\n"

    env_path.parent.mkdir(parents=True, exist_ok=True)
    env_path.write_text(output, encoding="utf-8")


def run_onboard(non_interactive: bool, reset: bool, env_file: str) -> None:
    env_path = Path(env_file).expanduser()

    # ── Welcome ───────────────────────────────────────────────────────────────
    console.print()
    console.print(Rule("[bold cyan]EurekaClaw Onboarding[/bold cyan]"))
    console.print(
        "[dim]This wizard configures your [bold].env[/bold] file.\n"
        "Press [bold]Enter[/bold] to accept the default shown in brackets.[/dim]\n"
    )

    # ── Load existing .env ────────────────────────────────────────────────────
    existing: dict[str, str] = {}
    if env_path.exists() and not reset:
        console.print(f"[yellow]Found existing {env_path} — values will be pre-filled.[/yellow]\n")
        existing = _load_existing_env(env_path)
    elif env_path.exists() and reset:
        console.print(f"[yellow]--reset: overwriting {env_path}.[/yellow]\n")

    def get(key: str, default: str = "") -> str:
        return existing.get(key, default)

    def ask(prompt: str, default: str, secret: bool = False) -> str:
        return _ask(prompt, default, secret, non_interactive)

    def ask_choice(prompt: str, choices: list[str], default: str) -> str:
        return _ask_choice(prompt, choices, default, non_interactive)

    cfg: dict[str, str] = {}

    # ── 1 / 5  LLM Backend ───────────────────────────────────────────────────
    console.print(Rule("[bold]1 / 5  LLM Backend[/bold]", style="dim"))
    console.print(
        "  [dim]anthropic[/dim]     — Anthropic API key (recommended)\n"
        "  [dim]oauth[/dim]         — Claude Pro/Max via OAuth (no API key needed)\n"
        "  [dim]openrouter[/dim]    — OpenRouter (access many models)\n"
        "  [dim]openai_compat[/dim] — Any OpenAI-compatible endpoint\n"
        "  [dim]local[/dim]         — Local vLLM / LM Studio at localhost:8000\n"
        "  [dim]minimax[/dim]       — Minimax\n"
    )
    backend = ask_choice(
        "LLM_BACKEND",
        ["anthropic", "oauth", "openrouter", "openai_compat", "local", "minimax"],
        get("LLM_BACKEND", "anthropic"),
    )
    cfg["LLM_BACKEND"] = backend

    # ── 2 / 5  API Credentials ────────────────────────────────────────────────
    console.print()
    console.print(Rule("[bold]2 / 5  API Credentials[/bold]", style="dim"))

    if backend == "anthropic":
        cfg["ANTHROPIC_API_KEY"] = ask(
            "  ANTHROPIC_API_KEY",
            get("ANTHROPIC_API_KEY", "sk-ant-..."),
            secret=True,
        )
        cfg["ANTHROPIC_AUTH_MODE"] = "api_key"
        cfg["CCPROXY_PORT"] = get("CCPROXY_PORT", "8000")
        cfg["ANTHROPIC_BASE_URL"] = ask(
            "  ANTHROPIC_BASE_URL (leave blank for default)",
            get("ANTHROPIC_BASE_URL", ""),
        )

    elif backend == "oauth":
        console.print(
            "  [dim]OAuth — no API key needed.\n"
            "  Prerequisite:  [bold]ccproxy auth login claude_api[/bold][/dim]"
        )
        cfg["ANTHROPIC_AUTH_MODE"] = "oauth"
        cfg["ANTHROPIC_API_KEY"] = get("ANTHROPIC_API_KEY", "")
        cfg["CCPROXY_PORT"] = ask("  CCPROXY_PORT", get("CCPROXY_PORT", "8000"))
        cfg["ANTHROPIC_BASE_URL"] = ask(
            "  ANTHROPIC_BASE_URL (leave blank for default)",
            get("ANTHROPIC_BASE_URL", ""),
        )

    elif backend == "openrouter":
        cfg["OPENAI_COMPAT_API_KEY"] = ask(
            "  OPENAI_COMPAT_API_KEY (sk-or-...)",
            get("OPENAI_COMPAT_API_KEY", "sk-or-..."),
            secret=True,
        )
        cfg["OPENAI_COMPAT_MODEL"] = ask(
            "  OPENAI_COMPAT_MODEL",
            get("OPENAI_COMPAT_MODEL", "meta-llama/llama-3.1-70b-instruct"),
        )
        cfg["OPENAI_COMPAT_BASE_URL"] = "https://openrouter.ai/api/v1"
        cfg["ANTHROPIC_AUTH_MODE"] = get("ANTHROPIC_AUTH_MODE", "api_key")
        cfg["CCPROXY_PORT"] = get("CCPROXY_PORT", "8000")
        cfg["ANTHROPIC_BASE_URL"] = get("ANTHROPIC_BASE_URL", "")

    elif backend == "openai_compat":
        cfg["OPENAI_COMPAT_BASE_URL"] = ask(
            "  OPENAI_COMPAT_BASE_URL",
            get("OPENAI_COMPAT_BASE_URL", "http://localhost:8000/v1"),
        )
        cfg["OPENAI_COMPAT_API_KEY"] = ask(
            "  OPENAI_COMPAT_API_KEY (leave blank if not required)",
            get("OPENAI_COMPAT_API_KEY", ""),
            secret=True,
        )
        cfg["OPENAI_COMPAT_MODEL"] = ask(
            "  OPENAI_COMPAT_MODEL",
            get("OPENAI_COMPAT_MODEL", ""),
        )
        cfg["ANTHROPIC_AUTH_MODE"] = get("ANTHROPIC_AUTH_MODE", "api_key")
        cfg["CCPROXY_PORT"] = get("CCPROXY_PORT", "8000")
        cfg["ANTHROPIC_BASE_URL"] = get("ANTHROPIC_BASE_URL", "")

    elif backend == "local":
        cfg["OPENAI_COMPAT_MODEL"] = ask(
            "  OPENAI_COMPAT_MODEL",
            get("OPENAI_COMPAT_MODEL", "Qwen/Qwen2.5-72B-Instruct"),
        )
        cfg["OPENAI_COMPAT_BASE_URL"] = get("OPENAI_COMPAT_BASE_URL", "http://localhost:8000/v1")
        cfg["ANTHROPIC_AUTH_MODE"] = get("ANTHROPIC_AUTH_MODE", "api_key")
        cfg["CCPROXY_PORT"] = get("CCPROXY_PORT", "8000")
        cfg["ANTHROPIC_BASE_URL"] = get("ANTHROPIC_BASE_URL", "")

    elif backend == "minimax":
        cfg["MINIMAX_API_KEY"] = ask(
            "  MINIMAX_API_KEY", get("MINIMAX_API_KEY", ""), secret=True
        )
        cfg["MINIMAX_MODEL"] = ask(
            "  MINIMAX_MODEL", get("MINIMAX_MODEL", "MiniMax-Text-01")
        )
        cfg["ANTHROPIC_AUTH_MODE"] = get("ANTHROPIC_AUTH_MODE", "api_key")
        cfg["CCPROXY_PORT"] = get("CCPROXY_PORT", "8000")
        cfg["ANTHROPIC_BASE_URL"] = get("ANTHROPIC_BASE_URL", "")

    # Model selection (for Anthropic-family backends)
    if backend in ("anthropic", "oauth"):
        console.print()
        console.print(
            "  [dim]Main model: [bold]claude-sonnet-4-6[/bold] (fast) | "
            "[bold]claude-opus-4-6[/bold] (deep reasoning)[/dim]"
        )
        cfg["EUREKACLAW_MODEL"] = ask(
            "  EUREKACLAW_MODEL",
            get("EUREKACLAW_MODEL", "claude-sonnet-4-6"),
        )
        cfg["EUREKACLAW_FAST_MODEL"] = ask(
            "  EUREKACLAW_FAST_MODEL",
            get("EUREKACLAW_FAST_MODEL", "claude-haiku-4-5-20251001"),
        )

    # ── 3 / 5  Search & Tool APIs ─────────────────────────────────────────────
    console.print()
    console.print(Rule("[bold]3 / 5  Search & Tool APIs[/bold] [dim](all optional — leave blank to skip)[/dim]", style="dim"))

    cfg["BRAVE_SEARCH_API_KEY"] = ask(
        "  BRAVE_SEARCH_API_KEY", get("BRAVE_SEARCH_API_KEY", ""), secret=True
    )
    cfg["SERPAPI_KEY"] = ask(
        "  SERPAPI_KEY", get("SERPAPI_KEY", ""), secret=True
    )
    cfg["WOLFRAM_APP_ID"] = ask(
        "  WOLFRAM_APP_ID", get("WOLFRAM_APP_ID", ""), secret=True
    )
    cfg["S2_API_KEY"] = ask(
        "  S2_API_KEY (Semantic Scholar)", get("S2_API_KEY", ""), secret=True
    )

    # ── 4 / 5  System Behaviour ───────────────────────────────────────────────
    console.print()
    console.print(Rule("[bold]4 / 5  System Behaviour[/bold]", style="dim"))

    cfg["OUTPUT_FORMAT"] = ask_choice(
        "OUTPUT_FORMAT",
        ["latex", "markdown"],
        get("OUTPUT_FORMAT", "latex"),
    )
    cfg["GATE_MODE"] = ask_choice(
        "GATE_MODE  (auto=cards shown; human=prompt every stage; none=silent)",
        ["auto", "human", "none"],
        get("GATE_MODE", "auto"),
    )
    cfg["EUREKACLAW_MODE"] = ask_choice(
        "EUREKACLAW_MODE",
        ["skills_only", "rl", "madmax"],
        get("EUREKACLAW_MODE", "skills_only"),
    )
    cfg["THEORY_PIPELINE"] = ask_choice(
        "THEORY_PIPELINE  (default=literature-first; memory_guided=analysis-first)",
        ["default", "memory_guided"],
        get("THEORY_PIPELINE", "default"),
    )
    cfg["EXPERIMENT_MODE"] = ask_choice(
        "EXPERIMENT_MODE  (auto=when bounds present; true=always; false=never)",
        ["auto", "true", "false"],
        get("EXPERIMENT_MODE", "auto"),
    )
    cfg["EUREKACLAW_DIR"] = ask(
        "  EUREKACLAW_DIR",
        get("EUREKACLAW_DIR", "~/.eurekaclaw"),
    )

    # ── 4b / 5  Advanced tuning (optional) ───────────────────────────────────
    console.print()
    do_advanced = not non_interactive and click.confirm(
        "  Configure advanced settings (proof quality, paper reader, token limits)?",
        default=False,
    )
    if do_advanced:
        console.print()
        console.print(Rule("[dim]Advanced: Proof Quality[/dim]", style="dim"))
        cfg["AUTO_VERIFY_CONFIDENCE"] = ask(
            "  AUTO_VERIFY_CONFIDENCE",
            get("AUTO_VERIFY_CONFIDENCE", "0.95"),
        )
        cfg["VERIFIER_PASS_CONFIDENCE"] = ask(
            "  VERIFIER_PASS_CONFIDENCE",
            get("VERIFIER_PASS_CONFIDENCE", "0.90"),
        )
        cfg["ENFORCE_PROOF_STYLE"] = ask_choice(
            "ENFORCE_PROOF_STYLE  (step-by-step proof rules + highlights)",
            ["true", "false"],
            get("ENFORCE_PROOF_STYLE", "true"),
        )
        cfg["STAGNATION_WINDOW"] = ask(
            "  STAGNATION_WINDOW",
            get("STAGNATION_WINDOW", "3"),
        )
        cfg["THEORY_MAX_ITERATIONS"] = ask(
            "  THEORY_MAX_ITERATIONS",
            get("THEORY_MAX_ITERATIONS", "10"),
        )
        cfg["THEORY_REVIEW_MAX_RETRIES"] = ask(
            "  THEORY_REVIEW_MAX_RETRIES",
            get("THEORY_REVIEW_MAX_RETRIES", "3"),
        )

        console.print()
        console.print(Rule("[dim]Advanced: Paper Reader[/dim]", style="dim"))
        cfg["PAPER_READER_USE_PDF"] = ask_choice(
            "PAPER_READER_USE_PDF",
            ["true", "false"],
            get("PAPER_READER_USE_PDF", "true"),
        )
        cfg["PAPER_READER_ABSTRACT_PAPERS"] = ask(
            "  PAPER_READER_ABSTRACT_PAPERS",
            get("PAPER_READER_ABSTRACT_PAPERS", "10"),
        )
        cfg["PAPER_READER_PDF_PAPERS"] = ask(
            "  PAPER_READER_PDF_PAPERS",
            get("PAPER_READER_PDF_PAPERS", "3"),
        )

        console.print()
        console.print(Rule("[dim]Advanced: Token Limits[/dim]", style="dim"))
        token_keys = [
            ("MAX_TOKENS_AGENT", "8192"),
            ("MAX_TOKENS_PROVER", "4096"),
            ("MAX_TOKENS_PLANNER", "4096"),
            ("MAX_TOKENS_DECOMPOSER", "4096"),
            ("MAX_TOKENS_FORMALIZER", "4096"),
            ("MAX_TOKENS_VERIFIER", "2048"),
            ("MAX_TOKENS_CRYSTALLIZER", "4096"),
            ("MAX_TOKENS_ASSEMBLER", "6000"),
            ("MAX_TOKENS_ARCHITECT", "3000"),
            ("MAX_TOKENS_ANALYST", "1600"),
            ("MAX_TOKENS_SKETCH", "1024"),
            ("MAX_TOKENS_COMPRESS", "1024"),
        ]
        for key, default in token_keys:
            cfg[key] = ask(f"  {key}", get(key, default))

        console.print()
        console.print(Rule("[dim]Advanced: Agent Loop[/dim]", style="dim"))
        cfg["CONTEXT_COMPRESS_AFTER_TURNS"] = ask(
            "  CONTEXT_COMPRESS_AFTER_TURNS",
            get("CONTEXT_COMPRESS_AFTER_TURNS", "6"),
        )
        cfg["SURVEY_MAX_TURNS"] = ask(
            "  SURVEY_MAX_TURNS", get("SURVEY_MAX_TURNS", "8")
        )
        cfg["THEORY_STAGE_MAX_TURNS"] = ask(
            "  THEORY_STAGE_MAX_TURNS", get("THEORY_STAGE_MAX_TURNS", "6")
        )
        cfg["WRITER_MAX_TURNS"] = ask(
            "  WRITER_MAX_TURNS", get("WRITER_MAX_TURNS", "4")
        )
        cfg["ARXIV_MAX_RESULTS"] = ask(
            "  ARXIV_MAX_RESULTS", get("ARXIV_MAX_RESULTS", "10")
        )
        cfg["LLM_RETRY_ATTEMPTS"] = ask(
            "  LLM_RETRY_ATTEMPTS", get("LLM_RETRY_ATTEMPTS", "5")
        )
        cfg["LLM_RETRY_WAIT_MIN"] = ask(
            "  LLM_RETRY_WAIT_MIN", get("LLM_RETRY_WAIT_MIN", "4")
        )
        cfg["LLM_RETRY_WAIT_MAX"] = ask(
            "  LLM_RETRY_WAIT_MAX", get("LLM_RETRY_WAIT_MAX", "90")
        )

    # ── 5 / 5  Write .env ────────────────────────────────────────────────────
    console.print()
    console.print(Rule("[bold]5 / 5  Writing .env[/bold]", style="dim"))

    merged = {**existing, **cfg}
    _write_env(env_path, merged)
    console.print(f"[green]✓ Written:[/green] {env_path.resolve()}")

    # ── Install skills ────────────────────────────────────────────────────────
    console.print()
    do_install = non_interactive or click.confirm(
        "  Install built-in skills now? (recommended for first-time setup)",
        default=True,
    )
    if do_install:
        console.print("[dim]Running install-skills...[/dim]")
        from eurekaclaw.skills.registry import _SEED_DIR
        from eurekaclaw.utils import copy_file
        from eurekaclaw.config import settings

        settings.ensure_dirs()
        dest = settings.skills_dir
        count = 0
        for src in sorted(_SEED_DIR.rglob("*.md")):
            if copy_file(src, dest, overwrite=False):
                count += 1
        console.print(f"[green]✓ Installed {count} skill(s) to {dest}[/green]")

    # ── Done ──────────────────────────────────────────────────────────────────
    console.print()
    console.print(Rule("[bold green]Onboarding complete![/bold green]"))
    console.print(
        f"\n  Config saved to: [cyan]{env_path.resolve()}[/cyan]\n\n"
        "  Next steps:\n"
        "    [bold]eurekaclaw prove[/bold] \"Your conjecture here\"\n"
        "    [bold]eurekaclaw explore[/bold] \"A research domain\"\n"
    )
