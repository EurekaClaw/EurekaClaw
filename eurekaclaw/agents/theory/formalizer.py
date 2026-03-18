"""Formalizer — translates informal mathematical intuition into rigorous formal notation."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import TheoryState

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

FORMALIZE_SYSTEM = """\
You are a mathematical formalization expert. Your role is to translate informal mathematical \
intuitions and conjectures into precise, rigorous formal notation suitable for proof assistants \
(Lean4, Coq) or LaTeX theorem environments.

When given an informal statement, produce:
1. A precise LaTeX formulation using standard mathematical notation
2. All necessary variable declarations and type annotations
3. Any implicit assumptions made explicit
4. The exact quantifiers and logical connectives

Use standard notation from the relevant domain (analysis, probability theory, linear algebra, etc.)
"""

FORMALIZE_USER = """\
Formalize the following informal mathematical statement into rigorous notation:

Informal statement: {informal}
Domain: {domain}
Context (known definitions and assumptions): {context}

Produce:
1. **Formal LaTeX statement**: The theorem written as `\\begin{{theorem}}...\\end{{theorem}}`
2. **Variable declarations**: Define all variables and their types
3. **Implicit assumptions**: List any assumptions not in the informal statement
4. **Lean4 sketch** (optional): A sketch of the Lean4 theorem statement

Keep the formalization as close to standard mathematical practice as possible.
"""


class Formalizer:
    """Step 1 of the Theory Agent inner loop: informal → formal notation."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Translate informal_statement → formal_statement on the TheoryState."""
        if not state.informal_statement:
            logger.warning("No informal statement to formalize")
            return state

        if state.formal_statement and state.iteration > 0:
            # Only re-formalize on retry if the conjecture was updated
            logger.debug("Skipping re-formalization (already formalized, iteration %d)", state.iteration)
            return state

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=2048,
                system=FORMALIZE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": FORMALIZE_USER.format(
                        informal=state.informal_statement,
                        domain=domain or "mathematics",
                        context=", ".join(state.lemma_dag.keys()) or "none",
                    ),
                }],
            )
            text = response.content[0].text

            # Extract the formal statement from the response
            formal = self._extract_formal_statement(text)
            state.formal_statement = formal
            logger.info("Formalized: %s → %s", state.informal_statement[:80], formal[:80])

        except Exception as e:
            logger.exception("Formalization failed: %s", e)
            # Fallback: use informal statement as formal statement
            state.formal_statement = f"\\text{{(Informal) }} {state.informal_statement}"

        return state

    def _extract_formal_statement(self, text: str) -> str:
        """Extract the LaTeX theorem block from the LLM response."""
        if "\\begin{theorem}" in text and "\\end{theorem}" in text:
            start = text.index("\\begin{theorem}")
            end = text.index("\\end{theorem}") + len("\\end{theorem}")
            return text[start:end]
        # Fallback: return the first substantial paragraph
        lines = [l.strip() for l in text.split("\n") if l.strip()]
        for line in lines:
            if len(line) > 50 and ("\\forall" in line or "\\exists" in line or "$" in line or ":" in line):
                return line
        return text[:500]
