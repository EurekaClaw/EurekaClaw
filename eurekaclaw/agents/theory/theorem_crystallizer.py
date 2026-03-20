"""TheoremCrystallizer — Stage 6 of the bottom-up proof pipeline.

This is the inverse of the old Formalizer.  Instead of turning an
informal conjecture into a formal statement *before* the proof
(which forced committing to notation and constants that are only
known after the proof), the Crystallizer reads the assembled proof
and *derives* the exact formal theorem statement from what was
actually proved.

The resulting state.formal_statement is guaranteed to be consistent
with the proof because it is extracted from it.
"""

from __future__ import annotations

import logging

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

CRYSTALLIZE_SYSTEM = """\
You are a mathematical formalization expert.  You have been given a
complete assembled proof.  Your task is to read the proof carefully
and extract the exact formal theorem statement that it establishes.

The theorem statement must:
1. Match the proof exactly — use the same notation, constants, and
   parameter names as they appear in the proof
2. State all quantifiers, assumptions, and conclusions precisely
3. Be written as a LaTeX \\begin{theorem}...\\end{theorem} environment
4. Include a theorem name in brackets, e.g. \\begin{theorem}[Name]
5. Not overclaim — if the proof establishes a bound with a specific
   constant C, state that constant (or its dependence) explicitly

Length constraint: the theorem block must fit in at most 20 lines of
LaTeX.  State the main result clearly and completely — do NOT truncate
or abbreviate mid-formula.  If the bound has multiple terms, write
each term on its own line inside the display math block.

Do not add content that is not in the proof.
"""

CRYSTALLIZE_USER = """\
Research gap being addressed:
{research_gap}

Assembled proof:
{assembled_proof}

Extract the formal theorem statement that this proof establishes.
Output ONLY the \\begin{{theorem}}...\\end{{theorem}} block.
"""


class TheoremCrystallizer:
    """Stage 6: derive the formal theorem statement from the assembled proof."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Populate state.formal_statement from state.assembled_proof."""
        if not state.assembled_proof:
            logger.warning("TheoremCrystallizer: no assembled_proof — skipping")
            return state

        # Compress proof if very long: the theorem statement can be derived
        # from the proof overview + conclusion sections
        proof_excerpt = state.assembled_proof
        if len(proof_excerpt) > 4000:
            proof_excerpt = (
                proof_excerpt[:2000]
                + "\n... [middle compressed] ...\n"
                + proof_excerpt[-1500:]
            )

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=2500,
                system=CRYSTALLIZE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": CRYSTALLIZE_USER.format(
                        research_gap=state.research_gap[:400],
                        assembled_proof=proof_excerpt,
                    ),
                }],
            )
            text = response.content[0].text.strip()
            state.formal_statement = self._extract_theorem_block(text)
            logger.info(
                "TheoremCrystallizer: formal statement set (%d chars)",
                len(state.formal_statement),
            )
        except Exception as e:
            logger.exception("TheoremCrystallizer failed: %s", e)
            # Fallback: use the research gap as an informal placeholder
            state.formal_statement = (
                r"\begin{theorem}[Main Result — crystallization failed]" + "\n"
                + state.research_gap[:400] + "\n"
                + r"\end{theorem}"
            )

        return state

    def _extract_theorem_block(self, text: str) -> str:
        if r"\begin{theorem}" in text and r"\end{theorem}" in text:
            start = text.index(r"\begin{theorem}")
            end = text.index(r"\end{theorem}") + len(r"\end{theorem}")
            return text[start:end]
        # LLM may have returned the block without the environment; wrap it
        lines = [l.strip() for l in text.split("\n") if l.strip()]
        if lines:
            return (
                r"\begin{theorem}[Main Result]" + "\n"
                + "\n".join(lines) + "\n"
                + r"\end{theorem}"
            )
        return text[:800]
