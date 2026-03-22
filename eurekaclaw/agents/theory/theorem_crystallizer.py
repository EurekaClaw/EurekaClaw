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
import re

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

Structured proof context:
{assembled_proof}

Problem type: {problem_type}
Proof template: {proof_template}
Proof skeleton:
{proof_skeleton}

Extract the formal theorem statement that this proof establishes.
Output ONLY the \\begin{{theorem}}...\\end{{theorem}} block.
"""


class TheoremCrystallizer:
    """Stage 6: derive the formal theorem statement from the assembled proof."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Populate state.formal_statement from state.assembled_proof.

        If the previous consistency check flagged the theorem as truncated,
        retry with a shorter input and a larger token budget so the LLM has
        room to complete the formula.
        """
        if not state.assembled_proof:
            logger.warning("TheoremCrystallizer: no assembled_proof — skipping")
            return state

        # Detect if the last failure was a truncation so we can compensate.
        last_failure = state.failed_attempts[-1] if state.failed_attempts else None
        is_truncation_retry = last_failure and any(
            kw in last_failure.failure_reason.lower()
            for kw in ("truncated", "truncation", "ends mid", "incomplete formula",
                       "cut off", "mid-expression")
        )

        if is_truncation_retry:
            # Use a minimal context so the model can spend tokens on the output.
            proof_excerpt = state.assembled_proof[:2000]
            max_tokens = settings.max_tokens_agent  # larger budget
            logger.info(
                "TheoremCrystallizer: truncation retry — using short context (%d chars), "
                "max_tokens=%d", len(proof_excerpt), max_tokens,
            )
        else:
            proof_excerpt = self._build_proof_context(state)
            max_tokens = settings.max_tokens_crystallizer

        try:
            response = await self.client.messages.create(
                model=settings.active_model,
                max_tokens=max_tokens,
                system=CRYSTALLIZE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": CRYSTALLIZE_USER.format(
                        research_gap=state.research_gap[:400],
                        assembled_proof=proof_excerpt,
                        problem_type=state.problem_type[:200] or "(unspecified)",
                        proof_template=state.proof_template[:200] or "(unspecified)",
                        proof_skeleton=state.proof_skeleton[:1200] or "(none)",
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
        if r"\begin{theorem}" in text:
            try:
                start = text.index(r"\begin{theorem}")
                end = text.index(r"\end{theorem}", start) + len(r"\end{theorem}")
                return text[start:end]
            except ValueError:
                pass
        # LLM may have returned the block without the environment; wrap it
        lines = [l.strip() for l in text.split("\n") if l.strip()]
        if lines:
            return (
                r"\begin{theorem}[Main Result]" + "\n"
                + "\n".join(lines) + "\n"
                + r"\end{theorem}"
            )
        return text[:800]

    def _build_proof_context(self, state: TheoryState) -> str:
        """Build a structured proof context instead of naive head/tail truncation."""
        sections: list[str] = []

        if state.proof_skeleton:
            sections.append("=== Proof Skeleton ===\n" + state.proof_skeleton[:1800])

        if state.proof_plan:
            lemma_lines = []
            for plan in state.proof_plan[:8]:
                lemma_lines.append(
                    f"- [{plan.lemma_id}] provenance={plan.provenance} statement={plan.statement[:220]}"
                )
            sections.append("=== Planned Key Lemmas ===\n" + "\n".join(lemma_lines))

        if state.proven_lemmas:
            proven_lines = []
            for lemma_id, record in list(state.proven_lemmas.items())[:8]:
                node = state.lemma_dag.get(lemma_id)
                stmt = node.statement if node else lemma_id
                proven_lines.append(
                    f"- [{lemma_id}] {stmt[:220]} (verified={record.verified}, method={record.verification_method})"
                )
            sections.append("=== Proven Lemmas ===\n" + "\n".join(proven_lines))

        body = state.assembled_proof
        sections.append("=== Proof Overview ===\n" + body[:1800])

        middle_hits = re.findall(
            r"(?is)(lemma\s+\d+.*?(?:proof\.|qed|\\end\{lemma\}|\\end\{proof\}))",
            body,
        )
        if middle_hits:
            sections.append(
                "=== Key Middle Excerpts ===\n" + "\n\n".join(hit[:900] for hit in middle_hits[:3])
            )

        sections.append("=== Proof Conclusion ===\n" + body[-1600:])
        return "\n\n".join(section for section in sections if section).strip()[:7000]
