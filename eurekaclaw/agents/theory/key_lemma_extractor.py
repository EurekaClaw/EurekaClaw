"""KeyLemmaExtractor — extract only the genuinely hard lemmas from a proof skeleton."""

from __future__ import annotations

import json
import logging
import uuid

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import LemmaNode, ProofPlan, TheoryState

logger = logging.getLogger(__name__)

EXTRACTOR_SYSTEM = """\
You are an expert proof planner for mathematical research.

You are given:
- a research gap
- known results from the literature
- reusable prior theorems/lemmas from memory
- a proof template
- a proof skeleton

Your task is NOT to force a large lemma DAG.
Instead, extract only the genuinely nontrivial steps that must become separate lemmas.

Rules:
- It is valid to return zero lemmas if the proof skeleton can be written as a continuous argument.
- Prefer 0-3 technical lemmas unless more are clearly necessary.
- Use provenance:
  - "known" for directly citable results
  - "adapted" for memory/literature results needing modification
  - "new" for genuinely new technical steps
- Do not create fake bookkeeping lemmas.
- If no independent lemma is needed, return an empty list.

Return ONLY valid JSON:
{
  "lemmas": [
    {
      "id": "short_snake_case",
      "statement": "LaTeX statement",
      "informal": "brief explanation",
      "provenance": "known|adapted|new",
      "source": "paper or memory theorem if applicable",
      "adaptation_note": "what changes if adapted",
      "dependencies": ["lemma_id"]
    }
  ]
}
"""

EXTRACTOR_USER = """\
Research gap:
{research_gap}

Known results:
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
"""


class KeyLemmaExtractor:
    """Extract only the key technical lemmas implied by the proof skeleton."""

    _LEMMA_KEYS = ("lemmas", "plan", "proof_plan", "lemma_list", "components", "parts")

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        known_summary = self._format_known(state)
        memory_theorems = "\n".join(state.memory_theorems[:5]) or "(none)"

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=2200,
                system=EXTRACTOR_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": EXTRACTOR_USER.format(
                        research_gap=state.research_gap[:1200],
                        known_results=known_summary,
                        memory_theorems=memory_theorems,
                        problem_type=state.problem_type[:200] or "(unspecified)",
                        proof_template=state.proof_template[:200] or "(unspecified)",
                        analysis_notes=state.analysis_notes[:1600] or "(none)",
                        proof_skeleton=state.proof_skeleton[:2200] or "(none)",
                    ),
                }],
            )
            text = response.content[0].text if response.content else "{}"
            lemmas_data = self._parse_lemmas(text)
            state = self._apply_plan(state, lemmas_data)
            logger.info(
                "KeyLemmaExtractor: extracted %d lemma(s) (%d open goals)",
                len(state.proof_plan),
                len(state.open_goals),
            )
        except Exception as exc:
            logger.exception("KeyLemmaExtractor failed: %s", exc)
            # Conservative fallback for the memory-guided route:
            # preserve the proof skeleton and proceed without independent lemmas.
            state.proof_plan = []
            state.lemma_dag = {}
            state.open_goals = []

        return state

    def _format_known(self, state: TheoryState) -> str:
        if not state.known_results:
            return "(none)"
        lines = []
        for kr in state.known_results[:10]:
            lines.append(
                f"• [{kr.result_type}] {kr.statement[:150]}"
                f"\n  informal: {kr.informal}"
                f"\n  technique: {kr.proof_technique}"
                f"\n  source: {kr.source_paper_title[:60]} (id: {kr.source_paper_id})"
            )
        return "\n\n".join(lines)

    def _parse_lemmas(self, text: str) -> list[dict]:
        import re

        m = re.search(r"```(?:json)?\s*(\{[\s\S]*?\}|\[[\s\S]*?\])\s*```", text)
        if m:
            result = self._try_parse_json(m.group(1))
            if result is not None:
                return result

        m = re.search(r"\{[\s\S]*\}", text)
        if m:
            result = self._try_parse_json(m.group(0))
            if result is not None:
                return result

        m = re.search(r"\[[\s\S]*\]", text)
        if m:
            try:
                data = json.loads(m.group(0))
                if isinstance(data, list):
                    return data
            except (json.JSONDecodeError, ValueError):
                pass

        return []

    def _try_parse_json(self, candidate: str) -> list[dict] | None:
        try:
            data = json.loads(candidate)
        except (json.JSONDecodeError, ValueError):
            return None
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in self._LEMMA_KEYS:
                if key in data and isinstance(data[key], list):
                    return data[key]
        return None

    def _apply_plan(self, state: TheoryState, lemmas_data: list[dict]) -> TheoryState:
        plan: list[ProofPlan] = []
        state.lemma_dag = {}

        for item in lemmas_data:
            lemma_id = self._coerce_string(item.get("id")) or str(uuid.uuid4())[:8]
            provenance = self._coerce_string(item.get("provenance")) or "new"
            if provenance not in ("known", "adapted", "new"):
                provenance = "new"
            proof_plan = ProofPlan(
                lemma_id=lemma_id,
                statement=self._coerce_string(item.get("statement")),
                informal=self._coerce_string(item.get("informal")),
                provenance=provenance,
                source=self._coerce_string(item.get("source")),
                adaptation_note=self._coerce_string(item.get("adaptation_note")),
                dependencies=self._coerce_dependencies(item.get("dependencies")),
            )
            plan.append(proof_plan)
            state.lemma_dag[lemma_id] = LemmaNode(
                lemma_id=lemma_id,
                statement=proof_plan.statement,
                informal=proof_plan.informal,
                dependencies=proof_plan.dependencies,
            )

        state.proof_plan = plan
        needs_proof = {pp.lemma_id for pp in plan if pp.provenance in ("adapted", "new")}
        topo = self._topological_sort(state.lemma_dag)
        state.open_goals = [lid for lid in topo if lid in needs_proof and lid not in state.proven_lemmas]
        return state

    def _topological_sort(self, dag: dict[str, LemmaNode]) -> list[str]:
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
        return order if len(order) == len(dag) else list(dag.keys())

    def _coerce_string(self, value: object) -> str:
        if value is None:
            return ""
        if isinstance(value, str):
            return value
        return str(value)

    def _coerce_dependencies(self, value: object) -> list[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [self._coerce_string(item).strip() for item in value if self._coerce_string(item).strip()]
        text = self._coerce_string(value).strip()
        return [text] if text else []
