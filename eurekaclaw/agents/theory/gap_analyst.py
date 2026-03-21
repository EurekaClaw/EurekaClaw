"""GapAnalyst — Stage 2 of the bottom-up proof pipeline.

Given the set of known results extracted from the literature and the
research direction selected by the planner, identifies precisely what
is *not* yet proven and what a novel contribution would look like.

Deliberately produces an *informal* research gap description — no
formal theorem statement yet.  The exact statement will only crystallize
in Stage 6 (TheoremCrystallizer) after the proof is assembled.
"""

from __future__ import annotations

import logging

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

GAP_SYSTEM = """\
You are a senior researcher in theoretical machine learning and mathematics.
You have been given a list of known results from the literature and a
research direction.  Your task is to identify the *gap*: what is not yet
known, what the novel contribution of a new paper should be, and what
the key technical challenges are.

Be concrete about:
1. Which specific result is missing (e.g. "no tight regret lower bound
   exists for this family of algorithms under sub-Gaussian noise")
2. Why existing results do not cover it (e.g. "prior work assumes
   bounded rewards; sub-Gaussian noise requires different concentration")
3. What proof techniques from the known results are likely to be
   *reusable* versus what is genuinely new
4. What the expected form of the new result is (e.g. "an O(d√T log T)
   upper bound") — but state this informally; do not commit to notation

Do NOT write a formal theorem statement.  The goal is to give the proof
architect a clear informal target.
"""

GAP_USER = """\
Research direction: {direction}
Domain: {domain}

Known results extracted from the literature ({n_results} total):
{known_results_summary}

Identify the research gap.  Write 3-5 paragraphs covering the four
points above.  Be specific about the mathematical objects involved.
"""


class GapAnalyst:
    """Stage 2: identify the research gap from known results + direction."""

    def __init__(self, bus: KnowledgeBus, client: LLMClient | None = None) -> None:
        self.bus = bus
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Populate state.research_gap."""
        brief = self.bus.get_research_brief()
        direction = (
            brief.selected_direction.hypothesis
            if brief and brief.selected_direction
            else state.informal_statement or domain
        )

        known_summary = self._summarize_known(state)

        try:
            response = await self.client.messages.create(
                model=settings.active_model,
                max_tokens=settings.max_tokens_formalizer,
                system=GAP_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": GAP_USER.format(
                        direction=direction[:400],
                        domain=domain or "mathematics",
                        n_results=len(state.known_results),
                        known_results_summary=known_summary,
                    ),
                }],
            )
            if not response.content:
                raise ValueError("LLM returned empty content list")
            state.research_gap = response.content[0].text.strip()
            logger.info("GapAnalyst: research gap identified (%d chars)", len(state.research_gap))
        except Exception as e:
            logger.exception("GapAnalyst failed: %s", e)
            state.research_gap = (
                f"Research direction: {direction}\n\n"
                f"(Gap analysis unavailable: {e})"
            )

        return state

    def _summarize_known(self, state: TheoryState) -> str:
        if not state.known_results:
            return "(no known results extracted from literature)"
        lines = []
        for kr in state.known_results:
            line = (
                f"[{kr.result_type.upper()}] {kr.informal or kr.statement[:100]}"
                f" — technique: {kr.proof_technique or 'unspecified'}"
                f" (from: {kr.source_paper_title[:50]})"
            )
            lines.append(line)
        return "\n".join(lines)
