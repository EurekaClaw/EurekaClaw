"""PaperQAHandler — interactive paper review gate with QA and rewrite loops."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from rich.panel import Panel
from rich.prompt import Confirm

from eurekaclaw.agents.paper_qa.agent import PaperQAAgent
from eurekaclaw.config import settings
from eurekaclaw.console import console
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient
from eurekaclaw.memory.manager import MemoryManager
from eurekaclaw.orchestrator.gate import GateController
from eurekaclaw.orchestrator.router import TaskRouter
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.tools.registry import ToolRegistry
from eurekaclaw.types.agents import AgentRole
from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus
from eurekaclaw.ui.constants import REWRITE_MARKER_PREFIX

logger = logging.getLogger(__name__)


class PaperQAHandler:
    """Encapsulates the full Paper QA Gate flow for CLI (and later UI).

    Manages two nested loops:
    - Outer loop: review paper -> optionally rewrite -> review again
    - Inner loop: ask questions -> QA agent answers -> decide next action
    """

    def __init__(
        self,
        bus: KnowledgeBus,
        agents: dict[AgentRole, BaseAgent],
        router: TaskRouter,
        client: LLMClient,
        tool_registry: ToolRegistry,
        skill_injector: SkillInjector,
        memory: MemoryManager,
        gate_controller: GateController,
    ) -> None:
        self.bus = bus
        self.agents = agents
        self.router = router
        self.client = client
        self.tool_registry = tool_registry
        self.skill_injector = skill_injector
        self.memory = memory
        self.gate = gate_controller

        self._qa_agent: PaperQAAgent | None = None
        self._history: list[dict[str, Any]] = []
        self._paper_version: int = 0
        self._session_dir: Path = settings.runs_dir / bus.session_id

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def run(self, pipeline: TaskPipeline, brief: ResearchBrief) -> None:
        """Main entry point — called from MetaOrchestrator."""
        latex = self._get_latex_from_pipeline(pipeline)
        if not latex:
            console.print("[dim]No paper LaTeX found — skipping review.[/dim]")
            return

        self._save_paper_version(latex)
        self.bus.put("paper_qa_latex", latex)

        # In UI mode, delegate to the review_gate event system so the
        # frontend overlay can drive the interaction instead of CLI prompts.
        import os
        if os.environ.get("EUREKACLAW_UI_MODE"):
            await self._run_ui_mode(pipeline, brief, latex)
            return

        if not self._should_review():
            return

        await self._review_loop(pipeline, brief, latex)

    async def run_historical(
        self, pipeline: TaskPipeline, brief: ResearchBrief
    ) -> None:
        """Enter review loop for a historical session (skip the y/N prompt).

        Used by CLI `eurekaclaw review` and UI "Review Paper" button.
        """
        latex = self._get_latex_from_pipeline(pipeline)
        if not latex:
            latex = self.bus.get("paper_qa_latex") or ""
        if not latex:
            console.print("[red]No paper LaTeX found in this session.[/red]")
            return

        self._save_paper_version(latex)
        self.bus.put("paper_qa_latex", latex)

        # Load existing QA history from disk if available
        history_file = self._session_dir / "paper_qa_history.jsonl"
        if history_file.exists():
            import json as _json
            for line in history_file.read_text(encoding="utf-8").strip().split("\n"):
                if line.strip():
                    try:
                        self._history.append(_json.loads(line))
                    except _json.JSONDecodeError:
                        pass

        await self._review_loop(pipeline, brief, latex)

    async def _run_ui_mode(
        self, pipeline: TaskPipeline, brief: ResearchBrief, latex: str
    ) -> None:
        """UI mode: use review_gate event system instead of CLI prompts.

        Loops until the user chooses "no" (accept). After each rebuttal or
        rewrite the gate is re-armed so the frontend can submit again.
        """
        from eurekaclaw.ui import review_gate

        session_id = self.bus.session_id
        qa_gate_task = next(
            (t for t in pipeline.tasks if t.name == "paper_qa_gate"), None
        )

        while True:
            # Mark gate as awaiting so frontend shows the overlay
            if qa_gate_task is not None:
                qa_gate_task.status = TaskStatus.AWAITING_GATE
                self.bus.put_pipeline(pipeline)

            decision = review_gate.wait_paper_qa(session_id)

            if qa_gate_task is not None:
                qa_gate_task.status = TaskStatus.COMPLETED
                self.bus.put_pipeline(pipeline)

            if decision.action == "no" or not decision.question.strip():
                return

            self.bus.put("paper_qa_question", decision.question)

            if decision.action == "rebuttal":
                agent = self._get_or_create_qa_agent()
                result = await agent.ask(
                    question=decision.question, latex=latex,
                    history=self._clean_history_for_agent(),
                )
                if result.failed:
                    logger.warning("PaperQAAgent failed: %s", result.error)
                else:
                    console.print("[green]Rebuttal answer generated[/green]")
                    # Store answer for frontend to display
                    self._history.append({
                        "role": "user",
                        "content": decision.question,
                        "ts": datetime.now(timezone.utc).isoformat(),
                        "version": self._paper_version,
                    })
                    self._history.append({
                        "role": "assistant",
                        "content": result.output.get("answer", ""),
                        "ts": datetime.now(timezone.utc).isoformat(),
                        "version": self._paper_version,
                    })
                    self._persist_history()

            elif decision.action == "rewrite":
                new_latex = await self._do_rewrite(
                    pipeline, brief, revision_prompt=decision.question
                )
                if new_latex is not None:
                    # Persist a rewrite marker matching the frontend's
                    # "↻" convention. Written AFTER success so a failed
                    # rewrite doesn't leave a marker in history for work
                    # that was never done.
                    marker = {
                        "role": "system",
                        "content": f'{REWRITE_MARKER_PREFIX}"{decision.question}"',
                        "ts": datetime.now(timezone.utc).isoformat(),
                        "version": self._paper_version,
                    }
                    self._history.append(marker)
                    self._session_dir.mkdir(parents=True, exist_ok=True)
                    marker_path = self._session_dir / "paper_qa_history.jsonl"
                    with marker_path.open("a", encoding="utf-8") as f:
                        f.write(json.dumps(marker, ensure_ascii=False) + "\n")
                    self._save_paper_version(new_latex)
                    # Bump writer.outputs.paper_version so the polling
                    # frontend sees the new version without having to
                    # derive it from chat markers.
                    writer_task = next(
                        (t for t in pipeline.tasks if t.name == "writer"), None
                    )
                    if writer_task is not None:
                        outputs = writer_task.outputs or {}
                        outputs["paper_version"] = int(outputs.get("paper_version", 1)) + 1
                        writer_task.outputs = outputs
                        self.bus.put_pipeline(pipeline)
                    latex = new_latex
                    self.bus.put("paper_qa_latex", latex)
                else:
                    # Rewrite failed — notify frontend, keep current paper
                    console.print(
                        "[yellow]Rewrite failed — keeping current "
                        f"paper (v{self._paper_version})[/yellow]"
                    )

            # Re-arm the gate for the next round
            review_gate.reset_paper_qa(session_id)

    # ------------------------------------------------------------------
    # Review loops
    # ------------------------------------------------------------------

    async def _review_loop(
        self, pipeline: TaskPipeline, brief: ResearchBrief, latex: str
    ) -> None:
        """Outer loop: review -> QA -> rewrite -> review ..."""
        while True:
            self._display_latex_preview(latex)
            action = await self._qa_loop(latex)

            if action == "accept":
                console.print(
                    f"[green]Paper accepted (v{self._paper_version})[/green]"
                )
                break

            if action == "rewrite":
                new_latex = await self._do_rewrite(pipeline, brief)
                if new_latex is None:
                    rolled_back = self._rollback_paper()
                    if rolled_back:
                        latex = rolled_back
                        console.print(
                            "[yellow]Rewrite failed — rolled back to "
                            f"v{self._paper_version}[/yellow]"
                        )
                    else:
                        # No previous version to rollback to — keep current
                        console.print(
                            "[yellow]Rewrite failed — keeping current "
                            f"paper (v{self._paper_version})[/yellow]"
                        )
                else:
                    latex = new_latex
                    self._save_paper_version(latex)
                    self.bus.put("paper_qa_latex", latex)

    async def _qa_loop(self, latex: str) -> str:
        """Inner loop: question -> QA agent -> user decides.

        Returns:
            "accept" or "rewrite"
        """
        while True:
            question = self._prompt_question()
            if not question:
                return "accept"

            console.print("\n[blue]QA Agent thinking...[/blue]")
            answer = await self._ask_qa_agent(latex, question)

            self._history.append({
                "role": "user",
                "content": question,
                "ts": datetime.now(timezone.utc).isoformat(),
                "version": self._paper_version,
            })
            self._history.append({
                "role": "assistant",
                "content": answer,
                "ts": datetime.now(timezone.utc).isoformat(),
                "version": self._paper_version,
            })
            self._persist_history()

            choice = self._prompt_after_answer()
            if choice == "a":
                return "accept"
            if choice == "r":
                return "rewrite"
            # choice == "q": continue inner loop

    # ------------------------------------------------------------------
    # QA Agent interaction
    # ------------------------------------------------------------------

    def _get_or_create_qa_agent(self) -> PaperQAAgent:
        if self._qa_agent is None:
            self._qa_agent = PaperQAAgent(
                bus=self.bus,
                tool_registry=self.tool_registry,
                skill_injector=self.skill_injector,
                memory=self.memory,
                client=self.client,
            )
        return self._qa_agent

    async def _ask_qa_agent(self, latex: str, question: str) -> str:
        agent = self._get_or_create_qa_agent()
        result = await agent.ask(
            question=question, latex=latex,
            history=self._clean_history_for_agent(),
        )
        if result.failed:
            console.print(f"[red]QA Agent error: {result.error}[/red]")
            return f"Error: {result.error}"
        return result.output.get("answer", "")

    # ------------------------------------------------------------------
    # Rewrite
    # ------------------------------------------------------------------

    async def _do_rewrite(
        self,
        pipeline: TaskPipeline,
        brief: ResearchBrief,
        revision_prompt: str | None = None,
        writer_only: bool = False,
    ) -> str | None:
        """Re-run agents with feedback. Returns new LaTeX or None.

        Args:
            revision_prompt: If provided (UI mode), skip the CLI prompt.
            writer_only: If True, skip theory and only re-run the writer.
                Used for historical session rewrites where the user wants
                the paper polished without re-proving the theory.
        """
        if revision_prompt is None:
            revision_prompt = self._prompt_revision()
        if not revision_prompt:
            console.print("[dim]No revision instructions — skipping rewrite.[/dim]")
            return None

        # Save rewrite context
        self._save_rewrite_context(revision_prompt)

        # Build feedback from QA history + revision prompt
        qa_summary = self._summarize_qa_history()
        feedback = (
            f"\n\n[User revision request after paper review]:\n"
            f"QA discussion summary:\n{qa_summary}\n\n"
            f"Revision instructions:\n{revision_prompt}"
        )

        # Determine which tasks to re-run
        if writer_only:
            rewrite_tasks = ["writer"]
        else:
            rewrite_tasks = ["theory", "experiment", "writer"]

        # Snapshot previous task outputs so we can restore on failure
        theory_task = next(
            (t for t in pipeline.tasks if t.name == "theory"), None
        )
        experiment_task = next(
            (t for t in pipeline.tasks if t.name == "experiment"), None
        )
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )
        prev_theory_outputs = dict(theory_task.outputs) if theory_task else {}
        prev_experiment_outputs = (
            dict(experiment_task.outputs) if experiment_task else {}
        )
        prev_writer_outputs = dict(writer_task.outputs) if writer_task else {}
        prev_theory_desc = theory_task.description if theory_task else ""

        # Put revision feedback on the bus so agents can read it.
        # WriterAgent checks bus.get("revision_feedback") and appends it
        # to the user prompt. TheoryAgent reads from task.description.
        self.bus.put("revision_feedback", feedback)

        # Reset tasks for re-execution
        if not writer_only and theory_task is not None:
            theory_task.description = (theory_task.description or "") + feedback
            theory_task.retries = 0
            theory_task.status = TaskStatus.PENDING
        if not writer_only and experiment_task is not None:
            experiment_task.retries = 0
            experiment_task.status = TaskStatus.PENDING
        if writer_task is not None:
            writer_task.retries = 0
            writer_task.status = TaskStatus.PENDING

        self.bus.put_pipeline(pipeline)
        label = "writer" if writer_only else "theory + experiment + writer"
        console.print(f"[blue]Re-running {label} with feedback...[/blue]")

        rewrite_failed = False
        try:
            for task in pipeline.tasks:
                if task.name not in rewrite_tasks:
                    continue
                if task.status != TaskStatus.PENDING:
                    continue

                task.mark_started()
                console.print(f"[blue]> Running: {task.name}[/blue]")
                agent = self.router.resolve(task)
                result = await agent.execute(task)

                if result.failed:
                    task.mark_failed(result.error)
                    console.print(
                        f"[red]Failed: {task.name}: {result.error[:100]}[/red]"
                    )
                    # Partial failure: if theory failed, writer can still
                    # generate a paper with [TODO] markers
                    if task.name == "theory":
                        console.print(
                            "[yellow]Theory failed — writer will generate "
                            "paper with [TODO] markers[/yellow]"
                        )
                        continue
                    rewrite_failed = True
                    break

                task_outputs = dict(result.output)
                if result.text_summary:
                    task_outputs["text_summary"] = result.text_summary
                task.mark_completed(task_outputs)
                console.print(f"[green]Done: {task.name}[/green]")

        except Exception as e:
            logger.exception("Rewrite failed: %s", e)
            console.print(f"[red]Rewrite error: {e}[/red]")
            rewrite_failed = True

        if rewrite_failed:
            # Restore tasks to COMPLETED with their previous outputs so
            # the pipeline stays in a consistent state for the next round.
            if theory_task is not None:
                theory_task.status = TaskStatus.COMPLETED
                theory_task.outputs = prev_theory_outputs
                theory_task.error_message = ""
                theory_task.description = prev_theory_desc
            if experiment_task is not None:
                experiment_task.status = TaskStatus.COMPLETED
                experiment_task.outputs = prev_experiment_outputs
                experiment_task.error_message = ""
            if writer_task is not None:
                writer_task.status = TaskStatus.COMPLETED
                writer_task.outputs = prev_writer_outputs
                writer_task.error_message = ""
            self.bus.put_pipeline(pipeline)
            return None

        self.bus.put_pipeline(pipeline)
        return self._get_latex_from_pipeline(pipeline)

    # ------------------------------------------------------------------
    # CLI prompts
    # ------------------------------------------------------------------

    def _should_review(self) -> bool:
        """CLI: prompt user; UI: would use review_gate (handled in future)."""
        try:
            return Confirm.ask(
                "\n[bold]Review the paper?[/bold]", default=False
            )
        except (KeyboardInterrupt, EOFError):
            return False

    def _prompt_question(self) -> str:
        try:
            q = console.input(
                "\n[bold]Question[/bold] [dim](Enter to accept):[/dim] "
            ).strip()
            return q
        except (KeyboardInterrupt, EOFError):
            return ""

    def _prompt_after_answer(self) -> str:
        """Returns 'a' (accept), 'q' (question), or 'r' (rewrite)."""
        console.print(
            "\n[bold]What next?[/bold]  "
            "[green][a]ccept[/green]  "
            "[cyan][q]uestion[/cyan]  "
            "[yellow][r]ewrite[/yellow]"
        )
        while True:
            try:
                choice = console.input("-> ").strip().lower()
            except (KeyboardInterrupt, EOFError):
                return "a"
            if choice in ("a", "accept"):
                return "a"
            if choice in ("q", "question"):
                return "q"
            if choice in ("r", "rewrite"):
                return "r"
            console.print("[red]Please enter 'a', 'q', or 'r'.[/red]")

    def _prompt_revision(self) -> str:
        try:
            return console.input(
                "\n[bold]Describe what to fix:[/bold]\n-> "
            ).strip()
        except (KeyboardInterrupt, EOFError):
            return ""

    # ------------------------------------------------------------------
    # Display
    # ------------------------------------------------------------------

    def _display_latex_preview(self, latex: str) -> None:
        lines = latex.split("\n")
        total = len(lines)
        head = 80
        tail = 20

        if total <= head + tail:
            preview = latex
        else:
            top = "\n".join(lines[:head])
            bottom = "\n".join(lines[-tail:])
            omitted = total - head - tail
            preview = f"{top}\n\n... ({omitted} lines omitted) ...\n\n{bottom}"

        console.print(Panel(
            preview,
            title=f"[cyan]Paper Preview (v{self._paper_version})[/cyan]",
            border_style="cyan",
            subtitle=f"{total} lines total",
        ))

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def _get_latex_from_pipeline(self, pipeline: TaskPipeline) -> str:
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )
        if writer_task and writer_task.outputs:
            return writer_task.outputs.get("latex_paper", "")
        return ""

    def _save_paper_version(self, latex: str) -> None:
        self._paper_version += 1
        self._session_dir.mkdir(parents=True, exist_ok=True)
        path = self._session_dir / f"paper_v{self._paper_version}.tex"
        path.write_text(latex, encoding="utf-8")
        logger.info("Saved %s", path)

    def _rollback_paper(self) -> str:
        """Load the previous paper version. Decrements version counter."""
        if self._paper_version <= 1:
            return ""
        prev = self._paper_version - 1
        path = self._session_dir / f"paper_v{prev}.tex"
        if path.exists():
            self._paper_version = prev
            return path.read_text(encoding="utf-8")
        return ""

    def _persist_history(self) -> None:
        """Append the last two entries (Q+A pair) to JSONL."""
        self._session_dir.mkdir(parents=True, exist_ok=True)
        path = self._session_dir / "paper_qa_history.jsonl"
        with path.open("a", encoding="utf-8") as f:
            for entry in self._history[-2:]:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _save_rewrite_context(self, revision_prompt: str) -> None:
        self._session_dir.mkdir(parents=True, exist_ok=True)
        ctx = {
            "qa_summary": self._summarize_qa_history(),
            "revision_prompt": revision_prompt,
            "rewrite_round": self._paper_version,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        path = self._session_dir / f"rewrite_context_v{self._paper_version}.json"
        path.write_text(json.dumps(ctx, indent=2, ensure_ascii=False), encoding="utf-8")

    def _clean_history_for_agent(self) -> list[dict[str, str]]:
        """Return history as role/content pairs the LLM API accepts.

        Strips metadata (ts, version) and folds rewrite markers
        (role="system") into user turns. Anthropic's messages API
        rejects role="system" in the message list, but the marker
        text (REWRITE_MARKER_PREFIX + "…") is real context the QA agent
        needs when the user asks follow-ups like "did you address
        the issue from my earlier rewrite request?". This mirrors
        what the frontend QAChat does when posting to /paper-qa/ask.
        """
        out: list[dict[str, str]] = []
        for h in self._history:
            role = h["role"]
            if role == "user" or role == "assistant":
                out.append({"role": role, "content": h["content"]})
            elif role == "system":
                out.append({"role": "user", "content": h["content"]})
        return out

    def _summarize_qa_history(self) -> str:
        """Build a concise text summary of the QA conversation for feedback injection."""
        if not self._history:
            return "(no prior discussion)"
        parts: list[str] = []
        for h in self._history:
            # Skip system markers (role="system", e.g. REWRITE_MARKER_PREFIX entries) —
            # those are UI history artifacts, not QA conversation turns.
            if h["role"] not in ("user", "assistant"):
                continue
            role = "User" if h["role"] == "user" else "QA Agent"
            content = h["content"][:300]
            parts.append(f"{role}: {content}")
        return "\n".join(parts) if parts else "(no prior discussion)"
