"""eurekaclaw onboard — interactive .env configuration wizard."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

import click
from rich.console import Console
from rich.rule import Rule

if TYPE_CHECKING:
    pass

console = Console()


def _load_existing_env(env_path: Path) -> dict[str, str]:
    existing: dict[str, str] = {}
    for line in env_path.read_text().splitlines():
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
    display = "  " + prompt + "  [" + "|".join(
        f"[bold]{c}[/bold]" if c == default else c for c in choices
    ) + "]"
    console.print(display)
    while True:
        val = click.prompt("  >", default=default)
        if val in choices:
            return val
        console.print(f"  [red]Invalid. Choose one of: {', '.join(choices)}[/red]")


def _write_env(env_path: Path, merged: dict[str, str]) -> None:
    """Write merged config to env_path, preserving .env.example structure."""
    env_example = Path(__file__).parent.parent / ".env.example"
    if env_example.exists():
        lines: list[str] = []
        seen: set[str] = set()
        for raw in env_example.read_text().splitlines():
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
    env_path.write_text(output)


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
        "Backend",
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

    elif backend == "oauth":
        console.print(
            "  [dim]OAuth — no API key needed.\n"
            "  Prerequisite:  [bold]ccproxy auth login claude_api[/bold][/dim]"
        )
        cfg["ANTHROPIC_AUTH_MODE"] = "oauth"
        cfg["ANTHROPIC_API_KEY"] = get("ANTHROPIC_API_KEY", "")
        cfg["CCPROXY_PORT"] = ask("  CCPROXY_PORT", get("CCPROXY_PORT", "8000"))

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

    elif backend == "local":
        cfg["OPENAI_COMPAT_MODEL"] = ask(
            "  OPENAI_COMPAT_MODEL",
            get("OPENAI_COMPAT_MODEL", "Qwen/Qwen2.5-72B-Instruct"),
        )
        cfg["OPENAI_COMPAT_BASE_URL"] = get("OPENAI_COMPAT_BASE_URL", "http://localhost:8000/v1")

    elif backend == "minimax":
        cfg["MINIMAX_API_KEY"] = ask(
            "  MINIMAX_API_KEY", get("MINIMAX_API_KEY", ""), secret=True
        )
        cfg["MINIMAX_MODEL"] = ask(
            "  MINIMAX_MODEL", get("MINIMAX_MODEL", "MiniMax-Text-01")
        )

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
    cfg["EUREKACLAW_DIR"] = ask(
        "  EUREKACLAW_DIR",
        get("EUREKACLAW_DIR", "~/.eurekaclaw"),
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
