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
    """Step 2 of the Theory Agent inner loop: theorem → lemma DAG.

    Caching: if the formal statement has not changed since the last successful
    decomposition (i.e. no refinement occurred), the existing lemma_dag is
    reused and no LLM call is made.  This saves 1 call per inner-loop iteration
    that does not involve a counterexample-triggered refinement.
    """

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()
        # Cache key: the last formal statement we successfully decomposed.
        self._last_formal: str = ""

    async def run(self, state: TheoryState) -> TheoryState:
        """Build the lemma DAG for the current formal statement.

        Skips the LLM call when:
        - A DAG already exists AND
        - The formal statement has not changed since the last decomposition.
        This avoids redundant re-decomposition across retry iterations that do
        not involve conjecture refinement.
        """
        if state.lemma_dag and state.iteration == 0:
            logger.debug("Lemma DAG already built")
            return state

        # Skip re-decomposition if the conjecture has not changed
        if state.lemma_dag and state.formal_statement == self._last_formal:
            logger.debug(
                "Skipping re-decomposition — formal statement unchanged (iteration %d)",
                state.iteration,
            )
            return state

        try:
            # Limit proven-lemma context to at most 8 keys to save tokens
            context_keys = list(state.proven_lemmas.keys())[-8:]
            context = ", ".join(context_keys) if context_keys else "none"

            response = await self.client.messages.create(
                model=settings.active_model,
                max_tokens=settings.max_tokens_decomposer,
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
            if not response.content:
                raise ValueError("LLM returned empty content list")
            text = response.content[0].text
            lemmas_data = self._parse_lemmas(text)
            if lemmas_data:
                state = self._build_dag(state, lemmas_data)
                self._last_formal = state.formal_statement
                logger.info("Decomposed into %d lemmas", len(state.lemma_dag))
            else:
                # LLM returned parseable JSON but with no lemmas — use single-theorem fallback.
                # This is an expected degraded path, not an error.
                logger.warning(
                    "Decomposer returned no lemmas — using single-theorem fallback"
                )
                state = self._single_theorem_fallback(state)

        except Exception as e:
            logger.exception("Lemma decomposition failed unexpectedly: %s", e)
            state = self._single_theorem_fallback(state)

        return state

    def _single_theorem_fallback(self, state: TheoryState) -> TheoryState:
        """Create a single-node DAG treating the theorem itself as the only lemma."""
        lemma_id = "main_theorem"
        state.lemma_dag[lemma_id] = LemmaNode(
            lemma_id=lemma_id,
            statement=state.formal_statement,
            informal=state.informal_statement,
            dependencies=[],
        )
        state.open_goals = [lemma_id]
        return state

    # Alternative key names the LLM might use instead of "lemmas"
    _LEMMA_KEYS = ("lemmas", "steps", "subgoals", "proof_steps", "lemma_list", "components", "parts")

    def _parse_lemmas(self, text: str) -> list[dict]:
        """Extract a list of lemma dicts from LLM output.

        Tries, in order:
        1. JSON in a ```json ... ``` or ``` ... ``` code fence
        2. Raw JSON object starting with ``{``
        3. Raw JSON array starting with ``[``
        4. Plain-text numbered/bulleted list heuristic
        """
        # --- Pass 1: code fences ---
        import re
        fence_match = re.search(r"```(?:json)?\s*\n?(.*?)```", text, re.DOTALL)
        if fence_match:
            result = self._try_parse_json(fence_match.group(1).strip())
            if result is not None:
                return result

        # --- Pass 2: first JSON object in the text ---
        obj_start = text.find("{")
        if obj_start != -1:
            try:
                obj_end = text.rindex("}") + 1
                result = self._try_parse_json(text[obj_start:obj_end])
                if result is not None:
                    return result
            except ValueError:
                pass

        # --- Pass 3: first JSON array in the text ---
        arr_start = text.find("[")
        if arr_start != -1:
            try:
                arr_end = text.rindex("]") + 1
                candidate = text[arr_start:arr_end]
                data = json.loads(candidate)
                if isinstance(data, list) and data:
                    normalized = self._normalize_list(data)
                    if normalized:
                        return normalized
            except (json.JSONDecodeError, ValueError):
                pass

        # --- Pass 4: plain-text numbered/bulleted list ---
        return self._parse_plain_text_lemmas(text)

    def _try_parse_json(self, candidate: str) -> list[dict] | None:
        """Return a list of lemma dicts if candidate is valid JSON, else None."""
        try:
            data = json.loads(candidate)
        except json.JSONDecodeError:
            return None
        if isinstance(data, list):
            normalized = self._normalize_list(data)
            return normalized if normalized else None
        if isinstance(data, dict):
            for key in self._LEMMA_KEYS:
                if key in data and isinstance(data[key], list):
                    normalized = self._normalize_list(data[key])
                    if normalized:
                        return normalized
        return None

    def _normalize_list(self, items: list) -> list[dict]:
        """Coerce a list of items into the expected lemma-dict shape."""
        result = []
        for item in items:
            if not isinstance(item, dict):
                continue
            # Accept any dict that has at least an id or statement
            lemma_id = (
                item.get("id")
                or item.get("lemma_id")
                or item.get("name")
                or item.get("title")
            )
            statement = (
                item.get("statement")
                or item.get("formal_statement")
                or item.get("hypothesis")
                or item.get("content")
                or item.get("text")
                or ""
            )
            if not lemma_id and not statement:
                continue
            result.append({
                "id": lemma_id or f"lemma_{len(result)+1}",
                "statement": statement,
                "informal": (
                    item.get("informal")
                    or item.get("intuition")
                    or item.get("description")
                    or item.get("rationale")
                    or ""
                ),
                "dependencies": item.get("dependencies") or item.get("deps") or [],
            })
        return result

    def _parse_plain_text_lemmas(self, text: str) -> list[dict]:
        """Last-resort: extract lemmas from a numbered or bulleted list."""
        import re
        lines = text.splitlines()
        lemmas: list[dict] = []
        # Match lines like "1. Lemma: ...", "- Lemma 1: ...", "**Lemma 1**:"
        item_re = re.compile(
            r"^(?:\s*(?:\d+[\.\)]\s*|\*\s*|-\s*|#+\s*))"  # list marker or heading
            r"(?:[Ll]emma\s*\d*\s*[:.]?\s*)?"               # optional "Lemma N:"
            r"(.+)$"
        )
        for line in lines:
            m = item_re.match(line)
            if m:
                stmt = m.group(1).strip().rstrip(".")
                if len(stmt) > 10:  # skip very short noise lines
                    lemmas.append({
                        "id": f"lemma_{len(lemmas)+1}",
                        "statement": stmt,
                        "informal": "",
                        "dependencies": [],
                    })
        return lemmas

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
