"""Refiner — updates conjectures and re-routes based on counterexample evidence."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.types.artifacts import Counterexample, TheoryState

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

REFINE_SYSTEM = """\
You are a mathematical conjecture refinement expert. Given a failed proof attempt and \
counterexample evidence, your task is to:

1. Diagnose what went wrong (incorrect hypothesis, missing assumption, wrong conclusion)
2. Propose a refined version of the conjecture that:
   - Is not falsified by the found counterexample
   - Is still interesting and non-trivial
   - Has a clearer proof path

Output both the new informal statement and the approach for proving it.
"""

REFINE_USER = """\
The following conjecture failed verification:

Original informal: {informal}
Original formal: {formal}

Counterexample evidence:
{counterexample}

Failed proof attempts for lemma {lemma_id}:
{failure_summary}

Please refine the conjecture:
1. **Diagnosis**: What is the fundamental issue?
2. **Refined informal statement**: The corrected version
3. **Refined formal statement** (LaTeX): The precise corrected theorem
4. **Why the refinement works**: Why the counterexample no longer applies
5. **New proof approach**: Revised strategy
"""


class Refiner:
    """Step 6 of the Theory Agent inner loop: update conjecture and prepare for retry."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def refine(
        self,
        state: TheoryState,
        lemma_id: str,
        counterexample: Counterexample,
    ) -> TheoryState:
        """Refine the conjecture based on counterexample evidence."""
        failure_summary = self._summarize_failures(state, lemma_id)

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=settings.max_tokens_formalizer,
                system=REFINE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": REFINE_USER.format(
                        informal=state.informal_statement,
                        formal=state.formal_statement,
                        counterexample=counterexample.counterexample_description[:1000],
                        lemma_id=lemma_id,
                        failure_summary=failure_summary,
                    ),
                }],
            )
            if not response.content:
                raise ValueError("LLM returned empty content list")
            text = response.content[0].text
            refined_informal, refined_formal = self._extract_refinements(text)

            if refined_informal:
                logger.info(
                    "Refined conjecture: %s → %s",
                    state.informal_statement[:60],
                    refined_informal[:60],
                )
                state.informal_statement = refined_informal
                state.formal_statement = refined_formal or state.formal_statement
                # Reset the DAG and proven lemmas — the refined conjecture is a
                # different theorem and old proofs no longer apply.
                state.lemma_dag.clear()
                state.open_goals.clear()
                state.proven_lemmas.clear()
            else:
                logger.warning("Refiner produced no clear refinement, keeping original")

        except Exception as e:
            logger.exception("Refinement failed: %s", e)

        return state

    def _summarize_failures(self, state: TheoryState, lemma_id: str) -> str:
        relevant = [f for f in state.failed_attempts if f.lemma_id == lemma_id]
        return "\n".join(f"- {f.failure_reason}" for f in relevant[-3:]) or "(no prior failures)"

    def _extract_refinements(self, text: str) -> tuple[str, str]:
        """Extract refined informal and formal statements from the LLM response."""
        informal = ""
        formal = ""

        lines = text.split("\n")
        capture_informal = False
        capture_formal = False
        formal_lines = []

        for line in lines:
            stripped = line.strip()
            if "refined informal" in stripped.lower() or "**refined informal" in stripped.lower():
                capture_informal = True
                capture_formal = False
                continue
            if "refined formal" in stripped.lower() or "**refined formal" in stripped.lower():
                capture_informal = False
                capture_formal = True
                continue
            if stripped.startswith("##") or stripped.startswith("**") and not (
                "refined" in stripped.lower()
            ):
                capture_informal = False
                capture_formal = False

            if capture_informal and stripped and not informal:
                informal = stripped.lstrip(":")
            if capture_formal and stripped:
                formal_lines.append(stripped)

        if formal_lines:
            formal = "\n".join(formal_lines[:10])

        # Fallback: extract LaTeX theorem block
        if not formal and "\\begin{theorem}" in text:
            start = text.index("\\begin{theorem}")
            end = text.index("\\end{theorem}") + len("\\end{theorem}") if "\\end{theorem}" in text else start + 200
            formal = text[start:end]

        return informal, formal
