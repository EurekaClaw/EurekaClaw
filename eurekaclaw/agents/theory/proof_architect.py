"""ProofArchitect — Stage 3 of the bottom-up proof pipeline.

Replaces LemmaDecomposer.  Given the research gap and the set of known
results, plans a proof structure where each lemma is annotated with its
provenance:

  "known"   — directly citable from an existing paper, no new proof needed
  "adapted" — a known result that needs minor modification
  "new"     — genuinely new, must be proved from scratch

This provenance information is what allows the LemmaDeveloper (Stage 4)
to skip citation-only lemmas and focus proof effort only on what is
actually new.
"""

from __future__ import annotations

import json
import logging
import uuid

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import LemmaNode, ProofPlan, TheoryState

logger = logging.getLogger(__name__)

ARCHITECT_SYSTEM = """\
You are an expert proof architect for theoretical machine learning papers.
Given a research gap description and a set of known results from the
literature, your task is to design a proof plan.

A proof plan is an ordered list of lemmas that together establish the
main result.  For each lemma you must specify:
- "id": short snake_case identifier
- "statement": the mathematical statement (LaTeX)
- "informal": one-sentence plain description
- "provenance": one of:
    "known"   — directly citable, no new proof needed
    "adapted" — extends or modifies a known result
    "new"     — genuinely novel, must be fully proved
- "source": if known/adapted, which paper or result it comes from
- "adaptation_note": if adapted, what changes relative to the source
- "dependencies": list of lemma ids this lemma depends on

Rules:
- Order lemmas topologically (dependencies before dependents)
- For general proof plans, 4-10 lemmas is typical.
- When a proof skeleton or decomposition is already available, do NOT force a
  large lemma DAG. A compact plan with only the genuinely nontrivial bottleneck
  lemmas plus the final result is preferred.
- Known lemmas should use results from the provided known-results list
- Adapted/new lemmas should identify exactly what is novel
- The final lemma should be the main result (provenance "new")
- Do NOT write the main theorem statement yet — that comes after the proof

Return JSON: {"lemmas": [...]}
"""

ARCHITECT_USER = """\
Research gap:
{research_gap}

Available known results (cite these where possible):
{known_results}

Relevant prior theorems / lemmas from memory:
{memory_theorems}

Problem type:
{problem_type}

Preferred proof template:
{proof_template}

Analysis notes:
{analysis_notes}

Proof skeleton:
{proof_skeleton}

Design a proof plan for the above gap.
Return ONLY valid JSON with a "lemmas" array.
"""


class ProofArchitect:
    """Stage 3: plan a provenance-annotated proof structure."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Populate state.proof_plan and state.lemma_dag / state.open_goals."""
        if not state.research_gap:
            logger.warning("ProofArchitect: no research_gap set — falling back to informal statement")
            state.research_gap = state.informal_statement

        known_summary = self._format_known(state)

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=3000,
                system=ARCHITECT_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": ARCHITECT_USER.format(
                        research_gap=state.research_gap[:1200],
                        known_results=known_summary,
                        memory_theorems="\n".join(state.memory_theorems[:5]) or "(none)",
                        problem_type=state.problem_type[:200] or "(unspecified)",
                        proof_template=state.proof_template[:200] or "(unspecified)",
                        analysis_notes=state.analysis_notes[:1600] or "(none)",
                        proof_skeleton=state.proof_skeleton[:1600] or "(none)",
                    ),
                }],
            )
            text = response.content[0].text
            lemmas_data = self._parse_lemmas(text)
            if lemmas_data:
                state = self._apply_plan(state, lemmas_data)
                logger.info(
                    "ProofArchitect: plan with %d lemmas (%d known, %d adapted, %d new)",
                    len(state.proof_plan),
                    sum(1 for p in state.proof_plan if p.provenance == "known"),
                    sum(1 for p in state.proof_plan if p.provenance == "adapted"),
                    sum(1 for p in state.proof_plan if p.provenance == "new"),
                )
            else:
                raise ValueError("Parsed zero lemmas from architect response")

        except Exception as e:
            logger.exception("ProofArchitect failed: %s", e)
            # Fallback: single new lemma representing the whole gap
            fallback_id = "main_result"
            state.proof_plan = [
                ProofPlan(
                    lemma_id=fallback_id,
                    statement=state.research_gap[:300],
                    informal=state.informal_statement,
                    provenance="new",
                    dependencies=[],
                )
            ]
            state.lemma_dag[fallback_id] = LemmaNode(
                lemma_id=fallback_id,
                statement=state.research_gap[:300],
                informal=state.informal_statement,
                dependencies=[],
            )
            state.open_goals = [fallback_id]

        return state

    # ------------------------------------------------------------------

    def _format_known(self, state: TheoryState) -> str:
        if not state.known_results:
            return "(none)"
        lines = []
        for kr in state.known_results:
            lines.append(
                f"• [{kr.result_type}] {kr.statement[:150]}"
                f"\n  informal: {kr.informal}"
                f"\n  technique: {kr.proof_technique}"
                f"\n  source: {kr.source_paper_title[:60]} (id: {kr.source_paper_id})"
            )
        return "\n\n".join(lines)

    # Keys the LLM may use for the lemma list in its JSON response
    _LEMMA_KEYS = ("lemmas", "plan", "proof_plan", "steps", "lemma_list",
                   "subgoals", "components", "parts")

    def _parse_lemmas(self, text: str) -> list[dict]:
        """4-pass extraction — mirrors LemmaDecomposer._parse_lemmas for robustness."""
        import re

        # Pass 1: JSON inside a ```json ... ``` or ``` ... ``` code fence
        m = re.search(r"```(?:json)?\s*(\{[\s\S]*?\}|\[[\s\S]*?\])\s*```", text)
        if m:
            result = self._try_parse_json(m.group(1))
            if result is not None:
                return result

        # Pass 2: first JSON object {...} in the text — check known key names
        m = re.search(r"\{[\s\S]*\}", text)
        if m:
            result = self._try_parse_json(m.group(0))
            if result is not None:
                return result

        # Pass 3: first JSON array [...] in the text
        m = re.search(r"\[[\s\S]*\]", text)
        if m:
            try:
                data = json.loads(m.group(0))
                if isinstance(data, list) and data:
                    return data
            except (json.JSONDecodeError, ValueError):
                pass

        # Pass 4: plain-text numbered / bulleted list heuristic
        items = re.findall(
            r"(?m)^(?:\d+[\.\)]\s*|\*\s*|-\s*)(.+)", text
        )
        if items:
            return [{"id": f"lemma_{i+1}", "statement": item.strip(),
                     "informal": item.strip(), "provenance": "new",
                     "dependencies": []}
                    for i, item in enumerate(items)]

        return []

    def _try_parse_json(self, candidate: str) -> list[dict] | None:
        """Parse a JSON string and extract the lemma list if present."""
        try:
            data = json.loads(candidate)
        except (json.JSONDecodeError, ValueError):
            return None
        if isinstance(data, list) and data:
            return data
        if isinstance(data, dict):
            for key in self._LEMMA_KEYS:
                if key in data and isinstance(data[key], list) and data[key]:
                    return data[key]
        return None


    def _apply_plan(self, state: TheoryState, lemmas_data: list[dict]) -> TheoryState:
        """Populate proof_plan, lemma_dag, and open_goals from parsed data."""
        plan: list[ProofPlan] = []
        for item in lemmas_data:
            lemma_id = item.get("id") or str(uuid.uuid4())[:8]
            provenance = item.get("provenance", "new")
            if provenance not in ("known", "adapted", "new"):
                provenance = "new"
            plan.append(
                ProofPlan(
                    lemma_id=lemma_id,
                    statement=item.get("statement", ""),
                    informal=item.get("informal", ""),
                    provenance=provenance,
                    source=item.get("source", ""),
                    adaptation_note=item.get("adaptation_note") or "",
                    dependencies=item.get("dependencies", []),
                )
            )

        state.proof_plan = plan

        # Build lemma_dag for all lemmas (LemmaDeveloper needs it)
        state.lemma_dag = {}
        for pp in plan:
            state.lemma_dag[pp.lemma_id] = LemmaNode(
                lemma_id=pp.lemma_id,
                statement=pp.statement,
                informal=pp.informal,
                dependencies=pp.dependencies,
            )

        # open_goals = only lemmas that need actual proof work (adapted or new),
        # in topological order excluding already-proven lemmas
        needs_proof = {pp.lemma_id for pp in plan if pp.provenance in ("adapted", "new")}
        state.open_goals = [
            lid for lid in self._topological_sort(state.lemma_dag)
            if lid in needs_proof and lid not in state.proven_lemmas
        ]
        return state

    def _topological_sort(self, dag: dict[str, LemmaNode]) -> list[str]:
        """Kahn's algorithm."""
        in_degree = {
            lid: len([d for d in node.dependencies if d in dag])
            for lid, node in dag.items()
        }
        queue = [lid for lid, deg in in_degree.items() if deg == 0]
        order: list[str] = []
        while queue:
            node_id = queue.pop(0)
            order.append(node_id)
            for lid, node in dag.items():
                if node_id in node.dependencies:
                    in_degree[lid] -= 1
                    if in_degree[lid] == 0:
                        queue.append(lid)
        remaining = [lid for lid in dag if lid not in order]
        return order + remaining
