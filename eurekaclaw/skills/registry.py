"""SkillRegistry — discover and load .md skill files with YAML frontmatter."""

from __future__ import annotations

import logging
from pathlib import Path

import frontmatter  # type: ignore

from eurekaclaw.config import settings
from eurekaclaw.types.skills import SkillMeta, SkillRecord

logger = logging.getLogger(__name__)

# Seed skills bundled with the package
_SEED_DIR = Path(__file__).parent / "seed_skills"


class SkillRegistry:
    """Discovers .md files from skills_dir, bundled seed_skills/, and domain plugins."""

    def __init__(self, skills_dir: Path | None = None) -> None:
        self._skills_dir = skills_dir or settings.skills_dir
        self._extra_dirs: list[Path] = []
        self._skills: dict[str, SkillRecord] = {}
        self._loaded = False

    def add_skills_dir(self, path: Path) -> None:
        """Register an extra directory (e.g. from a DomainPlugin) to load skills from."""
        if path not in self._extra_dirs:
            self._extra_dirs.append(path)
        self._loaded = False  # force reload on next access

    def _ensure_loaded(self) -> None:
        if not self._loaded:
            self._load()

    def _load(self) -> None:
        self._skills.clear()
        # 1. Seed skills bundled with the package (lowest priority)
        for path in sorted(_SEED_DIR.rglob("*.md")):
            self._load_file(path, is_seed=True)
        # 2. Domain plugin skill dirs (medium priority)
        for extra_dir in self._extra_dirs:
            if extra_dir.exists():
                for path in sorted(extra_dir.rglob("*.md")):
                    self._load_file(path, is_seed=True)
        # 3. User skills from ~/.metaclaw/skills/ (highest priority)
        self._skills_dir.mkdir(parents=True, exist_ok=True)
        for path in sorted(self._skills_dir.rglob("*.md")):
            self._load_file(path, is_seed=False)
        self._loaded = True
        logger.debug("Loaded %d skills total", len(self._skills))

    def _load_file(self, path: Path, is_seed: bool = False) -> None:
        try:
            post = frontmatter.load(str(path))
            meta_dict = dict(post.metadata)
            if not meta_dict.get("name"):
                meta_dict["name"] = path.stem
            if is_seed and "source" not in meta_dict:
                meta_dict["source"] = "seed"
            meta = SkillMeta.model_validate(meta_dict)
            record = SkillRecord(meta=meta, content=post.content, file_path=str(path))
            self._skills[meta.name] = record
        except Exception as e:
            logger.warning("Failed to load skill %s: %s", path, e)

    # ------------------------------------------------------------------

    def load_all(self) -> list[SkillRecord]:
        self._ensure_loaded()
        return list(self._skills.values())

    def get(self, name: str) -> SkillRecord | None:
        self._ensure_loaded()
        return self._skills.get(name)

    def get_by_tags(self, tags: list[str]) -> list[SkillRecord]:
        self._ensure_loaded()
        tag_set = set(tags)
        return [s for s in self._skills.values() if tag_set & set(s.meta.tags)]

    def get_by_role(self, role: str) -> list[SkillRecord]:
        self._ensure_loaded()
        return [s for s in self._skills.values() if role in s.meta.agent_roles]

    def get_by_pipeline_stage(self, stage: str) -> list[SkillRecord]:
        self._ensure_loaded()
        return [s for s in self._skills.values() if stage in s.meta.pipeline_stages]

    def upsert(self, skill: SkillRecord) -> None:
        """Write a skill to the skills directory and update the registry."""
        import yaml  # PyYAML — already a transitive dep via python-frontmatter

        self._skills_dir.mkdir(parents=True, exist_ok=True)
        path = self._skills_dir / f"{skill.meta.name}.md"
        meta_dict = skill.meta.model_dump(mode="json")
        # Drop None values so they don't serialize as the string 'null'
        meta_dict = {k: v for k, v in meta_dict.items() if v is not None}
        frontmatter_block = yaml.dump(meta_dict, default_flow_style=False, allow_unicode=True)
        file_content = f"---\n{frontmatter_block}---\n\n{skill.content}"
        path.write_text(file_content)
        skill.file_path = str(path)
        self._skills[skill.meta.name] = skill
        logger.info("Upserted skill: %s", skill.meta.name)

    def update_stats(self, name: str, success: bool) -> None:
        """Update usage_count and success_rate for a skill after a session.

        Called by ContinualLearningLoop after session completes so skills that
        actually helped get promoted in future top_k retrieval.
        """
        import yaml

        skill = self.get(name)
        if not skill or not skill.file_path:
            return
        path = Path(skill.file_path)
        if not path.exists():
            return

        skill.meta.usage_count += 1
        prev_rate = skill.meta.success_rate
        if prev_rate is None:
            skill.meta.success_rate = 1.0 if success else 0.0
        else:
            # Exponential moving average (α=0.3) so recent outcomes matter more
            skill.meta.success_rate = 0.7 * prev_rate + 0.3 * (1.0 if success else 0.0)

        meta_dict = skill.meta.model_dump(mode="json")
        meta_dict = {k: v for k, v in meta_dict.items() if v is not None}
        frontmatter_block = yaml.dump(meta_dict, default_flow_style=False, allow_unicode=True)
        path.write_text(f"---\n{frontmatter_block}---\n\n{skill.content}")
        logger.debug(
            "Updated skill stats: %s usage=%d success_rate=%.2f",
            name, skill.meta.usage_count, skill.meta.success_rate or 0,
        )

    def reload(self) -> None:
        self._loaded = False
        self._ensure_loaded()
