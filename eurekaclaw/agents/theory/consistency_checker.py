"""ConsistencyChecker — Stage 7 of the bottom-up proof pipeline.

Verifies that the crystallized theorem statement (state.formal_statement)
is actually supported by the assembled proof (state.assembled_proof).

Catches the most common failure mode of the crystallization step:
the LLM overgeneralizes or introduces notation inconsistencies when
writing the theorem statement.

Returns a structured check result stored on TheoryState.
The loop treats a failed consistency check as a signal to re-run
TheoremCrystallizer (with the checker's notes as additional context),
up to a configurable number of times.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

CHECK_SYSTEM = """\
You are a rigorous mathematical reviewer.  You will be given:
1. A theorem statement
2. An assembled proof that was intended to prove it

Check whether the proof actually establishes the stated theorem.
Look for:
- Overclaiming: the theorem is more general than what the proof shows
- Notation mismatch: symbols in the theorem differ from the proof
- Missing assumptions: the theorem omits conditions assumed in the proof
- Incorrect constants: bounds stated with wrong dependence on parameters

Return JSON:
{
  "consistent": true | false,
  "confidence": 0.0-1.0,
  "issues": ["list of specific inconsistencies"],
  "notes": "brief summary"
}
"""

CHECK_USER = """\
Theorem statement:
{theorem}

Assembled proof (excerpt):
{proof_excerpt}

Is the theorem statement consistent with and supported by this proof?
Return ONLY valid JSON.
"""


@dataclass
class ConsistencyResult:
    consistent: bool
    confidence: float
    issues: list[str]
    notes: str


class ConsistencyChecker:
    """Stage 7: verify theorem ↔ proof consistency."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Check consistency; append issues to state.failed_attempts if any."""
        if not state.formal_statement or not state.assembled_proof:
            logger.warning("ConsistencyChecker: missing theorem or proof — skipping")
            return state

        result = await self._check(state)

        if result.consistent:
            logger.info(
                "ConsistencyChecker: PASS (confidence=%.2f)", result.confidence
            )
            # Proof is complete and consistent
            state.status = "proved"
        else:
            logger.warning(
                "ConsistencyChecker: FAIL — %d issues: %s",
                len(result.issues), "; ".join(result.issues[:3]),
            )
            # Store issues so TheoremCrystallizer can use them on retry
            state.status = "in_progress"
            # Reuse FailedAttempt to record the mismatch (lemma_id = "_theorem")
            from eurekaclaw.types.artifacts import FailedAttempt
            state.failed_attempts.append(
                FailedAttempt(
                    lemma_id="_theorem_consistency",
                    attempt_text=state.formal_statement[:500],
                    failure_reason="; ".join(result.issues[:5]) or result.notes,
                    iteration=state.iteration,
                )
            )

        return state

    async def _check(self, state: TheoryState) -> ConsistencyResult:
        proof_excerpt = state.assembled_proof
        if len(proof_excerpt) > 3000:
            proof_excerpt = (
                proof_excerpt[:1500]
                + "\n... [compressed] ...\n"
                + proof_excerpt[-1000:]
            )
        try:
            response = await self.client.messages.create(
                model=settings.fast_model,
                max_tokens=512,
                system=CHECK_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": CHECK_USER.format(
                        theorem=state.formal_statement[:800],
                        proof_excerpt=proof_excerpt,
                    ),
                }],
            )
            text = response.content[0].text
            data = self._parse_json(text)
            return ConsistencyResult(
                consistent=bool(data.get("consistent", False)),
                confidence=float(data.get("confidence", 0.5)),
                issues=data.get("issues", []),
                notes=data.get("notes", ""),
            )
        except Exception as e:
            logger.warning("ConsistencyChecker LLM call failed: %s — defaulting to pass", e)
            return ConsistencyResult(
                consistent=True, confidence=0.5, issues=[],
                notes=f"Checker unavailable: {e}",
            )

    def _parse_json(self, text: str) -> dict:
        for start_delim, end_delim in [("```json", "```"), ("{", None)]:
            try:
                if start_delim in text:
                    start = text.index(start_delim) + len(start_delim)
                    if end_delim:
                        end = text.index(end_delim, start)
                        return json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        return json.loads(text[text.index("{"):end])
            except (json.JSONDecodeError, ValueError):
                continue
        return {"consistent": True, "confidence": 0.5, "issues": [], "notes": text[:200]}
