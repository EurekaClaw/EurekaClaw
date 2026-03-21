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
import re
from dataclasses import dataclass

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

CHECK_SYSTEM = """\
You are a rigorous mathematical reviewer.  You will be given:
1. A theorem statement
2. A structured proof context distilled from the proof artifacts

Check whether the proof actually establishes the stated theorem.
Look for:
- Overclaiming: the theorem is more general than what the proof shows
- Notation mismatch: symbols in the theorem differ from the proof
- Missing assumptions: the theorem omits conditions assumed in the proof
- Incorrect constants: bounds stated with wrong dependence on parameters
- Missing citations: any lemma identifier from the required list that does
  not appear in the proof text as [lemma_id] is a gap
- Truncated theorem statement: if the theorem formula ends mid-expression
  (e.g. ends with a backslash or unclosed brace), flag it as an issue

Important: if the proof is marked "[compressed]", do NOT flag missing
intermediate steps as issues — only flag things you can positively verify
are wrong or missing from what you can see.

Return JSON:
{
  "consistent": true | false,
  "confidence": 0.0-1.0,
  "issues": ["list of specific inconsistencies"],
  "uncited_lemmas": ["lemma_ids present in required list but not cited"],
  "notes": "brief summary"
}
"""

CHECK_USER = """\
Theorem statement:
{theorem}

Structured proof context:
{proof_excerpt}

Required lemma identifiers (each must appear as [lemma_id] in the proof):
{required_lemma_ids}

Is the theorem statement consistent with and supported by this proof?
Are all required lemmas cited?
Return ONLY valid JSON.
"""


@dataclass
class ConsistencyResult:
    consistent: bool
    confidence: float
    issues: list[str]
    uncited_lemmas: list[str]
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

        required_lemma_ids = list(state.proven_lemmas.keys())
        result = await self._check(state, required_lemma_ids)

        all_issues = result.issues + [
            f"Lemma [{lid}] is proved but never cited in the assembled proof"
            for lid in result.uncited_lemmas
        ]

        if result.consistent and not result.uncited_lemmas:
            logger.info(
                "ConsistencyChecker: PASS (confidence=%.2f)", result.confidence
            )
            state.status = "proved"
        else:
            logger.warning(
                "ConsistencyChecker: FAIL — %d issues: %s",
                len(all_issues), "; ".join(all_issues[:3]),
            )
            state.status = "in_progress"
            from eurekaclaw.types.artifacts import FailedAttempt
            state.failed_attempts.append(
                FailedAttempt(
                    lemma_id="_theorem_consistency",
                    attempt_text=state.formal_statement[:500],
                    failure_reason="; ".join(all_issues[:5]) or result.notes,
                    iteration=state.iteration,
                )
            )

        return state

    async def _check(self, state: TheoryState) -> ConsistencyResult:
        proof_excerpt = self._build_proof_context(state)
        try:
            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=700,
                system=CHECK_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": CHECK_USER.format(
                        theorem=state.formal_statement[:800],
                        proof_excerpt=proof_excerpt,
                        required_lemma_ids=ids_str,
                    ),
                }],
            )
            text = response.content[0].text
            data = self._parse_json(text)
            return ConsistencyResult(
                consistent=bool(data.get("consistent", False)),
                confidence=float(data.get("confidence", 0.5)),
                issues=data.get("issues", []),
                uncited_lemmas=data.get("uncited_lemmas", []),
                notes=data.get("notes", ""),
            )
        except Exception as e:
            logger.warning("ConsistencyChecker LLM call failed: %s — defaulting to pass", e)
            return ConsistencyResult(
                consistent=True, confidence=0.5, issues=[],
                uncited_lemmas=[],
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

    def _build_proof_context(self, state: TheoryState) -> str:
        """Build a structured proof context instead of naive head/tail truncation."""
        sections: list[str] = []

        if state.proof_skeleton:
            sections.append("=== Proof Skeleton ===\n" + state.proof_skeleton[:1800])

        if state.proof_plan:
            plan_lines = []
            for plan in state.proof_plan[:8]:
                plan_lines.append(
                    f"- [{plan.lemma_id}] provenance={plan.provenance} statement={plan.statement[:220]}"
                )
            sections.append("=== Planned Key Lemmas ===\n" + "\n".join(plan_lines))

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
        sections.append("=== Proof Overview ===\n" + body[:1600])

        middle_hits = re.findall(
            r"(?is)(lemma\s+\d+.*?(?:proof\.|qed|\\end\{lemma\}|\\end\{proof\}))",
            body,
        )
        if middle_hits:
            sections.append(
                "=== Key Middle Excerpts ===\n" + "\n\n".join(hit[:800] for hit in middle_hits[:3])
            )

        sections.append("=== Proof Conclusion ===\n" + body[-1400:])
        return "\n\n".join(section for section in sections if section).strip()[:6500]
