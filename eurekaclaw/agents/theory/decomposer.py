"""LemmaDecomposer — breaks a target theorem into a DAG of sub-goals using networkx."""

from __future__ import annotations

import json
import logging
import uuid
from typing import TYPE_CHECKING

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.types.artifacts import LemmaNode, TheoryState

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

DECOMPOSE_SYSTEM = """\
You are an expert mathematical proof planner. Given a theorem, your task is to decompose it \
into the minimal set of lemmas that together imply the theorem.

For each lemma, specify:
- A short unique ID (snake_case)
- The precise formal statement
- The informal intuition
- Which other lemmas it depends on (by ID)

Output as a JSON dependency graph. Lemmas with no dependencies form the "base" of the proof.
The final lemma should be the theorem itself, citing all its required sub-lemmas.
"""

DECOMPOSE_USER = """\
Decompose this theorem into a minimal set of lemmas:

Theorem: {formal_statement}
Informal: {informal_statement}
Known context: {context}

Return JSON: {{"lemmas": [{{"id": "...", "statement": "...", "informal": "...", "dependencies": [...]}}]}}

Requirements:
- 3-8 lemmas total (including the main theorem at the end)
- Each lemma should be self-contained and independently provable
- Dependency ordering must be a valid DAG (no cycles)
- The last lemma's statement should be (or imply) the main theorem
"""


class LemmaDecomposer:
    """Step 2 of the Theory Agent inner loop: theorem → lemma DAG."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState) -> TheoryState:
        """Build the lemma DAG for the current formal statement."""
        if state.lemma_dag and state.iteration == 0:
            logger.debug("Lemma DAG already built")
            return state

        try:
            context = ", ".join(k for k in state.proven_lemmas.keys()) if state.proven_lemmas else "none"
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=3000,
                system=DECOMPOSE_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": DECOMPOSE_USER.format(
                        formal_statement=state.formal_statement,
                        informal_statement=state.informal_statement,
                        context=context,
                    ),
                }],
            )
            text = response.content[0].text
            lemmas_data = self._parse_lemmas(text)
            state = self._build_dag(state, lemmas_data)
            logger.info("Decomposed into %d lemmas", len(state.lemma_dag))

        except Exception as e:
            logger.exception("Lemma decomposition failed: %s", e)
            # Fallback: single lemma = the theorem itself
            lemma_id = "main_theorem"
            state.lemma_dag[lemma_id] = LemmaNode(
                lemma_id=lemma_id,
                statement=state.formal_statement,
                informal=state.informal_statement,
                dependencies=[],
            )
            state.open_goals = [lemma_id]

        return state

    def _parse_lemmas(self, text: str) -> list[dict]:
        for delim_start, delim_end in [("```json", "```"), ("{", None)]:
            try:
                if delim_start in text:
                    start = text.index(delim_start) + len(delim_start)
                    if delim_end:
                        end = text.index(delim_end, start)
                        data = json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        data = json.loads(text[text.index("{"):end])
                    if isinstance(data, dict) and "lemmas" in data:
                        return data["lemmas"]
                    if isinstance(data, list):
                        return data
            except (json.JSONDecodeError, ValueError):
                continue
        return []

    def _build_dag(self, state: TheoryState, lemmas_data: list[dict]) -> TheoryState:
        """Populate state.lemma_dag and state.open_goals from parsed lemma data."""
        for item in lemmas_data:
            lemma_id = item.get("id") or str(uuid.uuid4())[:8]
            node = LemmaNode(
                lemma_id=lemma_id,
                statement=item.get("statement", ""),
                informal=item.get("informal", ""),
                dependencies=item.get("dependencies", []),
            )
            state.lemma_dag[lemma_id] = node

        # Build open_goals as topological order excluding already-proven lemmas
        state.open_goals = [
            lid for lid in self._topological_sort(state.lemma_dag)
            if lid not in state.proven_lemmas
        ]
        return state

    def _topological_sort(self, dag: dict[str, LemmaNode]) -> list[str]:
        """Kahn's algorithm for topological sort of the lemma DAG."""
        in_degree = {lid: 0 for lid in dag}
        for node in dag.values():
            for dep in node.dependencies:
                if dep in in_degree:
                    in_degree[dep] = in_degree.get(dep, 0)  # dep exists
                    in_degree[node.lemma_id] = in_degree.get(node.lemma_id, 0)

        # Rebuild in-degree correctly
        in_degree = {lid: 0 for lid in dag}
        for node in dag.values():
            for dep in node.dependencies:
                if dep in dag:
                    in_degree[node.lemma_id] += 1
                    # wait — this is wrong; in_degree should count dependencies
        # Correct: in_degree[v] = number of dependencies of v that are in the dag
        in_degree = {lid: len([d for d in node.dependencies if d in dag])
                     for lid, node in dag.items()}

        queue = [lid for lid, deg in in_degree.items() if deg == 0]
        order = []
        while queue:
            node_id = queue.pop(0)
            order.append(node_id)
            # Find nodes that depended on node_id
            for lid, node in dag.items():
                if node_id in node.dependencies:
                    in_degree[lid] -= 1
                    if in_degree[lid] == 0:
                        queue.append(lid)
        # If cycle, return remaining nodes
        remaining = [lid for lid in dag if lid not in order]
        return order + remaining
