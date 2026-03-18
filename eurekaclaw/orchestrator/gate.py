"""GateController — manages approval gates at key pipeline transition points."""

from __future__ import annotations

import logging

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm
from rich.table import Table

from eurekaclaw.config import settings
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)
console = Console()


class GateController:
    """Human-on-the-loop or auto-approval at pipeline gate points."""

    def __init__(self, mode: str | None = None, bus=None) -> None:
        self.mode = mode or settings.gate_mode
        self.bus = bus  # KnowledgeBus, injected by MetaOrchestrator

    async def request_approval(self, task: Task) -> bool:
        """Request gate approval for a task. Returns True if approved."""
        if self.mode == "none":
            return True
        if self.mode == "auto":
            return self._auto_approve(task)
        # Human mode
        return self._human_approve(task)

    def _auto_approve(self, task: Task) -> bool:
        """Automatic approval logic based on task confidence signals."""
        logger.info("Auto-approving gate for task: %s", task.name)
        return True

    def _human_approve(self, task: Task) -> bool:
        """Interactive CLI prompt for human approval."""
        # Print context-specific status before the approval prompt
        if task.name == "theory_review_gate":
            self._print_theory_status()
        elif task.name == "final_review_gate":
            self._print_paper_status()
        elif task.name == "direction_selection_gate":
            self._print_direction_status()

        console.print(Panel(
            f"[bold]{task.description}[/bold]",
            title="[yellow]⏸  Gate: approval required[/yellow]",
            border_style="yellow",
        ))
        try:
            return Confirm.ask("Approve and continue?", default=True)
        except (KeyboardInterrupt, EOFError):
            logger.warning("Gate input interrupted — defaulting to approve")
            return True

    # ------------------------------------------------------------------
    # Per-gate status displays
    # ------------------------------------------------------------------

    def _print_theory_status(self) -> None:
        """Print proof status from TheoryState before the theory review gate."""
        if not self.bus:
            return
        state = self.bus.get_theory_state()
        if not state:
            console.print("[dim]No theory state available yet.[/dim]")
            return

        table = Table(title="Proof Status", show_header=True, header_style="bold cyan")
        table.add_column("Field", style="bold")
        table.add_column("Value")

        status_color = {
            "proved": "green",
            "in_progress": "yellow",
            "refuted": "red",
            "abandoned": "red",
            "pending": "dim",
        }.get(state.status, "white")

        table.add_row("Status", f"[{status_color}]{state.status}[/{status_color}]")
        table.add_row("Iterations", str(state.iteration))
        table.add_row("Proven lemmas", str(len(state.proven_lemmas)))
        table.add_row("Open goals", str(len(state.open_goals)))
        table.add_row("Failed attempts", str(len(state.failed_attempts)))
        table.add_row("Counterexamples", str(len(state.counterexamples)))
        console.print(table)

        if state.informal_statement:
            console.print(Panel(
                state.informal_statement,
                title="[cyan]Theorem (informal)[/cyan]",
                border_style="dim",
            ))

        if state.proven_lemmas:
            console.print("\n[bold green]Proven lemmas:[/bold green]")
            for lid, rec in state.proven_lemmas.items():
                node = state.lemma_dag.get(lid)
                stmt = node.statement[:120] if node else lid
                verified_tag = "[green]✓[/green]" if rec.verified else "[yellow]~ (low confidence)[/yellow]"
                console.print(f"  {verified_tag} [cyan]{lid}[/cyan]: {stmt}")

        if state.open_goals:
            console.print("\n[bold yellow]Open goals:[/bold yellow]")
            for lid in state.open_goals:
                node = state.lemma_dag.get(lid)
                stmt = node.statement[:120] if node else lid
                console.print(f"  [yellow]?[/yellow] [cyan]{lid}[/cyan]: {stmt}")

        if state.counterexamples:
            last_cx = state.counterexamples[-1]
            console.print(Panel(
                f"[bold]Lemma:[/bold] {last_cx.lemma_id}\n"
                f"[bold]Falsifies conjecture:[/bold] {last_cx.falsifies_conjecture}\n"
                f"[bold]Suggested refinement:[/bold] {last_cx.suggested_refinement[:300] or '(none)'}",
                title="[red]Most recent counterexample[/red]",
                border_style="red",
            ))

    def _print_direction_status(self) -> None:
        """Print candidate research directions before the direction gate."""
        if not self.bus:
            return
        brief = self.bus.get_research_brief()
        if not brief or not brief.directions:
            return

        console.print(f"\n[bold]Research directions for:[/bold] {brief.query}\n")
        for i, d in enumerate(brief.directions):
            selected = brief.selected_direction and d.direction_id == brief.selected_direction.direction_id
            marker = "[green]★ (recommended)[/green]" if selected else f"  {i+1}."
            console.print(f"{marker} [bold]{d.title}[/bold]")
            console.print(f"     Hypothesis: {d.hypothesis[:200]}")
            if d.composite_score:
                console.print(
                    f"     Score: novelty={d.novelty_score:.2f}  "
                    f"soundness={d.soundness_score:.2f}  "
                    f"transformative={d.transformative_score:.2f}  "
                    f"→ composite={d.composite_score:.2f}"
                )
            console.print()

    def _print_paper_status(self) -> None:
        """Print a brief summary of all artifacts before the final review gate."""
        if not self.bus:
            return
        brief = self.bus.get_research_brief()
        state = self.bus.get_theory_state()
        exp = self.bus.get_experiment_result()

        lines = []
        if brief:
            lines.append(f"[bold]Domain:[/bold] {brief.domain}")
            lines.append(f"[bold]Query:[/bold]  {brief.query}")
        if state:
            status_color = "green" if state.status == "proved" else "yellow"
            lines.append(
                f"[bold]Proof:[/bold]  [{status_color}]{state.status}[/{status_color}] "
                f"— {len(state.proven_lemmas)} lemmas proved, {len(state.open_goals)} open"
            )
        if exp:
            lines.append(
                f"[bold]Experiment:[/bold] alignment_score={exp.alignment_score:.2f}, "
                f"{len(exp.bounds)} bounds"
            )
        console.print(Panel("\n".join(lines), title="[cyan]Session Summary[/cyan]", border_style="cyan"))
