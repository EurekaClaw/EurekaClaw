"""TheoryAgent — drives the inner proof loop from the ResearchBrief."""

from __future__ import annotations

import logging
import uuid

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.agents.theory.inner_loop_yaml import TheoryInnerLoopYaml
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.artifacts import TheoryState
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


class TheoryAgent(BaseAgent):
    """Manages the full theory proof workflow.

    Responsibilities:
    1. Initialize TheoryState from the selected ResearchDirection
    2. Run the TheoryInnerLoop (formalize → decompose → prove → verify → refine)
    3. Track and report proof status
    4. Expose failure log for continual learning
    """

    role = AgentRole.THEORY

    def get_tool_names(self) -> list[str]:
        return ["arxiv_search", "wolfram_alpha", "lean4_verify", "execute_python"]

    def _role_system_prompt(self, task: Task) -> str:
        return """\
You are the Theory Agent of EurekaClaw. You specialize in rigorous mathematical reasoning \
for theoretical computer science, machine learning theory, and pure mathematics.

The proof pipeline is specified by the YAML file loaded by TheoryInnerLoopYaml.
"""

    async def execute(self, task: Task) -> AgentResult:
        brief = self.bus.get_research_brief()
        if not brief:
            return self._make_result(task, False, {}, error="No ResearchBrief found on bus")

        direction = brief.selected_direction
        if not direction:
            # Fall back to first direction if no selection made
            if brief.directions:
                direction = brief.directions[0]
            else:
                return self._make_result(task, False, {}, error="No research direction selected")

        # In "detailed" mode the user supplied a specific conjecture — always
        # use it as the informal statement so the proof loop stays on target.
        # In exploration/reference mode, use the planner-selected hypothesis.
        if brief.input_mode == "detailed" and brief.conjecture:
            informal = brief.conjecture
        else:
            informal = direction.hypothesis

        # Initialize TheoryState
        state = TheoryState(
            session_id=brief.session_id,
            theorem_id=str(uuid.uuid4()),
            informal_statement=informal,
            formal_statement="",
            status="pending",
        )
        self.bus.put_theory_state(state)

        # Run the inner loop
        inner_loop = TheoryInnerLoopYaml(
            bus=self.bus,
            skill_injector=self.skill_injector,
        )

        try:
            final_state = await inner_loop.run(
                session_id=brief.session_id,
                domain=brief.domain,
            )

            success = final_state.status in ("proved",)
            proven_count = len(final_state.proven_lemmas)
            open_count = len(final_state.open_goals)

            self.memory.log_event(
                self.role.value,
                f"Theory loop: {final_state.status}, {proven_count} lemmas proved, {open_count} open",
            )

            # Add proven theorems to knowledge graph
            if success:
                self.memory.add_theorem(
                    theorem_name=direction.title,
                    formal_statement=final_state.formal_statement,
                    domain=brief.domain,
                    session_id=brief.session_id,
                    tags=[brief.domain.lower().replace(" ", "_")],
                )

            return self._make_result(
                task,
                success=success,
                output={
                    "status": final_state.status,
                    "theorem_id": final_state.theorem_id,
                    "proven_lemmas": proven_count,
                    "open_goals": open_count,
                    "iterations": final_state.iteration,
                    "failures": len(inner_loop.failure_log),
                },
                text_summary=(
                    f"Theorem {'proved' if success else final_state.status}: "
                    f"{proven_count} lemmas proved, {open_count} goals remain"
                ),
            )

        except Exception as e:
            logger.exception("Theory agent failed")
            return self._make_result(task, False, {}, error=str(e))
