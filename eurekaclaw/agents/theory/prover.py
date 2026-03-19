"""Prover — LLM chain-of-thought proof attempts, optionally dispatching to Lean4."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import TYPE_CHECKING

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.types.artifacts import LemmaNode, TheoryState

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

PROVE_SYSTEM = """\
You are an expert mathematical proof writer specializing in rigorous proofs for theoretical \
computer science, machine learning theory, and pure mathematics.

Your proof attempts must be:
1. Logically complete — every step follows from previous steps or stated assumptions
2. Formally precise — use correct mathematical notation
3. Well-structured — state the proof strategy at the start
4. Honest about gaps — if you're uncertain about a step, flag it explicitly as [GAP: ...]

When you cannot complete a proof, explain exactly which step fails and why.
"""

PROVE_USER = """\
Prove the following lemma:

Lemma ID: {lemma_id}
Statement: {statement}
Informal: {informal}

Already proven lemmas you may cite (statement only):
{proven_lemmas}

Dependencies for this lemma:
{dependencies}

Provide a complete, rigorous proof. Use LaTeX notation.
Start with the proof strategy, then give the detailed proof steps.
If this requires techniques from a specific area (e.g., concentration inequalities,
measure theory), state which techniques you're using.
"""


@dataclass
class ProofAttempt:
    lemma_id: str
    proof_text: str
    lean4_sketch: str
    confidence: float        # 0-1
    gaps: list[str]          # steps flagged as [GAP: ...]
    success: bool


class Prover:
    """Step 3 of the Theory Agent inner loop: LLM CoT + optional Lean4 dispatch."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def attempt(
        self,
        state: TheoryState,
        lemma_id: str,
        skill_context: str = "",
    ) -> ProofAttempt:
        """Attempt to prove lemma_id given the current state.

        Args:
            state: current TheoryState
            lemma_id: which lemma to prove
            skill_context: optional XML skill block (from SkillInjector) appended
                           to the system prompt to guide proof technique selection
        """
        node = state.lemma_dag.get(lemma_id)
        if not node:
            return ProofAttempt(
                lemma_id=lemma_id, proof_text="", lean4_sketch="",
                confidence=0.0, gaps=[], success=False,
            )

        proven_summary = self._format_proven(state)
        deps_summary = self._format_dependencies(state, node)
        system = PROVE_SYSTEM + ("\n\n" + skill_context if skill_context else "")

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=4096,
                system=system,
                messages=[{
                    "role": "user",
                    "content": PROVE_USER.format(
                        lemma_id=lemma_id,
                        statement=node.statement,
                        informal=node.informal,
                        proven_lemmas=proven_summary,
                        dependencies=deps_summary,
                    ),
                }],
            )
            text = response.content[0].text
            return self._parse_proof_attempt(lemma_id, text)

        except Exception as e:
            logger.exception("Proof attempt failed for %s: %s", lemma_id, e)
            return ProofAttempt(
                lemma_id=lemma_id,
                proof_text=f"Proof attempt failed: {e}",
                lean4_sketch="",
                confidence=0.0,
                gaps=[str(e)],
                success=False,
            )

    def _format_proven(self, state: TheoryState) -> str:
        """Compact representation of proven lemmas — statement only (no proof text).

        Inspired by Paper2Poster's 87%-fewer-tokens approach: include only the
        minimal information needed (lemma ID + statement), not the full proof.
        For large DAGs, show the 5 most recently proven lemmas plus a count.
        """
        if not state.proven_lemmas:
            return "(none yet)"
        items = list(state.proven_lemmas.items())
        lines = []
        if len(items) > 5:
            lines.append(f"(+{len(items) - 5} more proven lemmas not shown)")
        for lid, _record in items[-5:]:
            node = state.lemma_dag.get(lid)
            stmt = (node.statement[:120] if node else _record.proof_text[:80]).strip()
            lines.append(f"[{lid}] ✓ {stmt}")
        return "\n".join(lines)

    def _format_dependencies(self, state: TheoryState, node: LemmaNode) -> str:
        deps = []
        for dep_id in node.dependencies:
            dep_node = state.lemma_dag.get(dep_id)
            if dep_node:
                # Truncate long dependency statements to save tokens
                stmt = dep_node.statement[:120] if len(dep_node.statement) > 120 else dep_node.statement
                deps.append(f"[{dep_id}]: {stmt}")
        return "\n".join(deps) if deps else "(no sub-dependencies)"

    def _parse_proof_attempt(self, lemma_id: str, text: str) -> ProofAttempt:
        """Parse the LLM's proof text into a ProofAttempt."""
        gaps = []
        # Extract explicit gaps
        import re
        gap_matches = re.findall(r"\[GAP:\s*([^\]]+)\]", text, re.IGNORECASE)
        gaps.extend(gap_matches)

        # Assess confidence based on presence of gaps and completeness signals
        has_qed = any(kw in text.lower() for kw in ["qed", "□", "\\qed", "this completes", "as desired"])
        confidence = 0.8 if (has_qed and not gaps) else (0.5 if has_qed else 0.3)

        # Boost confidence when prover explicitly states no gaps remain
        if has_qed and not gaps and "therefore" in text.lower() and len(text) > 500:
            confidence = min(confidence + 0.1, 1.0)

        # Extract Lean4 sketch if present
        lean4_sketch = ""
        if "```lean" in text.lower():
            start_marker = text.lower().index("```lean")
            try:
                end_marker = text.index("```", start_marker + 7)
                lean4_sketch = text[start_marker + 7:end_marker].strip()
            except ValueError:
                pass

        success = len(gaps) == 0 and confidence >= 0.5

        return ProofAttempt(
            lemma_id=lemma_id,
            proof_text=text,
            lean4_sketch=lean4_sketch,
            confidence=confidence,
            gaps=gaps,
            success=success,
        )
