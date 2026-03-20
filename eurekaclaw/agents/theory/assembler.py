"""Assembler — Stage 5 of the bottom-up proof pipeline.

Takes all proven lemmas (newly proved + citation-only known results)
and weaves them into a single coherent proof narrative.

The output (state.assembled_proof) is the raw material for
TheoremCrystallizer (Stage 6), which will read it to derive the
exact formal theorem statement.
"""

from __future__ import annotations

import logging

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

ASSEMBLE_SYSTEM = """\
You are a mathematical writer assembling a rigorous research paper proof.
You have been given:
1. A proof skeleton describing the overall argument
2. A set of known lemmas (cited from existing papers, no reproving needed)
3. A set of newly proved lemmas (with full proof texts, possibly empty)

Your task is to write a complete, self-contained proof that:
- Uses the proof skeleton as the primary organizing structure when it is available
- Cites known results by paper and theorem number (use the source information)
- Presents adapted and new results with their full proofs
- Flows logically from base lemmas to the main result
- Uses consistent notation throughout
- Is written at the level of a top ML theory conference paper

Citation rule: whenever you use a proved lemma, cite it by its identifier
in square brackets, e.g. "By [arm_pull_count_bound], we have..." or
"Applying [regret_decomposition] gives...".  Every proved lemma that
appears in the logical chain MUST be cited at least once by its id.

Do NOT state the main theorem yet.  Just write the proof body.
The theorem statement will be extracted after from the proof itself.
"""

ASSEMBLE_USER = """\
Research gap being addressed:
{research_gap}

Known results (to be cited, not reproved):
{known_citations}

Newly proved lemmas (in proof order):
{proved_lemmas}

Proof skeleton:
{proof_skeleton}

Write the complete assembled proof.  Use LaTeX notation.
Begin with a proof overview paragraph. If the proof skeleton is substantive, follow it
as the main spine of the argument, inserting lemma proofs only where they are actually needed.
"""


class Assembler:
    """Stage 5: assemble proven lemmas into a coherent proof narrative."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Populate state.assembled_proof."""
        known_citations = self._format_known_citations(state)
        proved_lemmas = self._format_proved_lemmas(state)
        lemma_ids = ", ".join(f"[{lid}]" for lid in state.proven_lemmas) or "(none)"

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=6000,
                system=ASSEMBLE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": ASSEMBLE_USER.format(
                        research_gap=state.research_gap[:800],
                        known_citations=known_citations,
                        proved_lemmas=proved_lemmas,
                        proof_skeleton=state.proof_skeleton[:1600] or "(none)",
                    ),
                }],
            )
            state.assembled_proof = response.content[0].text.strip()
            logger.info("Assembler: assembled proof (%d chars)", len(state.assembled_proof))
        except Exception as e:
            logger.exception("Assembler failed: %s", e)
            # Fallback: prefer the proof skeleton, then append raw proofs if any exist.
            parts = []
            if state.proof_skeleton:
                parts.append("=== Proof Skeleton ===\n" + state.proof_skeleton)
            parts.extend(
                f"=== {lid} ===\n{rec.proof_text}"
                for lid, rec in state.proven_lemmas.items()
            )
            state.assembled_proof = "\n\n".join(parts) or state.research_gap

        return state

    def _format_known_citations(self, state: TheoryState) -> str:
        """List known lemmas that are cited but not proved here."""
        known_ids = {
            pp.lemma_id
            for pp in state.proof_plan
            if pp.provenance == "known"
        }
        if not known_ids:
            return "(none — all results are new)"
        lines = []
        for pp in state.proof_plan:
            if pp.provenance != "known":
                continue
            lines.append(
                f"[{pp.lemma_id}] {pp.statement}\n"
                f"  → Cite: {pp.source or 'see references'}"
            )
        return "\n".join(lines)

    def _format_proved_lemmas(self, state: TheoryState) -> str:
        """Format all lemmas that were actually proved (adapted + new)."""
        if not state.proven_lemmas:
            return "(no lemmas proved yet)"
        # Follow proof_plan order where possible
        plan_order = [pp.lemma_id for pp in state.proof_plan]
        ordered_ids = [lid for lid in plan_order if lid in state.proven_lemmas]
        # Append any not in the plan (shouldn't happen, but be safe)
        ordered_ids += [lid for lid in state.proven_lemmas if lid not in ordered_ids]

        parts = []
        for lid in ordered_ids:
            rec = state.proven_lemmas[lid]
            node = state.lemma_dag.get(lid)
            statement = node.statement if node else lid
            # Compress very long proofs: keep head + tail
            proof_text = rec.proof_text
            if len(proof_text) > 2000:
                proof_text = proof_text[:1000] + "\n... [abbreviated] ...\n" + proof_text[-600:]
            parts.append(
                f"--- Lemma: {lid} ---\n"
                f"Statement: {statement}\n"
                f"Proof:\n{proof_text}\n"
                f"(verified: {rec.verified}, method: {rec.verification_method})"
            )
        return "\n\n".join(parts)
