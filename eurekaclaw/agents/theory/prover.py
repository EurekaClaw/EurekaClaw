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

After the proof body, you MUST append a self-assessment block in this exact format:
```json
{
  "confidence": <float 0.0-1.0>,
  "completeness": "<complete|partial|sketch>",
  "gaps": ["<description of each uncertain or unverified step>"],
  "weakest_step": "<the single step you are least sure about, or empty string>",
  "techniques_used": ["<mathematical technique names>"]
}
```

Confidence calibration guide:
- 0.95+  : every step is elementary or follows from a named theorem; no hand-waving at all
- 0.80-0.94 : all key steps are present; at most one routine calculation left implicit
- 0.60-0.79 : proof sketch is correct but one non-trivial step is not fully worked out
- 0.40-0.59 : main idea is right but there is a genuine gap flagged with [GAP: ...]
- below 0.40 : proof is incomplete or the approach may be wrong

Be conservative. Overconfident proofs that are wrong waste iterations.
"""

PROVE_USER = """\
Prove the following lemma:

Lemma ID: {lemma_id}
Statement: {statement}
Informal: {informal}

Already proven lemmas you may cite (by their ID in square brackets, e.g. [lemma_id]):
{proven_lemmas}

Dependencies for this lemma:
{dependencies}
{past_context}
Provide a complete, rigorous proof. Use LaTeX notation.
Start with the proof strategy, then give the detailed proof steps.
If this requires techniques from a specific area (e.g., concentration inequalities,
measure theory), state which techniques you're using.
End with the ```json self-assessment block as instructed.
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
        past_failures: list[str] | None = None,
        cross_session_hint: str | None = None,
        skill_context: str = "",
    ) -> ProofAttempt:
        """Attempt to prove lemma_id given the current state.

        Args:
            state: current TheoryState
            lemma_id: which lemma to prove
            past_failures: failure reasons from earlier iterations of this session
            cross_session_hint: proof approach from a prior session (persistent memory)
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

        # Build past context block (memory injection)
        past_parts: list[str] = []
        if past_failures:
            fails_text = "\n".join(f"  - {r[:120]}" for r in past_failures[:3])
            past_parts.append(
                f"\nPREVIOUS FAILED APPROACHES (avoid repeating these):\n{fails_text}"
            )
        if cross_session_hint:
            past_parts.append(
                f"\nCROSS-SESSION HINT (approach that worked in a prior session):\n"
                f"  {cross_session_hint[:200]}"
            )
        past_context = "\n".join(past_parts)

        try:
            response = await self.client.messages.create(
                model=settings.active_model,
                max_tokens=settings.max_tokens_prover,
                system=system,
                messages=[{
                    "role": "user",
                    "content": PROVE_USER.format(
                        lemma_id=lemma_id,
                        statement=node.statement,
                        informal=node.informal,
                        proven_lemmas=proven_summary,
                        dependencies=deps_summary,
                        past_context=past_context,
                    ),
                }],
            )
            if not response.content:
                raise ValueError("LLM returned empty content list")
            text = response.content[0].text
            return self._parse_proof_attempt(
                lemma_id, text, proven_lemma_ids=set(state.proven_lemmas.keys())
            )

        except Exception as e:
            logger.warning("Proof attempt failed for %s: %s", lemma_id, e)
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

        Include only the minimal information needed (lemma ID + statement),
        not the full proof.
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

    def _parse_proof_attempt(
        self, lemma_id: str, text: str, proven_lemma_ids: set[str] | None = None
    ) -> ProofAttempt:
        """Parse the LLM proof text into a ProofAttempt.

        Priority order for confidence:
        1. Structured ```json self-assessment block emitted by the LLM
        2. Heuristic fallback (QED signals, gap count, proof length)

        Also runs a citation-integrity check: if the proof cites a lemma ID
        that is not in proven_lemma_ids, confidence is penalised.
        """
        import json
        import re

        # ── Step 1: extract any inline [GAP: ...] tags ────────────────────────
        gap_matches = re.findall(r"\[GAP:\s*([^\]]+)\]", text, re.IGNORECASE)
        gaps: list[str] = list(gap_matches)

        # ── Step 2: parse the structured self-assessment block ─────────────────
        confidence: float | None = None
        sa_block_match = re.search(
            r"```json\s*(\{[\s\S]*?\})\s*```", text
        )
        if sa_block_match:
            try:
                sa = json.loads(sa_block_match.group(1))
                confidence = float(sa.get("confidence", -1))
                if confidence < 0 or confidence > 1:
                    confidence = None
                # Merge any gaps from the structured block with inline tags
                sa_gaps = [str(g) for g in sa.get("gaps", []) if g]
                for g in sa_gaps:
                    if g not in gaps:
                        gaps.append(g)
                weakest = sa.get("weakest_step", "")
                if weakest and weakest not in gaps:
                    gaps.append(f"weakest step: {weakest}")
            except (json.JSONDecodeError, ValueError, TypeError):
                pass

        # ── Step 3: heuristic fallback if no valid structured block ────────────
        if confidence is None:
            has_qed = any(
                kw in text.lower()
                for kw in ("qed", "□", "\\qed", "this completes", "as desired")
            )
            if has_qed and not gaps:
                confidence = 0.8
                if "therefore" in text.lower() and len(text) > 500:
                    confidence = 0.9
            elif has_qed:
                confidence = 0.5
            else:
                confidence = 0.3
            logger.debug(
                "Prover: no structured self-assessment found for %s — "
                "using heuristic confidence %.2f", lemma_id, confidence
            )

        # ── Step 4: citation-integrity check ─────────────────────────────────
        # Penalise citations to lemmas that haven't been proved yet.
        if proven_lemma_ids is not None:
            cited_ids = set(re.findall(r"\[([a-zA-Z_][a-zA-Z0-9_]*)\]", text))
            # Only check IDs that look like snake_case lemma names, not
            # LaTeX constructs like [\sigma] or [n].
            uncited = {
                cid for cid in cited_ids
                if "_" in cid and cid not in proven_lemma_ids
            }
            if uncited:
                penalty = min(0.15 * len(uncited), 0.30)
                old_conf = confidence
                confidence = max(0.0, confidence - penalty)
                gaps.append(
                    f"Cites unproven lemma(s) {sorted(uncited)} — "
                    f"confidence penalised {old_conf:.2f}→{confidence:.2f}"
                )
                logger.warning(
                    "Prover: lemma %s cites unproven id(s) %s — "
                    "confidence %.2f→%.2f",
                    lemma_id, sorted(uncited), old_conf, confidence,
                )

        # ── Step 5: weasel-word penalty ───────────────────────────────────────
        weasel_count = sum(
            text.lower().count(w)
            for w in ("clearly", "obviously", "it is easy to see",
                      "it follows trivially", "by inspection")
        )
        if weasel_count >= 3:
            penalty = min(0.05 * weasel_count, 0.15)
            confidence = max(0.0, confidence - penalty)
            logger.debug(
                "Prover: %d weasel phrase(s) in %s — confidence penalised by %.2f",
                weasel_count, lemma_id, penalty,
            )

        # ── Step 6: extract Lean4 sketch ──────────────────────────────────────
        lean4_sketch = ""
        if "```lean" in text.lower():
            start_marker = text.lower().index("```lean")
            try:
                end_marker = text.index("```", start_marker + 7)
                lean4_sketch = text[start_marker + 7:end_marker].strip()
            except ValueError:
                pass

        # Strip the self-assessment JSON block from the stored proof text
        # so downstream stages don't see it as part of the proof body.
        proof_text = text
        if sa_block_match:
            proof_text = (
                text[: sa_block_match.start()].rstrip()
                + text[sa_block_match.end():]
            ).strip()

        success = len(gaps) == 0 and confidence >= 0.5

        return ProofAttempt(
            lemma_id=lemma_id,
            proof_text=proof_text,
            lean4_sketch=lean4_sketch,
            confidence=confidence,
            gaps=gaps,
            success=success,
        )
