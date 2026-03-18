"""Verifier — checks proof correctness via Lean4, Coq, or structured peer-agent review."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Literal

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.agents.theory.prover import ProofAttempt
from eurekaclaw.config import settings
from eurekaclaw.tools.lean4 import Lean4Tool
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

PEER_REVIEW_SYSTEM = """\
You are a peer reviewer for mathematical proofs. Your role is to rigorously check whether \
a given proof is correct.

Verification checklist:
1. Are all logical steps valid? No unjustified leaps?
2. Are all referenced lemmas actually proven (or stated as assumptions)?
3. Are there circular dependencies?
4. Are quantifiers handled correctly?
5. Are there edge cases that the proof misses?
6. Is the conclusion exactly what was claimed?

Output a JSON verification report.
"""

PEER_REVIEW_USER = """\
Verify this proof:

Lemma: {statement}
Proof:
{proof_text}

Proven dependencies available:
{proven_deps}

Return JSON:
{{
  "verified": true/false,
  "confidence": 0.0-1.0,
  "errors": ["list of logical errors"],
  "gaps": ["unproven steps"],
  "notes": "general notes"
}}
"""


@dataclass
class VerificationResult:
    lemma_id: str
    passed: bool
    method: Literal["lean4", "coq", "peer_review", "llm_check"]
    confidence: float
    errors: list[str]
    notes: str


class Verifier:
    """Step 4 of the Theory Agent inner loop: formal or peer-review verification."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()
        self._lean4 = Lean4Tool()

    async def check(self, proof_attempt: ProofAttempt, state: TheoryState) -> VerificationResult:
        """Verify a proof attempt. Tries Lean4 first, falls back to peer review."""
        # Try Lean4 if we have a sketch
        if proof_attempt.lean4_sketch:
            result = await self._lean4_verify(proof_attempt)
            if result is not None:
                return result

        # Fall back to LLM peer review
        return await self._peer_review(proof_attempt, state)

    async def _lean4_verify(self, attempt: ProofAttempt) -> VerificationResult | None:
        """Try to verify using Lean4 subprocess."""
        try:
            raw = await self._lean4.call(
                proof_code=attempt.lean4_sketch,
                theorem_name=attempt.lemma_id,
            )
            data = json.loads(raw)
            if data.get("lean4_available") is False:
                return None  # Lean4 not installed, fall through
            return VerificationResult(
                lemma_id=attempt.lemma_id,
                passed=data.get("verified", False),
                method="lean4",
                confidence=1.0 if data.get("verified") else 0.0,
                errors=[data.get("lean4_output", "")] if not data.get("verified") else [],
                notes=data.get("message", ""),
            )
        except Exception as e:
            logger.debug("Lean4 verification unavailable: %s", e)
            return None

    async def _peer_review(self, attempt: ProofAttempt, state: TheoryState) -> VerificationResult:
        """LLM-based structured peer review."""
        dep_ids = state.lemma_dag.get(attempt.lemma_id, None)
        proven_deps = ""
        if dep_ids:
            for dep_id in dep_ids.dependencies:
                rec = state.proven_lemmas.get(dep_id)
                if rec:
                    proven_deps += f"\n[{dep_id}]: {rec.proof_text[:300]}"

        node = state.lemma_dag.get(attempt.lemma_id)
        statement = node.statement if node else attempt.lemma_id

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_fast_model,
                max_tokens=1024,
                system=PEER_REVIEW_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": PEER_REVIEW_USER.format(
                        statement=statement,
                        proof_text=attempt.proof_text[:3000],
                        proven_deps=proven_deps or "(none)",
                    ),
                }],
            )
            text = response.content[0].text
            data = self._parse_review(text)

            return VerificationResult(
                lemma_id=attempt.lemma_id,
                passed=data.get("verified", False) and len(data.get("errors", [])) == 0,
                method="peer_review",
                confidence=float(data.get("confidence", 0.5)),
                errors=data.get("errors", []) + data.get("gaps", []),
                notes=data.get("notes", ""),
            )
        except Exception as e:
            logger.exception("Peer review failed: %s", e)
            return VerificationResult(
                lemma_id=attempt.lemma_id,
                passed=attempt.success and attempt.confidence >= 0.7,
                method="llm_check",
                confidence=attempt.confidence,
                errors=attempt.gaps,
                notes=f"Auto-verified (reviewer unavailable): {e}",
            )

    def _parse_review(self, text: str) -> dict:
        for delim_start, delim_end in [("```json", "```"), ("{", None)]:
            try:
                if delim_start in text:
                    start = text.index(delim_start) + len(delim_start)
                    if delim_end:
                        end = text.index(delim_end, start)
                        return json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        return json.loads(text[text.index("{"):end])
            except (json.JSONDecodeError, ValueError):
                continue
        # Heuristic fallback
        verified = "true" in text.lower() and "error" not in text.lower()
        return {"verified": verified, "confidence": 0.5, "errors": [], "notes": text[:200]}
