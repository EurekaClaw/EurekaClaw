"""MetaOrchestrator — the central brain driving the full research pipeline."""

from __future__ import annotations

import logging
from pathlib import Path

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

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

logger = logging.getLogger(__name__)
console = Console()


class MetaOrchestrator:
    """Central brain. Drives the full pipeline from input spec to research output."""

    def __init__(
        self,
        bus: KnowledgeBus,
        tool_registry: ToolRegistry | None = None,
        skill_registry: SkillRegistry | None = None,
        client: LLMClient | None = None,
        domain_plugin: DomainPlugin | None = None,
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

        self.skill_injector = SkillInjector(self.skill_registry)
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
        if brief.input_mode == "detailed" and brief.conjecture:
            console.print("[blue]Detailed mode: using conjecture directly as research direction[/blue]")
            domain_label = brief.domain or "the Conjecture"
            direction = ResearchDirection(
                direction_id=str(uuid.uuid4()),
                title=f"Proof of {domain_label}",
                hypothesis=brief.conjecture,
                approach_sketch=(
                    "Formalize the conjecture, decompose into lemmas, "
                    "attempt proof via mathematical induction / known bounds."
                ),
                novelty_score=0.8,
                soundness_score=0.8,
                transformative_score=0.7,
            )
            direction.compute_composite()
            brief.directions = [direction]
            brief.selected_direction = direction
            self.bus.put_research_brief(brief)
            console.print(f"[green]Direction set to: {direction.title}[/green]")
            return

        # --- Exploration / reference mode: run full divergent-convergent ---
        console.print("[blue]Generating 5 research directions...[/blue]")
        try:
            directions = await self.planner.diverge(brief)
            best = await self.planner.converge(directions, brief)
            brief.directions = directions
            brief.selected_direction = best
            self.bus.put_research_brief(brief)
            console.print(f"[green]Best direction selected: {best.title}[/green]")
            console.print(f"  Composite score: {best.composite_score:.2f}")
            console.print(f"  Hypothesis: {best.hypothesis[:200]}")
        except Exception as e:
            logger.exception("Direction planning failed: %s", e)

    async def _handle_theory_review_gate(
        self, pipeline: "TaskPipeline", brief: "ResearchBrief"
    ) -> None:
        """Show the proof sketch to the user and optionally re-run theory.

        If the user rejects, their feedback (which lemma + what's wrong) is
        injected into the theory task description and theory is re-executed once.
        """
        from eurekaclaw.types.tasks import TaskStatus

        approved, lemma_ref, reason = self.gate.theory_review_prompt()
        if approved:
            return

        # Find the theory task and re-queue it with the user's feedback
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

        console.print(f"[yellow]Re-running theory agent with your feedback...[/yellow]\n")
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

        # Show the updated sketch for a second look (no further retry)
        approved2, _, _ = self.gate.theory_review_prompt()
        if not approved2:
            console.print(
                "[yellow]Sketch still flagged — proceeding to writer anyway.[/yellow]\n"
            )

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
