"""EurekaClaw CLI entry point."""

from __future__ import annotations

import asyncio
import json
import logging
import sys
from pathlib import Path

import click
from rich.console import Console
from rich.logging import RichHandler
from rich.panel import Panel

from eurekaclaw.config import settings

console = Console()


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(message)s",
        handlers=[RichHandler(console=console, rich_tracebacks=True, show_path=False)],
    )
    logging.getLogger("anthropic").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)


@click.group()
@click.option("--verbose", "-v", is_flag=True, help="Enable debug logging")
def main(verbose: bool) -> None:
    """EurekaClaw — Multi-agent system for theoretical research."""
    setup_logging(verbose)


@main.command()
@click.argument("conjecture")
@click.option("--domain", "-d", default="", help="Research domain (auto-inferred if omitted)")
@click.option("--mode", default="skills_only", type=click.Choice(["skills_only", "rl", "madmax"]))
@click.option("--gate", default="none", type=click.Choice(["human", "auto", "none"]))
@click.option("--output", "-o", default="", help="Output directory for artifacts")
def prove(conjecture: str, domain: str, mode: str, gate: str, output: str) -> None:
    """Level 1: Prove a specific conjecture.

    Example: eurekaclaw prove "The sample complexity of transformers is O(L*d*log(d)/eps^2)"
    """
    _run_session(
        mode="detailed",
        query=conjecture,
        conjecture=conjecture,
        domain=domain,
        learn_mode=mode,
        gate=gate,
        output_dir=output,
    )


@main.command()
@click.argument("domain")
@click.option("--query", "-q", default="", help="Specific research question")
@click.option("--mode", default="skills_only", type=click.Choice(["skills_only", "rl", "madmax"]))
@click.option("--gate", default="none", type=click.Choice(["human", "auto", "none"]))
@click.option("--output", "-o", default="", help="Output directory for artifacts")
def explore(domain: str, query: str, mode: str, gate: str, output: str) -> None:
    """Level 3: Open exploration of a research domain.

    Example: eurekaclaw explore "sample complexity of transformers"
    """
    _run_session(mode="exploration", query=query or domain, domain=domain, learn_mode=mode, gate=gate, output_dir=output)


@main.command()
@click.argument("paper_ids", nargs=-1)
@click.option("--domain", "-d", required=True, help="Research domain")
@click.option("--mode", default="skills_only")
@click.option("--gate", default="none", type=click.Choice(["human", "auto", "none"]))
def from_papers(paper_ids: tuple[str, ...], domain: str, mode: str, gate: str) -> None:
    """Level 2: Generate hypotheses from reference papers.

    Example: eurekaclaw from-papers 2301.12345 2302.67890 --domain "ML theory"
    """
    _run_session(
        mode="reference",
        query=f"Find gaps in {domain}",
        domain=domain,
        paper_ids=list(paper_ids),
        learn_mode=mode,
        gate=gate,
    )


@main.command()
def skills() -> None:
    """List all available skills in the skills bank."""
    from eurekaclaw.skills.registry import SkillRegistry
    registry = SkillRegistry()
    all_skills = registry.load_all()

    console.print(Panel(
        f"[bold]{len(all_skills)} skills loaded[/bold]\n\n" +
        "\n".join(
            f"• [cyan]{s.meta.name}[/cyan] ({', '.join(s.meta.tags[:3])}) — {s.meta.description[:60]}"
            for s in sorted(all_skills, key=lambda x: x.meta.name)
        ),
        title="[green]EurekaClaw Skills Bank[/green]",
    ))


@main.command()
@click.argument("session_id")
def eval_session(session_id: str) -> None:
    """Evaluate a completed research session."""
    from eurekaclaw.evaluation.evaluator import ScientistBenchEvaluator
    from eurekaclaw.knowledge_bus.bus import KnowledgeBus

    session_dir = settings.runs_dir / session_id
    if not session_dir.exists():
        console.print(f"[red]Session not found: {session_dir}[/red]")
        sys.exit(1)

    bus = KnowledgeBus.load(session_id, session_dir)
    evaluator = ScientistBenchEvaluator()

    async def run_eval():
        return await evaluator.evaluate(bus)

    report = asyncio.run(run_eval())
    console.print(Panel(
        json.dumps(report.to_dict(), indent=2),
        title=f"[green]Evaluation Report: {session_id[:8]}[/green]",
    ))


@main.command()
@click.option("--force", "-f", is_flag=True, help="Overwrite skills that are already installed.")
def install_skills(force: bool) -> None:
    """Copy seed skills to ~/.eurekaclaw/skills/.

    Skips files that already exist unless --force is given.
    """
    from eurekaclaw.skills.registry import _SEED_DIR
    import shutil

    settings.ensure_dirs()
    dest = settings.skills_dir

    count = 0
    skipped = 0
    for src in sorted(_SEED_DIR.rglob("*.md")):
        dst = dest / src.name
        if dst.exists() and not force:
            skipped += 1
            continue
        shutil.copy2(src, dst)
        count += 1
        console.print(f"  {'Updated' if dst.exists() else 'Installed'}: {src.name}")

    console.print(f"[green]Installed {count} seed skills to {dest}[/green]")
    if skipped:
        console.print(f"[dim]Skipped {skipped} already-installed skills (use --force to overwrite)[/dim]")


@main.command()
@click.option("--host", default="127.0.0.1", help="Host to bind the UI server to.")
@click.option("--port", default=8080, type=int, help="Port to bind the UI server to.")
@click.option("--open-browser/--no-open-browser", default=False, help="Open the UI in the default browser.")
def ui(host: str, port: int, open_browser: bool) -> None:
    """Launch the EurekaClaw browser UI."""
    import threading
    import time
    import webbrowser

    from eurekaclaw.ui.server import serve_ui

    console.print(f"[green]Starting EurekaClaw UI on http://{host}:{port}[/green]")

    if open_browser:
        def _open() -> None:
            time.sleep(1.0)
            webbrowser.open(f"http://{host}:{port}/")

        threading.Thread(target=_open, daemon=True).start()

    serve_ui(host=host, port=port)


def _compile_pdf(tex_path: Path) -> None:
    """Run pdflatex twice on tex_path to resolve cross-references.

    Strategy:
    1. Normal compile with -interaction=nonstopmode (ignores most errors, continues).
    2. If no PDF is produced (truly fatal LaTeX error), generate a rescue document
       that is guaranteed to compile and contains the key content as plain text.
    """
    import subprocess

    latex_bin = settings.latex_bin  # "pdflatex" by default
    out_dir = tex_path.parent
    pdf_path = out_dir / tex_path.with_suffix(".pdf").name

    try:
        cmd = [latex_bin, "-interaction=nonstopmode", "-output-directory", str(out_dir.resolve()), str(tex_path.resolve())]
        for _ in range(2):  # two passes for refs/TOC
            subprocess.run(cmd, capture_output=True, check=False, cwd=out_dir.resolve())

        if pdf_path.exists():
            console.print(f"[green]PDF generated: {pdf_path}[/green]")
        else:
            console.print("[yellow]pdflatex: fatal errors prevented PDF output — attempting rescue compile...[/yellow]")
            _show_latex_errors(out_dir / tex_path.with_suffix(".log").name)
            _rescue_compile(tex_path, pdf_path, latex_bin, out_dir)
    except FileNotFoundError:
        console.print(
            f"[yellow]PDF generation skipped: '{latex_bin}' not found. "
            "Install TeX Live or set LATEX_BIN in .env.[/yellow]"
        )


def _rescue_compile(original_tex: Path, pdf_path: Path, latex_bin: str, out_dir: Path) -> None:
    """Build a guaranteed-compilable fallback PDF from the original .tex source.

    Extracts the title and raw body text (stripping all LaTeX commands) and
    wraps them in a minimal, error-free document.  The result is labelled
    'Draft (rescue compile)' so the user knows it is a fallback.
    """
    import re
    import subprocess

    try:
        src = original_tex.read_text(errors="replace")
    except Exception:
        src = ""

    # Extract title from \title{...}
    title_match = re.search(r"\\title\{([^}]*)\}", src)
    title = title_match.group(1) if title_match else "Research Paper"

    # Extract body between \begin{document} and \end{document}
    body_match = re.search(r"\\begin\{document\}(.*?)\\end\{document\}", src, re.DOTALL)
    raw_body = body_match.group(1) if body_match else src

    # Strip LaTeX commands to get plain text (best-effort)
    plain = re.sub(r"\\[a-zA-Z]+\*?\{[^}]*\}", " ", raw_body)   # \cmd{arg}
    plain = re.sub(r"\\[a-zA-Z]+\*?", " ", plain)                # \cmd
    plain = re.sub(r"[{}$^_&]", " ", plain)                      # special chars
    plain = re.sub(r"\s{2,}", "\n\n", plain).strip()
    # Truncate to avoid overfull pages in the rescue doc
    plain = plain[:6000]

    # Escape percent signs (only special char that survives above and breaks LaTeX)
    plain_escaped = plain.replace("%", r"\%")

    rescue_tex = rf"""\nonstopmode
\documentclass[12pt]{{article}}
\usepackage[T1]{{fontenc}}
\usepackage[margin=1in]{{geometry}}
\title{{{title} \\ \large Draft (rescue compile --- original LaTeX had fatal errors)}}
\author{{EurekaClaw}}
\date{{\today}}
\begin{{document}}
\maketitle
\begin{{verbatim}}
{plain[:5000]}
\end{{verbatim}}
\end{{document}}
"""
    rescue_path = out_dir / "paper_rescue.tex"
    rescue_path.write_text(rescue_tex, encoding="utf-8")

    import subprocess
    abs_out = out_dir.resolve()
    cmd = [latex_bin, "-interaction=nonstopmode", "-output-directory", str(abs_out), str(rescue_path.resolve())]
    for _ in range(2):
        subprocess.run(cmd, capture_output=True, check=False, cwd=abs_out)

    rescue_pdf = out_dir / "paper_rescue.pdf"
    if rescue_pdf.exists():
        rescue_pdf.rename(pdf_path)
        console.print(f"[yellow]Rescue PDF generated (plain-text fallback): {pdf_path}[/yellow]")
    else:
        console.print(f"[red]Rescue compile also failed. Check {out_dir}/paper_rescue.log[/red]")


def _show_latex_errors(log_path: Path) -> None:
    """Extract and print error lines from a pdflatex .log file."""
    if not log_path.exists():
        console.print(f"[yellow]  No log file found at {log_path}[/yellow]")
        return
    errors = []
    try:
        lines = log_path.read_text(errors="replace").splitlines()
        for i, line in enumerate(lines):
            if line.startswith("!") or (line.startswith("l.") and errors):
                errors.append(line)
                # include the next two context lines pdflatex prints after "!"
                errors.extend(lines[i + 1 : i + 3])
        if errors:
            console.print("[yellow]  LaTeX errors:[/yellow]")
            for err in errors[:20]:  # cap at 20 lines
                console.print(f"[red]  {err}[/red]")
        else:
            console.print(f"[yellow]  No explicit errors found in log. Full log: {log_path}[/yellow]")
    except Exception as exc:
        console.print(f"[yellow]  Could not read log file: {exc}[/yellow]")


def _run_session(
    mode: str,
    query: str,
    domain: str,
    conjecture: str | None = None,
    paper_ids: list[str] | None = None,
    learn_mode: str = "skills_only",
    gate: str = "human",
    output_dir: str = "",
) -> None:
    """Common session runner."""
    import os
    from eurekaclaw.main import EurekaSession, save_artifacts
    from eurekaclaw.types.tasks import InputSpec

    # Override the settings singleton in-place so all already-imported modules
    # see the new values (importlib.reload would create a new object that old
    # references wouldn't see).
    os.environ["EUREKACLAW_MODE"] = learn_mode
    os.environ["GATE_MODE"] = gate
    settings.eurekaclaw_mode = learn_mode  # type: ignore[misc]
    settings.gate_mode = gate  # type: ignore[misc]

    # --- ccproxy: start if ANTHROPIC_AUTH_MODE=oauth -------------------------
    _ccproxy_proc = None
    if settings.anthropic_auth_mode == "oauth":
        try:
            from eurekaclaw.ccproxy_manager import maybe_start_ccproxy, stop_ccproxy
            _ccproxy_proc = maybe_start_ccproxy()
            if _ccproxy_proc:
                import atexit
                atexit.register(stop_ccproxy, _ccproxy_proc)
        except (RuntimeError, ValueError) as exc:
            console.print(f"[red]ccproxy error: {exc}[/red]")
            sys.exit(1)

    spec = InputSpec(
        mode=mode,  # type: ignore[arg-type]
        query=query,
        conjecture=conjecture,
        domain=domain,
        paper_ids=paper_ids or [],
    )

    session = EurekaSession()
    result = asyncio.run(session.run(spec))

    if output_dir:
        out = save_artifacts(result, output_dir)
        console.print(f"[green]Artifacts saved to {out}[/green]")


if __name__ == "__main__":
    main()
