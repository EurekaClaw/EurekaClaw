"""CounterexampleSearcher — adversarial sub-agent to falsify conjectures."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.types.artifacts import Counterexample, TheoryState

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

COUNTEREXAMPLE_SYSTEM = """\
You are an adversarial mathematical agent. Your goal is to find counterexamples to conjectures.

A good counterexample is:
1. A specific, concrete instance that satisfies all the hypotheses
2. But violates the conclusion
3. Can be verified by explicit computation

When searching for counterexamples:
- Consider extremal cases (n→0, n→∞, degenerate cases)
- Consider structure-breaking cases (e.g., discontinuous functions for continuity claims)
- Consider randomized constructions
- For combinatorial claims, try small cases first

If you cannot find a counterexample, explain why and suggest how the conjecture might be strengthened.
"""

COUNTEREXAMPLE_USER = """\
Attempt to find a counterexample to the following lemma:

Lemma: {statement}
Current proof attempt (which failed with reason: {failure_reason}):
{proof_text}

Search for:
1. A concrete counterexample (specific values satisfying hypotheses but violating conclusion)
2. If no counterexample: the hidden assumption that makes the proof fail
3. A suggested refinement of the conjecture that IS true

For each candidate counterexample, verify it step by step.
"""


class CounterexampleSearcher:
    """Step 5 of the Theory Agent inner loop: adversarial falsification."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def search(
        self,
        state: TheoryState,
        lemma_id: str,
        failure_reason: str = "",
        proof_text: str = "",
    ) -> Counterexample:
        """Search for a counterexample to lemma_id."""
        node = state.lemma_dag.get(lemma_id)
        if not node:
            return Counterexample(
                lemma_id=lemma_id,
                counterexample_description="Lemma node not found",
                falsifies_conjecture=False,
                suggested_refinement="",
            )

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=2048,
                system=COUNTEREXAMPLE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": COUNTEREXAMPLE_USER.format(
                        statement=node.statement,
                        failure_reason=failure_reason or "Proof verification failed",
                        proof_text=proof_text[:2000] or "(no proof text)",
                    ),
                }],
            )
            text = response.content[0].text
            return self._parse_counterexample(lemma_id, text)

        except Exception as e:
            logger.exception("Counterexample search failed: %s", e)
            return Counterexample(
                lemma_id=lemma_id,
                counterexample_description=f"Search failed: {e}",
                falsifies_conjecture=False,
                suggested_refinement="",
            )

    def _parse_counterexample(self, lemma_id: str, text: str) -> Counterexample:
        """Parse the adversarial agent's output."""
        text_lower = text.lower()

        # Detect if a genuine counterexample was found
        counterexample_signals = [
            "counterexample:", "consider x =", "let x =", "take n =",
            "the function f(x) =", "for example, when", "specific example",
        ]
        falsifies = any(sig in text_lower for sig in counterexample_signals)

        # Extract suggested refinement
        refinement = ""
        for marker in ["suggested refinement", "stronger version", "modified conjecture", "instead, the true"]:
            if marker in text_lower:
                idx = text_lower.index(marker)
                refinement = text[idx:idx + 500].strip()
                break

        return Counterexample(
            lemma_id=lemma_id,
            counterexample_description=text[:1000],
            falsifies_conjecture=falsifies,
            suggested_refinement=refinement,
        )
