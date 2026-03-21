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

Be conservative:
- Mark "verified": true only if the proof is fully justified end-to-end.
- If any material step is implicit, unclear, or plausibly false, return "verified": false.
- Confidence above 0.9 should be reserved for proofs with no meaningful ambiguity.

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
    method: Literal["lean4", "coq", "peer_review", "llm_check", "auto_high_confidence"]
    confidence: float
    errors: list[str]
    notes: str


class Verifier:
    """Step 4 of the Theory Agent inner loop: formal or peer-review verification."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()
        self._lean4 = Lean4Tool()

    @staticmethod
    def _threshold(value: float | str, fallback: float) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return fallback

    async def check(self, proof_attempt: ProofAttempt, state: TheoryState) -> VerificationResult:
        """Verify a proof attempt. Tries Lean4 first, falls back to peer review.

        High-confidence shortcut (strict version):
        if the prover assigned confidence >= AUTO_VERIFY_CONFIDENCE and there
        are no explicit [GAP:...] flags, skip the LLM peer-review call entirely.
        """
        auto_verify_threshold = self._threshold(settings.auto_verify_confidence, 0.95)

        # Fast-path: auto-accept proofs the prover is already confident about
        if (
            proof_attempt.success
            and proof_attempt.confidence >= auto_verify_threshold
            and not proof_attempt.gaps
        ):
            logger.info(
                "Auto-verifying lemma %s (confidence=%.2f, no gaps)",
                proof_attempt.lemma_id, proof_attempt.confidence,
            )
            return VerificationResult(
                lemma_id=proof_attempt.lemma_id,
                passed=True,
                method="auto_high_confidence",
                confidence=proof_attempt.confidence,
                errors=[],
                notes=(
                    f"Auto-verified: prover confidence {proof_attempt.confidence:.2f} "
                    f">= threshold {auto_verify_threshold:.2f}, no gaps."
                ),
            )

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
        """LLM-based structured peer review.

        Smart compaction: for long proofs only the strategy (head) and
        conclusion (tail) are sent; the middle is replaced with a placeholder.  Dependency proof texts are replaced with a simple PROVEN
        marker to eliminate redundant tokens.
        """
        dep_ids = state.lemma_dag.get(attempt.lemma_id, None)
        proven_deps = ""
        if dep_ids:
            for dep_id in dep_ids.dependencies:
                rec = state.proven_lemmas.get(dep_id)
                if rec:
                    # Use "PROVEN" marker instead of repeating full proof text
                    proven_deps += f"\n[{dep_id}]: PROVEN ✓"

        node = state.lemma_dag.get(attempt.lemma_id)
        statement = node.statement if node else attempt.lemma_id

        # Compress long proof texts: keep strategy (head) + conclusion (tail)
        proof_text = attempt.proof_text
        if len(proof_text) > 1500:
            head = proof_text[:600]
            tail = proof_text[-400:]
            proof_text = f"{head}\n... [middle section compressed] ...\n{tail}"

        try:
            verifier_pass_threshold = self._threshold(settings.verifier_pass_confidence, 0.90)
            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=settings.max_tokens_verifier,
                system=PEER_REVIEW_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": PEER_REVIEW_USER.format(
                        statement=statement,
                        proof_text=proof_text,
                        proven_deps=proven_deps or "(none)",
                    ),
                }],
            )
            if not response.content:
                raise ValueError("LLM peer review returned an empty content list (possible content filter or stop with no body)")
            text = response.content[0].text
            data = self._parse_review(text)

            confidence = float(data.get("confidence", 0.5))
            threshold = float(settings.verifier_pass_confidence)
            errors = data.get("errors", []) + data.get("gaps", [])
            passed = (
                bool(data.get("verified", False))
                and len(errors) == 0
                and confidence >= verifier_pass_threshold
            )

            return VerificationResult(
                lemma_id=attempt.lemma_id,
                passed=passed,
                method="peer_review",
                confidence=confidence,
                errors=errors,
                notes=(
                    f"{data.get('notes', '')} "
                    f"[pass threshold={verifier_pass_threshold:.2f}]"
                ).strip(),
            )
        except Exception as e:
            logger.warning("Peer review failed; rejecting proof conservatively: %s", e)
            return VerificationResult(
                lemma_id=attempt.lemma_id,
                passed=False,
                method="llm_check",
                confidence=attempt.confidence,
                errors=attempt.gaps or ["Peer review unavailable"],
                notes=f"Verification failed conservatively because peer review was unavailable: {e}",
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
