"""MetaOrchestrator — the central brain driving the full research pipeline."""

from __future__ import annotations

import logging
from pathlib import Path

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Prompt

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.agents.experiment.agent import ExperimentAgent
from eurekaclaw.agents.ideation.agent import IdeationAgent
from eurekaclaw.agents.survey.agent import SurveyAgent
from eurekaclaw.agents.theory.agent import TheoryAgent
from eurekaclaw.agents.writer.agent import WriterAgent
from eurekaclaw.config import settings
from eurekaclaw.domains.base import DomainPlugin
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.learning.loop import ContinualLearningLoop
from eurekaclaw.memory.manager import MemoryManager
from eurekaclaw.orchestrator.gate import GateController, get_user_feedback
from eurekaclaw.orchestrator.pipeline import PipelineManager
from eurekaclaw.orchestrator.planner import DivergentConvergentPlanner
from eurekaclaw.orchestrator.router import TaskRouter
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.tools.registry import ToolRegistry, build_default_registry
from eurekaclaw.types.agents import AgentRole
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import InputSpec, ResearchOutput, Task, TaskPipeline, TaskStatus

from eurekaclaw.console import console

logger = logging.getLogger(__name__)


class MetaOrchestrator:
    """Central brain. Drives the full pipeline from input spec to research output."""

    def __init__(
        self,
        bus: KnowledgeBus,
        tool_registry: ToolRegistry | None = None,
        skill_registry: SkillRegistry | None = None,
        client: LLMClient | None = None,
        domain_plugin: DomainPlugin | None = None,
        selected_skills: list[str] | None = None,
    ) -> None:
        self.bus = bus
        self.client: LLMClient = client or create_client()
        self.tool_registry = tool_registry or build_default_registry()
        self.skill_registry = skill_registry or SkillRegistry()
        self.domain_plugin = domain_plugin

        # Apply domain plugin: register extra tools and skills
        if domain_plugin:
            domain_plugin.register_tools(self.tool_registry)
            for skills_dir in domain_plugin.get_skills_dirs():
                self.skill_registry.add_skills_dir(skills_dir)
            logger.info("Domain plugin loaded: %s", domain_plugin.display_name)

        self.skill_injector = SkillInjector(self.skill_registry, selected_skills=selected_skills)
        self.memory = MemoryManager(session_id=bus.session_id)

        # Build agent team
        agent_kwargs = dict(
            bus=self.bus,
            tool_registry=self.tool_registry,
            skill_injector=self.skill_injector,
            memory=self.memory,
            client=self.client,
        )
        self.agents: dict[AgentRole, BaseAgent] = {
            AgentRole.SURVEY: SurveyAgent(**agent_kwargs),
            AgentRole.IDEATION: IdeationAgent(**agent_kwargs),
            AgentRole.THEORY: TheoryAgent(**agent_kwargs),
            AgentRole.EXPERIMENT: ExperimentAgent(**agent_kwargs),
            AgentRole.WRITER: WriterAgent(**agent_kwargs),
        }

        self.planner = DivergentConvergentPlanner(client=self.client)
        self.gate = GateController(bus=self.bus)
        self.pipeline_manager = PipelineManager()
        self.router = TaskRouter(self.agents)
        self.learning_loop = ContinualLearningLoop(
            mode=settings.eurekaclaw_mode,
            skill_registry=self.skill_registry,
            client=self.client,
        )

    async def run(self, input_spec: InputSpec) -> ResearchOutput:
        """Run the full research pipeline from input to output artifacts."""
        from eurekaclaw.llm.base import reset_global_tokens
        reset_global_tokens()
        settings.ensure_dirs()

        # --- Phase 1: Initialize the research brief ---
        brief = self._init_brief(input_spec)
        self.bus.put_research_brief(brief)
        console.print(f"\n[bold green]EurekaClaw[/bold green] session: {brief.session_id}")
        plugin_name = self.domain_plugin.display_name if self.domain_plugin else "general"
        console.print(f"Domain: {brief.domain} ({plugin_name}) | Mode: {input_spec.mode} | Learning: {settings.eurekaclaw_mode}\n")
        if self.domain_plugin:
            # Store workflow hint on bus so agents can read it
            self.bus.put("domain_workflow_hint", self.domain_plugin.get_workflow_hint())

        # --- Phase 2: Divergent-Convergent planning (before survey, so we have a direction) ---
        # We'll do the survey first to get open problems, then plan
        pipeline = self.pipeline_manager.build(brief)
        self.bus.put_pipeline(pipeline)

        # --- Phase 3: Execute tasks ---
        for task in pipeline.tasks:
            if task.status == TaskStatus.SKIPPED:
                continue

            # Check dependencies
            if not self._dependencies_met(task, pipeline):
                logger.warning("Skipping %s — dependencies not met", task.name)
                task.status = TaskStatus.SKIPPED
                continue

            # Direction selection always runs for orchestrator tasks, regardless
            # of whether a human gate is configured.
            if task.name == "direction_selection_gate":
                await self._handle_direction_gate(brief)

            # Theory review gate: show proof sketch, ask for approval.
            # If rejected, inject feedback and re-run theory (once).
            if task.name == "theory_review_gate":
                await self._handle_theory_review_gate(pipeline, brief)

            # Ensure a research direction exists before theory runs.
            # direction_selection_gate may have been skipped (e.g. survey failed),
            # so we check here as a safety net and prompt the user if needed.
            if task.name == "theory":
                brief = self.bus.get_research_brief() or brief
                if not brief.directions:
                    await self._handle_manual_direction(brief)

            # Gate check (human / auto approval)
            if task.gate_required:
                task.status = TaskStatus.AWAITING_GATE
                approved = await self.gate.request_approval(task)
                if not approved:
                    task.status = TaskStatus.SKIPPED
                    console.print(f"[yellow]Skipped: {task.name}[/yellow]")
                    continue

            # Execute orchestrator tasks (no agent needed)
            if task.agent_role == "orchestrator":
                task.mark_completed()
                continue

            # Inject user feedback from the preceding gate into this task
            _gate_name = f"{task.name}_gate" if not task.name.endswith("_gate") else task.name
            _prev_gates = {
                "theory": "direction_selection_gate",
                "experiment": "theory_review_gate",
                "writer": "final_review_gate",
            }
            _feedback = get_user_feedback(_prev_gates.get(task.name, _gate_name))
            if _feedback:
                task.description = (task.description or "") + f"\n\n[User guidance]: {_feedback}"
                console.print(f"[dim]  ↳ User feedback injected: {_feedback[:80]}[/dim]")

            task.mark_started()
            console.print(f"[blue]▶ Running: {task.name}[/blue]")

            agent = self.router.resolve(task)

            with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"), console=console) as progress:
                prog_task = progress.add_task(f"{task.name}...", total=None)
                result = await agent.execute(task)
                progress.update(prog_task, completed=True)

            if result.failed:
                task.mark_failed(result.error)
                console.print(f"[red]✗ Failed: {task.name}: {result.error[:100]}[/red]")
                self.learning_loop.failure_capture.record_task_failure(task, result.error)
                if task.retries < task.max_retries:
                    task.retries += 1
                    task.status = TaskStatus.PENDING
                    console.print(f"[yellow]  Retrying ({task.retries}/{task.max_retries})...[/yellow]")
                    result = await agent.execute(task)
                    if result.failed:
                        task.mark_failed(result.error)
            else:
                task_outputs = dict(result.output)
                if result.text_summary:
                    task_outputs["text_summary"] = result.text_summary
                if result.token_usage:
                    task_outputs["token_usage"] = result.token_usage
                task.mark_completed(task_outputs)
                console.print(f"[green]✓ Done: {task.name}[/green]")
                if result.text_summary:
                    console.print(f"  {result.text_summary}")

                # Always-on summary card — visible regardless of gate_mode
                self.gate.print_stage_summary(task.name)

                if task.name == "survey":
                    await self._handle_empty_survey_fallback(pipeline)

            self.bus.put_pipeline(pipeline)

        # --- Phase 4: Post-run continual learning ---
        console.print("\n[blue]Running continual learning loop...[/blue]")
        await self.learning_loop.post_run(pipeline, self.bus)

        # --- Phase 5: Collect outputs ---
        output = self._collect_outputs(brief)
        session_dir = settings.runs_dir / brief.session_id
        self.bus.persist(session_dir)
        console.print(f"\n[bold green]Session complete![/bold green] Artifacts saved to {session_dir}")

        return output

    def _init_brief(self, spec: InputSpec) -> ResearchBrief:
        from eurekaclaw.types.artifacts import ResearchBrief
        return ResearchBrief(
            session_id=self.bus.session_id,  # reuse the outer session ID so pause/resume flags align
            input_mode=spec.mode,
            domain=spec.domain,  # always set by EurekaSession.run() before reaching here
            query=spec.query or spec.conjecture or spec.domain,
            conjecture=spec.conjecture,
            selected_skills=spec.selected_skills,
            reference_paper_ids=spec.paper_ids,
        )

    async def _handle_direction_gate(self, brief: ResearchBrief) -> None:
        """Run Divergent-Convergent planner before the direction gate.

        Re-reads the brief from the bus so that survey-updated open_problems
        and key_mathematical_objects are visible to the planner.

        For "detailed" mode (the `prove` command) with a specific conjecture,
        we skip the creative planner and directly use the conjecture as the
        sole research direction, preserving the user's exact statement.
        """
        import uuid
        from eurekaclaw.types.artifacts import ResearchDirection

        # Always fetch the latest brief — SurveyAgent may have enriched it
        brief = self.bus.get_research_brief() or brief
        if brief.directions:
            return

        # --- Detailed mode: user gave a specific conjecture to prove ---
        # Ideation ran but returned 0 directions — require user to confirm or
        # provide a direction even though a conjecture was supplied.  We do NOT
        # silently auto-create from the conjecture; instead _handle_manual_direction
        # will show the conjecture as a default and require explicit confirmation.
        if brief.input_mode == "detailed":
            await self._handle_manual_direction(brief)
            return

        # --- Exploration / reference mode: run full divergent-convergent ---
        console.print("[blue]Generating 5 research directions...[/blue]")
        directions = []
        try:
            directions = await self.planner.diverge(brief)
            if directions:
                console.print("\n[bold]Generated research directions:[/bold]")
                for i, d in enumerate(directions, 1):
                    console.print(f"  [cyan]{i}.[/cyan] {d.title}")
                    console.print(f"     {d.hypothesis[:160]}")
                best = await self.planner.converge(directions, brief)
                brief.directions = directions
                brief.selected_direction = best
                self.bus.put_research_brief(brief)
                console.print(f"\n[green]▶ Best direction selected: {best.title}[/green]")
                console.print(f"  Composite score: {best.composite_score:.2f}")
                console.print(f"  Hypothesis: {best.hypothesis[:200]}")
        except Exception as e:
            logger.exception("Direction planning failed: %s", e)

        if not directions:
            await self._handle_manual_direction(brief)

    async def _handle_manual_direction(self, brief: "ResearchBrief") -> None:
        """Fallback: ideation produced no directions — ask the user to supply one.

        If ``brief.conjecture`` is set (prove mode), it is shown as the default;
        pressing Enter without typing anything accepts it.
        """
        import os
        import uuid
        from eurekaclaw.types.artifacts import ResearchDirection

        if os.environ.get("EUREKACLAW_UI_MODE"):
            # UI mode: block until the frontend submits a direction
            from eurekaclaw.ui import review_gate
            from eurekaclaw.types.tasks import TaskStatus

            session_id = self.bus.session_id
            pipeline = self.bus.get_pipeline()
            gate_task = next(
                (t for t in pipeline.tasks if t.name == "direction_selection_gate"),
                None,
            ) if pipeline else None

            if gate_task is not None:
                gate_task.status = TaskStatus.AWAITING_GATE
                self.bus.put_pipeline(pipeline)

            decision = review_gate.wait_direction(session_id)
            hypothesis = (decision.direction or "").strip() if decision else ""
            if not hypothesis:
                hypothesis = brief.conjecture or ""

            if gate_task is not None:
                gate_task.status = TaskStatus.COMPLETED
                self.bus.put_pipeline(pipeline)

            if not hypothesis:
                logger.warning("Direction gate: no direction provided and no conjecture fallback — skipping")
                return

            direction = ResearchDirection(
                direction_id=str(uuid.uuid4()),
                title=hypothesis[:80],
                hypothesis=hypothesis,
                approach_sketch="User-provided direction — formalize, decompose into lemmas, attempt proof.",
                novelty_score=0.8,
                soundness_score=0.8,
                transformative_score=0.7,
            )
            direction.compute_composite()
            brief.directions = [direction]
            brief.selected_direction = direction
            self.bus.put_research_brief(brief)
            return

        console.print(
            "\n[yellow]⚠  Ideation returned 0 research directions — human input required.[/yellow]"
        )
        if brief.open_problems:
            console.print("\n[bold]Open problems found by survey:[/bold]")
            for p in brief.open_problems[:5]:
                console.print(f"  • {str(p)[:120]}")

        if brief.conjecture:
            console.print(
                f"\n[bold]Your conjecture:[/bold] {brief.conjecture[:200]}\n"
                "[dim]Press Enter to use it as the research direction, or type a different one.[/dim]\n"
            )
        else:
            console.print(
                "\n[bold]Please enter a research direction / hypothesis to pursue.[/bold]\n"
                "[dim](e.g. \"UCB1 achieves O(√(KT log T)) regret in the stochastic MAB setting\")[/dim]\n"
            )

        hypothesis = ""
        while not hypothesis:
            try:
                raw = console.input("→ ")
            except (KeyboardInterrupt, EOFError):
                console.print("\n[red]Cancelled — cannot continue without a research direction.[/red]")
                raise RuntimeError("No research direction available and user did not provide one.")

            hypothesis = raw.strip()
            if not hypothesis:
                if brief.conjecture and raw == "":
                    # Pure Enter accepts the conjecture default
                    hypothesis = brief.conjecture
                else:
                    console.print("[yellow]Please enter a direction to continue (or Ctrl+C to abort).[/yellow]")

        direction = ResearchDirection(
            direction_id=str(uuid.uuid4()),
            title=hypothesis[:80],
            hypothesis=hypothesis,
            approach_sketch="User-provided direction — formalize, decompose into lemmas, attempt proof.",
            novelty_score=0.8,
            soundness_score=0.8,
            transformative_score=0.7,
        )
        direction.compute_composite()
        brief.directions = [direction]
        brief.selected_direction = direction
        self.bus.put_research_brief(brief)
        console.print(f"[green]Direction set to: {direction.title}[/green]\n")

    async def _handle_theory_review_gate(
        self, pipeline: "TaskPipeline", brief: "ResearchBrief"
    ) -> None:
        """Show the proof sketch to the user and re-run theory until approved.

        The user can reject up to ``settings.theory_review_max_retries`` times.
        Each rejection injects feedback and re-runs the full theory stage.
        After the retry limit is reached the pipeline proceeds to writer
        without further prompting.
        """
        import os
        from eurekaclaw.types.tasks import TaskStatus

        max_retries = settings.theory_review_max_retries
        attempt = 0

        if os.environ.get("EUREKACLAW_UI_MODE"):
            # UI mode: use event-based gate
            from eurekaclaw.ui import review_gate

            session_id = self.bus.session_id

            while True:
                gate_task = next(
                    (t for t in pipeline.tasks if t.name == "theory_review_gate"),
                    None,
                )
                if gate_task is not None:
                    gate_task.status = TaskStatus.AWAITING_GATE
                    self.bus.put_pipeline(pipeline)

                decision = review_gate.wait_theory(session_id)

                if gate_task is not None:
                    gate_task.status = TaskStatus.COMPLETED
                    self.bus.put_pipeline(pipeline)

                if decision is None or decision.approved:
                    return

                attempt += 1
                if attempt > max_retries:
                    logger.info("Theory review: retry limit reached — proceeding to writer")
                    return

                theory_task = next((t for t in pipeline.tasks if t.name == "theory"), None)
                if theory_task is None:
                    logger.warning("theory_review_gate: no 'theory' task found — proceeding")
                    return

                feedback = (
                    f"The user flagged lemma '{decision.lemma_id}' as having a critical logical gap.\n"
                    f"Issue: {decision.reason}\n"
                    f"Please re-examine this lemma and fix the logical chain before assembling the proof."
                )
                theory_task.description = (theory_task.description or "") + f"\n\n[User feedback]: {feedback}"
                theory_task.retries = 0
                theory_task.status = TaskStatus.PENDING

                agent = self.router.resolve(theory_task)
                result = await agent.execute(theory_task)

                if result.failed:
                    theory_task.mark_failed(result.error)
                else:
                    theory_task.mark_completed(dict(result.output))

                self.bus.put_pipeline(pipeline)
                review_gate.reset_theory(session_id)
            return

        while True:
            approved, lemma_ref, reason = self.gate.theory_review_prompt()
            if approved:
                return

            attempt += 1
            if attempt > max_retries:
                console.print(
                    f"[yellow]Retry limit ({max_retries}) reached — proceeding to writer.[/yellow]\n"
                )
                return

            console.print(
                f"[yellow]Re-running theory agent with your feedback "
                f"(attempt {attempt}/{max_retries})...[/yellow]\n"
            )

            theory_task = next((t for t in pipeline.tasks if t.name == "theory"), None)
            if theory_task is None:
                logger.warning("theory_review_gate: no 'theory' task found — proceeding")
                return

            feedback = (
                f"The user flagged lemma '{lemma_ref}' as having a critical logical gap.\n"
                f"Issue: {reason}\n"
                f"Please re-examine this lemma and fix the logical chain before assembling the proof."
            )
            theory_task.description = (theory_task.description or "") + f"\n\n[User feedback]: {feedback}"
            theory_task.retries = 0
            theory_task.status = TaskStatus.PENDING

            agent = self.router.resolve(theory_task)

            from rich.progress import Progress, SpinnerColumn, TextColumn
            with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"), console=console) as progress:
                prog_task = progress.add_task("theory (revision)...", total=None)
                result = await agent.execute(theory_task)
                progress.update(prog_task, completed=True)

            if result.failed:
                theory_task.mark_failed(result.error)
                console.print(f"[red]Theory revision failed: {result.error[:100]}[/red]")
            else:
                theory_task.mark_completed(dict(result.output))
                console.print("[green]✓ Theory revision complete.[/green]")
                self.gate.print_stage_summary("theory")

            self.bus.put_pipeline(pipeline)

    async def _handle_empty_survey_fallback(self, pipeline: TaskPipeline) -> None:
        """If the survey found 0 papers, pause and ask the user for paper IDs."""
        import os

        bib = self.bus.get_bibliography()
        has_papers = False
        if bib:
            # Safely check whether there are any gathered papers
            bib_dict = bib.model_dump()
            papers = bib_dict.get("papers") or bib_dict.get("entries") or []
            has_papers = len(papers) > 0

        if has_papers:
            return

        if os.environ.get("EUREKACLAW_UI_MODE"):
            # UI mode: block until the frontend submits paper IDs (or skips)
            from eurekaclaw.ui import review_gate

            session_id = self.bus.session_id
            survey_task = next((t for t in pipeline.tasks if t.name == "survey"), None)

            if survey_task is not None:
                survey_task.status = TaskStatus.AWAITING_GATE
                self.bus.put_pipeline(pipeline)

            decision = review_gate.wait_survey(session_id)

            if survey_task is not None:
                survey_task.status = TaskStatus.COMPLETED
                self.bus.put_pipeline(pipeline)

            if not decision.paper_ids:
                return

            paper_input = ", ".join(decision.paper_ids)
            if survey_task is None:
                return

            feedback = f"Please specifically use and analyze these papers: {paper_input}"
            survey_task.description = (survey_task.description or "") + f"\n\n[User provided papers]: {feedback}"
            survey_task.retries = 0
            survey_task.status = TaskStatus.PENDING

            arxiv_tool = self.tool_registry.get("arxiv_search")
            if arxiv_tool:
                arxiv_tool.exact_match_mode = True

            agent = self.router.resolve(survey_task)
            result = await agent.execute(survey_task)

            if arxiv_tool:
                arxiv_tool.exact_match_mode = False

            if result.failed:
                survey_task.mark_failed(result.error)
            else:
                task_outputs = dict(result.output)
                if result.text_summary:
                    task_outputs["text_summary"] = result.text_summary
                if result.token_usage:
                    task_outputs["token_usage"] = result.token_usage
                survey_task.mark_completed(task_outputs)
                self.gate.print_stage_summary("survey")

            self.bus.put_pipeline(pipeline)
            return

        console.print("\n[yellow]⚠ Survey stage completed but found 0 papers.[/yellow]")
        try:
            paper_input = Prompt.ask(
                "[bold cyan]Please provide a comma-separated list of paper IDs/titles to retry, or press Enter to proceed without papers[/bold cyan]"
            )
        except (KeyboardInterrupt, EOFError):
            console.print("\n[dim]Input interrupted — proceeding without papers.[/dim]")
            return

        if not paper_input.strip():
            return

        survey_task = next((t for t in pipeline.tasks if t.name == "survey"), None)
        if not survey_task:
            return

        # Inject the manual overrides and ready the task for re-execution
        feedback = f"Please specifically use and analyze these papers: {paper_input.strip()}"
        survey_task.description = (survey_task.description or "") + f"\n\n[User provided papers]: {feedback}"
        survey_task.retries = 0
        survey_task.status = TaskStatus.PENDING

        # Enable exact match schema on the arXiv tool specifically for this retry
        arxiv_tool = self.tool_registry.get("arxiv_search")
        if arxiv_tool:
            arxiv_tool.exact_match_mode = True

        console.print(f"\n[yellow]Re-running survey agent with your provided papers...[/yellow]")
        agent = self.router.resolve(survey_task)

        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"), console=console) as progress:
            prog_task = progress.add_task("survey (revision)...", total=None)
            result = await agent.execute(survey_task)
            progress.update(prog_task, completed=True)

        # Restore standard schema behavior after execution
        if arxiv_tool:
            arxiv_tool.exact_match_mode = False

        if result.failed:
            survey_task.mark_failed(result.error)
            console.print(f"[red]Survey revision failed: {result.error[:100]}[/red]")
        else:
            task_outputs = dict(result.output)
            if result.text_summary:
                task_outputs["text_summary"] = result.text_summary
            if result.token_usage:
                task_outputs["token_usage"] = result.token_usage
            survey_task.mark_completed(task_outputs)
            console.print("[green]✓ Survey revision complete.[/green]")
            self.gate.print_stage_summary("survey")

    def _dependencies_met(self, task: Task, pipeline: TaskPipeline) -> bool:
        for dep_id in task.depends_on:
            dep = pipeline.get_task(dep_id)
            if dep is None:
                continue
            if dep.status == TaskStatus.FAILED:
                logger.warning(
                    "Skipping '%s': dependency '%s' failed — %s",
                    task.name, dep.name, dep.error_message or "(no message)",
                )
                return False
            if dep.status == TaskStatus.SKIPPED:
                logger.warning("Skipping '%s': dependency '%s' was skipped", task.name, dep.name)
                return False
            if dep.status != TaskStatus.COMPLETED:
                return False
        return True

    def _collect_outputs(self, brief: ResearchBrief) -> ResearchOutput:
        import json
        from eurekaclaw.types.tasks import ResearchOutput

        theory_state = self.bus.get_theory_state()
        exp_result = self.bus.get_experiment_result()
        bib = self.bus.get_bibliography()

        # WriterAgent stores its output in task.outputs (via mark_completed),
        # not on the bus under a "writer" key.  Retrieve it from the pipeline.
        pipeline = self.bus.get_pipeline()
        latex_paper = ""
        if pipeline:
            writer_task = next((t for t in pipeline.tasks if t.name == "writer"), None)
            if writer_task and writer_task.outputs:
                latex_paper = writer_task.outputs.get("latex_paper", "")

        return ResearchOutput(
            session_id=brief.session_id,
            latex_paper=latex_paper,
            theory_state_json=theory_state.model_dump_json(indent=2) if theory_state else "",
            experiment_result_json=exp_result.model_dump_json(indent=2) if exp_result else "",
            research_brief_json=brief.model_dump_json(indent=2),
            bibliography_json=bib.model_dump_json(indent=2) if bib else "",
        )
