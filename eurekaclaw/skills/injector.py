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

    def __init__(self, registry: SkillRegistry, selected_skills: list[str] | None = None) -> None:
        self.registry = registry
        self._injected: set[str] = set()
        self.selected_skills = []
        for skill_name in selected_skills or []:
            skill = self.registry.get(skill_name)
            if skill:
                self.selected_skills.append(skill)
            else:
                logger.warning("Selected skill %r not found in registry", skill_name)

    def top_k(
        self,
        task: Task,
        role: str,
        k: int = 5,
        strategy: Literal["tag", "semantic", "hybrid"] = "tag",
    ) -> list[SkillRecord]:
        """Return top-k skills for this task/role combination."""
        if strategy == "tag":
            return self._tag_retrieval(task.agent_role, role, k)
        if strategy == "semantic":
            return self._semantic_retrieval(task, role, k)
        # # hybrid: tag filter first, then rank by description similarity
        candidates = self._tag_retrieval(task.agent_role, role, k * 3)
        # if len(candidates) <= k:
        #     return candidates
        return self._rank_by_text_similarity(candidates, task, k)

    def _tag_retrieval(self, task_role: str, role: str, k: int) -> list[SkillRecord]:
        by_role = self.registry.get_by_role(role)
        by_stage = self.registry.get_by_pipeline_stage(task_role)

        all_names = set(s.meta.name for s in by_role + by_stage)
        # Filter by selected skills if specified
        if self.selected_skills:
            must_have = set(s.meta.name for s in self.selected_skills)
            must_have = must_have & all_names
        else:
            must_have = set()
        optional_names = all_names - must_have

        must_have_skills = [self.registry.get(name) for name in must_have]
        optional_skills = [self.registry.get(name) for name in optional_names]
        # Sort other skills by usage_count (most-used first for established skills)
        optional_skills.sort(key=lambda s: s.meta.usage_count, reverse=True)
        combined = must_have_skills + optional_skills
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

    def render_for_prompt(self, skills: list[SkillRecord], domain: str = "") -> str:
        """Format skills + cross-session memories for system prompt injection."""
        parts: list[str] = []

        if skills:
            parts.append("<skills>")
            for skill in skills:
                parts.append(f"<skill name=\"{skill.meta.name}\">")
                parts.append(skill.content.strip())
                parts.append("</skill>")
                self._injected.add(skill.meta.name)
            parts.append("</skills>")

        # Inject cross-session domain memories via MemoryManager (tier 4)
        if domain:
            try:
                from eurekaclaw.memory.manager import MemoryManager
                memories_block = MemoryManager(session_id="injector").load_for_injection(domain, k=4)
                if memories_block:
                    parts.append(memories_block)
            except Exception:
                pass  # Never block on memory loading failure

        return "\n".join(parts)




if __name__ == "__main__":    # Quick test
    import pathlib
    from eurekaclaw.types.tasks import Task
    from eurekaclaw.types.agents import AgentRole
    registry = SkillRegistry(skills_dir=pathlib.Path.home() / ".eurekaclaw/skills")
    injector = SkillInjector(registry, selected_skills=["eluder_dimension", "compactness_argument"])
    top_skills = injector._tag_retrieval(AgentRole.SURVEY, AgentRole.THEORY, 3)
    print([s.meta.name for s in top_skills])