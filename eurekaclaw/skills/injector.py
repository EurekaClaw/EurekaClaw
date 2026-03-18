"""SkillInjector — retrieve top-k skills and format them for prompt injection."""

from __future__ import annotations

import logging
from typing import Literal

from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.types.skills import SkillRecord
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


class SkillInjector:
    """Retrieves top-k skills relevant to a task and formats for system prompt injection."""

    def __init__(self, registry: SkillRegistry) -> None:
        self.registry = registry

    def top_k(
        self,
        task: Task,
        role: str,
        k: int = 5,
        strategy: Literal["tag", "semantic", "hybrid"] = "tag",
    ) -> list[SkillRecord]:
        """Return top-k skills for this task/role combination."""
        if strategy == "tag":
            return self._tag_retrieval(task, role, k)
        if strategy == "semantic":
            return self._semantic_retrieval(task, role, k)
        # hybrid: tag filter first, then rank by description similarity
        candidates = self._tag_retrieval(task, role, k * 3)
        if len(candidates) <= k:
            return candidates
        return self._rank_by_text_similarity(candidates, task, k)

    def _tag_retrieval(self, task: Task, role: str, k: int) -> list[SkillRecord]:
        by_role = self.registry.get_by_role(role)
        by_stage = self.registry.get_by_pipeline_stage(task.agent_role)
        # Union, deduplicated by name
        seen: set[str] = set()
        combined = []
        for s in by_role + by_stage:
            if s.meta.name not in seen:
                seen.add(s.meta.name)
                combined.append(s)
        # Sort by usage_count (most-used first for established skills)
        combined.sort(key=lambda s: s.meta.usage_count, reverse=True)
        return combined[:k]

    def _semantic_retrieval(self, task: Task, role: str, k: int) -> list[SkillRecord]:
        """Embedding-based retrieval using sentence-transformers."""
        try:
            from sentence_transformers import SentenceTransformer  # type: ignore
            import numpy as np  # type: ignore

            model = SentenceTransformer("all-MiniLM-L6-v2")
            query = f"{task.name} {task.description} {role}"
            q_emb = model.encode(query)

            skills = self.registry.load_all()
            scored = []
            for skill in skills:
                text = f"{skill.meta.name} {skill.meta.description} {' '.join(skill.meta.tags)}"
                s_emb = model.encode(text)
                score = float(np.dot(q_emb, s_emb) / (np.linalg.norm(q_emb) * np.linalg.norm(s_emb) + 1e-9))
                scored.append((score, skill))
            scored.sort(key=lambda x: x[0], reverse=True)
            return [s for _, s in scored[:k]]
        except ImportError:
            logger.debug("sentence-transformers not available, falling back to tag retrieval")
            return self._tag_retrieval(task, role, k)

    def _rank_by_text_similarity(self, candidates: list[SkillRecord], task: Task, k: int) -> list[SkillRecord]:
        """Simple keyword overlap ranking as fallback."""
        query_words = set((task.name + " " + task.description).lower().split())
        def score(s: SkillRecord) -> int:
            skill_words = set((s.meta.name + " " + s.meta.description + " " + " ".join(s.meta.tags)).lower().split())
            return len(query_words & skill_words)
        return sorted(candidates, key=score, reverse=True)[:k]

    def render_for_prompt(self, skills: list[SkillRecord]) -> str:
        """Format skills for system prompt injection as an XML block."""
        if not skills:
            return ""
        parts = ["<skills>"]
        for skill in skills:
            parts.append(f"<skill name=\"{skill.meta.name}\">")
            parts.append(skill.content.strip())
            parts.append("</skill>")
        parts.append("</skills>")
        return "\n".join(parts)
