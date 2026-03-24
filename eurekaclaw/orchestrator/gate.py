"""GateController — summary cards, human intervention, and confidence-based auto-escalation."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.table import Table

from eurekaclaw.config import settings
from eurekaclaw.types.tasks import Task

from eurekaclaw.console import console

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

# Stored per-session so later stages can access user feedback from earlier stages.
_user_feedback: dict[str, str] = {}


def get_user_feedback(stage: str) -> str | None:
    """Retrieve feedback the user typed at a previous gate."""
    return _user_feedback.get(stage)


class GateController:
    """Human-on-the-loop or auto-approval at pipeline gate points.

    gate_mode:
      "none"  — silent: no cards, no prompts (fully autonomous)
      "auto"  — cards always printed; prompts only when confidence is low
      "human" — cards always printed; prompts at every gate
    """

    def __init__(self, mode: str | None = None, bus=None) -> None:
        self.mode = mode or settings.gate_mode
        self.bus = bus

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def print_stage_summary(self, stage_name: str) -> None:
        """Always-on summary card printed after each completed stage.

        Called unconditionally by MetaOrchestrator regardless of gate_mode.
        Gives the user visibility into what just happened without blocking.
        """
        if stage_name == "survey":
            self._print_survey_summary()
        elif stage_name == "theory":
            self._print_theory_status()
        elif stage_name == "experiment":
            self._print_experiment_summary()
        elif stage_name == "writer":
            self._print_paper_status()

    async def request_approval(self, task: Task) -> bool:
        """Request gate approval. Returns True if approved, False to skip."""
        if self.mode == "none":
            return True
        if self.mode == "auto":
            return self._auto_approve(task)
        return self._human_approve(task)

    # ------------------------------------------------------------------
    # Approval logic
    # ------------------------------------------------------------------

    def _auto_approve(self, task: Task) -> bool:
        """Auto-approve unless confidence signals are bad."""
        if task.name == "theory_review_gate":
            low_conf = self._count_low_confidence_lemmas()
            if low_conf > 0:
                console.print(
                    f"\n[yellow]⚠  Auto-gate escalation: {low_conf} lemma(s) have low confidence.[/yellow]"
                )
                console.print("[dim]Switching to human review for this gate.[/dim]\n")
                return self._human_approve(task)
        logger.info("Auto-approving gate: %s", task.name)
        return True

    def _human_approve(self, task: Task) -> bool:
        """Interactive prompt with optional text feedback."""
        # Print context card (may already have been printed by print_stage_summary,
        # but gates like direction_selection don't map to a completed stage)
        if task.name == "direction_selection_gate":
            self._print_direction_status()
        elif task.name == "theory_review_gate":
            self._print_theory_status()
        elif task.name == "final_review_gate":
            self._print_paper_status()

        console.print(Panel(
            f"[bold]{task.description}[/bold]",
            title="[yellow]⏸  Gate: human review[/yellow]",
            border_style="yellow",
        ))

        try:
            approved = Confirm.ask("Continue to next stage?", default=True)
        except (KeyboardInterrupt, EOFError):
            logger.warning("Gate input interrupted — defaulting to approve")
            return True

        if approved:
            # Offer optional feedback that gets injected into the next stage
            try:
                feedback = Prompt.ask(
                    "[dim]Optional: type a correction or hint for the next stage "
                    "(press Enter to skip)[/dim]",
                    default="",
                )
            except (KeyboardInterrupt, EOFError):
                feedback = ""
            if feedback.strip():
                _user_feedback[task.name] = feedback.strip()
                console.print(f"[dim]Feedback recorded — will be passed to next agent.[/dim]")
        else:
            console.print("[yellow]Stage skipped by user.[/yellow]")

        return approved

    # ------------------------------------------------------------------
    # Summary cards (always-on)
    # ------------------------------------------------------------------

    def _print_survey_summary(self) -> None:
        if not self.bus:
            return
        brief = self.bus.get_research_brief()
        if not brief:
            return

        lines = []
        bib = self.bus.get_bibliography()
        n_papers = len(bib.papers) if bib else 0
        
        if n_papers == 0:
            lines.append("[bold red]Papers found:[/bold red] 0")
        else:
            lines.append(f"[bold]Papers found:[/bold] {n_papers}")
            
        if brief.open_problems:
            lines.append(f"[bold]Open problems identified:[/bold] {len(brief.open_problems)}")
            for p in brief.open_problems[:3]:
                lines.append(f"  • {str(p)[:120]}")
            if len(brief.open_problems) > 3:
                lines.append(f"  [dim]… and {len(brief.open_problems) - 3} more[/dim]")
        if brief.key_mathematical_objects:
            lines.append(f"[bold]Key objects:[/bold] " +
                         ", ".join(str(o)[:60] for o in brief.key_mathematical_objects[:5]))
        border = "red" if n_papers == 0 else "cyan"
        console.print(Panel("\n".join(lines), title="[cyan]📚 Survey complete[/cyan]", border_style=border))

    def _print_theory_status(self) -> None:
        if not self.bus:
            return
        state = self.bus.get_theory_state()
        if not state:
            console.print("[dim]No theory state available.[/dim]")
            return

        # Overall status table
        status_color = {
            "proved": "green", "in_progress": "yellow",
            "refuted": "red", "abandoned": "red", "pending": "dim",
        }.get(state.status, "white")

        table = Table(title="Proof Status", show_header=True, header_style="bold cyan")
        table.add_column("Field", style="bold")
        table.add_column("Value")
        table.add_row("Status", f"[{status_color}]{state.status}[/{status_color}]")
        table.add_row("Iterations", str(state.iteration))
        table.add_row("Proven lemmas", str(len(state.proven_lemmas)))
        table.add_row("Open goals", str(len(state.open_goals)))
        table.add_row("Failed attempts", str(len(state.failed_attempts)))
        table.add_row("Counterexamples", str(len(state.counterexamples)))

        # Confidence summary
        low_conf = self._count_low_confidence_lemmas()
        if low_conf:
            table.add_row(
                "Low-confidence lemmas",
                f"[yellow]{low_conf}[/yellow] [dim](not formally verified)[/dim]",
            )
        console.print(table)

        # Theorem statement
        if state.informal_statement:
            console.print(Panel(
                state.informal_statement,
                title="[cyan]Theorem[/cyan]",
                border_style="dim",
            ))

        # Lemma-by-lemma breakdown with confidence
        if state.proven_lemmas:
            console.print("\n[bold]Lemma breakdown:[/bold]")
            for lid, rec in state.proven_lemmas.items():
                node = state.lemma_dag.get(lid)
                stmt = node.statement[:120] if node else lid
                if rec.verified:
                    tag = "[green]✓ proved[/green]"
                else:
                    tag = "[yellow]~ low confidence[/yellow]  [dim](LLM self-assessed; no formal check)[/dim]"
                console.print(f"  {tag} [cyan]{lid}[/cyan]")
                console.print(f"    [dim]{stmt}[/dim]")

        if state.open_goals:
            console.print("\n[bold yellow]Still open:[/bold yellow]")
            for lid in state.open_goals:
                node = state.lemma_dag.get(lid)
                console.print(f"  [yellow]?[/yellow] {node.statement[:100] if node else lid}")

        if state.counterexamples:
            last_cx = state.counterexamples[-1]
            console.print(Panel(
                f"[bold]Affects lemma:[/bold] {last_cx.lemma_id}\n"
                f"[bold]Falsifies conjecture:[/bold] {last_cx.falsifies_conjecture}\n"
                f"[bold]Suggested fix:[/bold] {last_cx.suggested_refinement[:300] or '(none)'}",
                title="[red]⚠  Counterexample found[/red]",
                border_style="red",
            ))

    def _print_experiment_summary(self) -> None:
        if not self.bus:
            return
        exp = self.bus.get_experiment_result()
        if not exp:
            return
        color = "green" if exp.alignment_score >= 0.8 else "yellow" if exp.alignment_score >= 0.5 else "red"
        lines = [
            f"[bold]Alignment score:[/bold] [{color}]{exp.alignment_score:.2f}[/{color}]"
            f"  [dim](1.0 = theory matches simulation perfectly)[/dim]",
        ]
        if exp.bounds:
            lines.append(f"[bold]Bounds verified:[/bold] {len(exp.bounds)}")
            for b in exp.bounds[:3]:
                lines.append(f"  • {str(b)[:120]}")

        # Show per-lemma numerical check results
        lemma_checks = exp.outputs.get("lemma_checks", []) if exp.outputs else []
        if lemma_checks:
            lines.append(f"\n[bold]Low-confidence lemma checks:[/bold]")
            for c in lemma_checks:
                lid = c.get("lemma_id", "?")
                rate = c.get("violation_rate", 0.0)
                n = c.get("n_trials", 0)
                suspect = c.get("numerically_suspect", False)
                if suspect:
                    lines.append(f"  [red]✗ {lid}: violation_rate={rate:.3f} over {n} trials — SUSPECT[/red]")
                else:
                    lines.append(f"  [green]✓ {lid}: violation_rate={rate:.3f} over {n} trials[/green]")

        suspect_lemmas = self.bus.get("numerically_suspect_lemmas") or []
        if suspect_lemmas:
            lines.append(f"\n[red bold]⚠  Suspect lemmas: {', '.join(suspect_lemmas)}[/red bold]")
            lines.append("[dim]These lemmas failed numerical testing — review before publishing.[/dim]")

        border = "red" if suspect_lemmas else "cyan"
        console.print(Panel("\n".join(lines), title="[cyan]🧪 Experiment complete[/cyan]", border_style=border))

    def _print_direction_status(self) -> None:
        if not self.bus:
            return
        brief = self.bus.get_research_brief()
        if not brief or not brief.directions:
            return
        console.print(f"\n[bold]Research directions for:[/bold] {brief.query}\n")
        for i, d in enumerate(brief.directions):
            selected = brief.selected_direction and d.direction_id == brief.selected_direction.direction_id
            marker = "[green]★ recommended[/green]" if selected else f"  {i+1}."
            console.print(f"{marker} [bold]{d.title}[/bold]")
            console.print(f"     {d.hypothesis[:200]}")
            if d.composite_score:
                console.print(
                    f"     [dim]novelty={d.novelty_score:.2f}  "
                    f"soundness={d.soundness_score:.2f}  "
                    f"composite={d.composite_score:.2f}[/dim]"
                )
            console.print()

    def _print_paper_status(self) -> None:
        if not self.bus:
            return
        brief = self.bus.get_research_brief()
        state = self.bus.get_theory_state()
        exp = self.bus.get_experiment_result()

        lines = []
        if brief:
            lines.append(f"[bold]Domain:[/bold]  {brief.domain}")
            lines.append(f"[bold]Query:[/bold]   {brief.query}")
        if state:
            status_color = "green" if state.status == "proved" else "yellow"
            low_conf = self._count_low_confidence_lemmas()
            proof_line = (
                f"[bold]Proof:[/bold]   [{status_color}]{state.status}[/{status_color}]"
                f" — {len(state.proven_lemmas)} lemmas"
            )
            if low_conf:
                proof_line += f", [yellow]{low_conf} low-confidence[/yellow]"
            lines.append(proof_line)
        if exp:
            color = "green" if exp.alignment_score >= 0.8 else "yellow"
            lines.append(
                f"[bold]Experiment:[/bold] [{color}]alignment={exp.alignment_score:.2f}[/{color}]"
            )
        console.print(Panel("\n".join(lines), title="[cyan]📄 Session Summary[/cyan]", border_style="cyan"))

    def survey_empty_prompt(self) -> str:
        """Check if 0 papers were found and optionally ask the user for fallback IDs."""
        if not self.bus:
            return ""

        bib = self.bus.get_bibliography()
        n_papers = len(bib.papers) if bib else 0
        if n_papers > 0:
            return ""

        try:
            paper_input = Prompt.ask(
                "\n[cyan]Please provide a comma-separated list of paper IDs/titles to retry, or press Enter to proceed without papers[/cyan]"
            )
        except (KeyboardInterrupt, EOFError):
            console.print("\n[dim]Input interrupted — proceeding.[/dim]")
            return ""
            
        return paper_input.strip()

    def theory_review_prompt(self) -> tuple[bool, str, str]:
        """Show the numbered lemma chain and ask for approval.

        Returns:
            (approved, lemma_id_or_number, reason)
            If approved: (True, "", "")
            If rejected: (False, "<lemma ref>", "<issue description>")
        """
        if not self.bus:
            return True, "", ""

        state = self.bus.get_theory_state()
        if not state or not state.proven_lemmas:
            console.print("[dim]No proof state available — proceeding.[/dim]")
            return True, "", ""

        # Build numbered lemma list
        lemma_ids = list(state.proven_lemmas.keys())
        console.print()
        console.rule("[bold cyan]Proof Sketch Review[/bold cyan]")
        console.print(
            "[dim]The theory agent has finished. Review the proof structure below\n"
            "before the paper is written.[/dim]\n"
        )

        for idx, lid in enumerate(lemma_ids, start=1):
            rec = state.proven_lemmas[lid]
            node = state.lemma_dag.get(lid)
            stmt = (node.statement if node else lid)[:140]

            if rec.verified:
                conf_tag = "[green]✓[/green]"
                conf_label = "[green]verified[/green]"
            else:
                conf_tag = "[yellow]~[/yellow]"
                conf_label = "[yellow]low confidence[/yellow]"

            console.print(
                f"  [bold]L{idx}[/bold]  [{conf_tag}] "
                f"[cyan]{lid}[/cyan]  {conf_label}"
            )
            console.print(f"       [dim]{stmt}[/dim]")

        if state.open_goals:
            console.print()
            for lid in state.open_goals:
                node = state.lemma_dag.get(lid)
                console.print(
                    f"  [bold yellow]?[/bold yellow]  [cyan]{lid}[/cyan]  "
                    f"[yellow]unproved[/yellow]"
                )
                if node:
                    console.print(f"       [dim]{node.statement[:140]}[/dim]")

        console.print()
        console.rule()
        console.print(
            "\n[bold]Does this proof sketch look correct?[/bold]\n"
            "  [green]y[/green]  — Proceed to writing\n"
            "  [red]n[/red]  — Flag the most logically problematic step\n"
        )

        while True:
            try:
                answer = console.input("→ ").strip().lower()
            except (KeyboardInterrupt, EOFError):
                console.print("\n[dim]Input interrupted — proceeding.[/dim]")
                return True, "", ""

            if answer == "" or answer.startswith("y"):
                console.print("[green]Proof approved — proceeding to writer.[/green]\n")
                return True, "", ""
            elif answer.startswith("n"):
                break
            else:
                console.print("[red]Please enter 'y' or 'n'.[/red]")

        # Rejection: ask which lemma and what the issue is
        console.print()
        
        all_valid_ids = set(lemma_ids)
        if state.open_goals:
            all_valid_ids.update(state.open_goals)

        while True:
            try:
                lemma_ref = console.input(
                    "[bold]Which step has the most critical logical gap?[/bold]\n"
                    "[dim]Enter lemma number (e.g. L3) or ID:[/dim] → "
                ).strip()
            except (KeyboardInterrupt, EOFError):
                console.print("\n[dim]Input interrupted — proceeding anyway.[/dim]")
                return True, "", ""

            # Resolve "L3" → actual lemma id
            resolved_id = lemma_ref
            if lemma_ref.upper().startswith("L") and lemma_ref[1:].isdigit():
                idx = int(lemma_ref[1:]) - 1
                if 0 <= idx < len(lemma_ids):
                    resolved_id = lemma_ids[idx]
                    break
                else:
                    console.print(f"[red]Invalid lemma number. Please enter a number between L1 and L{len(lemma_ids)}.[/red]\n")
            elif resolved_id in all_valid_ids:
                break
            else:
                console.print("[red]Invalid input. Please enter a valid lemma number (e.g., L1) or exact ID.[/red]\n")

        while True:
            try:
                reason = console.input(
                    "\n[bold]Describe the issue[/bold]\n"
                    "[dim](Be specific — the theory agent will retry with your feedback):[/dim] → "
                ).strip()
            except (KeyboardInterrupt, EOFError):
                console.print("\n[dim]Input interrupted — proceeding anyway.[/dim]")
                return True, "", ""

            if not reason:
                console.print("[red]Please provide a description of the issue, or press Ctrl+C to abort.[/red]")
                continue
            break

        console.print(
            f"\n[yellow]Flagged:[/yellow] [cyan]{resolved_id}[/cyan]\n"
            f"[yellow]Issue:[/yellow] {reason}\n"
        )
        return False, resolved_id, reason

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _count_low_confidence_lemmas(self) -> int:
        if not self.bus:
            return 0
        state = self.bus.get_theory_state()
        if not state:
            return 0
        return sum(1 for rec in state.proven_lemmas.values() if not rec.verified)
