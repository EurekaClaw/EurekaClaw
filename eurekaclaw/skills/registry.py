"""SkillRegistry — discover and load .md skill files with YAML frontmatter."""

from __future__ import annotations

import json
import logging
from pathlib import Path
import yaml

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

    @property
    def _seed_stats_path(self) -> Path:
        """Path to the JSON file that stores usage stats for seed skills."""
        return settings.eurekaclaw_dir / "seed_skill_stats.json"

    def _load_seed_stats(self) -> dict[str, dict]:
        """Return {skill_name: {usage_count, success_rate}} from the stats file."""
        if self._seed_stats_path.exists():
            try:
                return json.loads(self._seed_stats_path.read_text(encoding="utf-8"))
            except Exception as e:
                logger.warning("Failed to read seed skill stats: %s", e)
        return {}

    def _save_seed_stats(self, stats: dict[str, dict]) -> None:
        self._seed_stats_path.parent.mkdir(parents=True, exist_ok=True)
        self._seed_stats_path.write_text(
            json.dumps(stats, indent=2), encoding="utf-8"
        )

    def _load(self) -> None:
        self._skills.clear()
        seed_stats = self._load_seed_stats()
        # 1. Seed skills bundled with the package (lowest priority)
        # for path in sorted(_SEED_DIR.rglob("*.md")):
        #     self._load_file(path, is_seed=True, seed_stats=seed_stats)
        # 2. Domain plugin skill dirs (medium priority)
        # for extra_dir in self._extra_dirs:
        #     if extra_dir.exists():
        #         for path in sorted(extra_dir.rglob("*.md")):
        #             self._load_file(path, is_seed=True, seed_stats=seed_stats)
        # 3. User skills from ~/.eurekaclaw/skills/ (highest priority)
        self._skills_dir.mkdir(parents=True, exist_ok=True)
        skill_names = [s for s in self._skills_dir.iterdir() if s.is_dir()]
        for skill_name_path in skill_names:
            file = skill_name_path / "SKILL.md"
            record = self._load_file(file, is_seed=False)
            skill_name = skill_name_path.name
            record.meta.name = skill_name  # Override name from frontmatter with folder name
            self._skills[skill_name] = record
        self._loaded = True
        logger.debug("Loaded %d skills total", len(self._skills))

    def _load_file(
        self, path: Path, is_seed: bool = False, seed_stats: dict | None = None
    ) -> None:
        post = frontmatter.load(str(path))
        meta_dict = dict(post.metadata)
        if not meta_dict.get("name"):
            meta_dict["name"] = path.stem
        if is_seed and "source" not in meta_dict:
            meta_dict["source"] = "seed"
        meta = SkillMeta.model_validate(meta_dict)
        # Overlay usage stats from the external JSON so seed .md files
        # are never modified by runtime activity.
        if is_seed and seed_stats and meta.name in seed_stats:
            entry = seed_stats[meta.name]
            meta.usage_count = entry.get("usage_count", meta.usage_count)
            meta.success_rate = entry.get("success_rate", meta.success_rate)
        record = SkillRecord(meta=meta, content=post.content, file_path=str(path))
        return record
        # self._skills[meta.name] = record
        # except Exception as e:
        #     logger.warning("Failed to load skill %s: %s", path, e)

    # ------------------------------------------------------------------

    def load_all(self) -> list[SkillRecord]:
        self._ensure_loaded()
        for skill in self._skills.values():
            self.upsert(skill)  # Ensure all skills are upserted to persist any new stats
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
          # PyYAML — already a transitive dep via python-frontmatter

        self._skills_dir.mkdir(parents=True, exist_ok=True)
        folder_name = skill.meta.name
        folder_path = self._skills_dir / f"{folder_name}"
        folder_path.mkdir(parents=True, exist_ok=True)
        file_path = folder_path / "SKILL.md"

        meta_dict = skill.meta.model_dump(mode="json")
        # Drop None values so they don't serialize as the string 'null'
        meta_dict = {k: v for k, v in meta_dict.items() if v is not None}
        frontmatter_block = yaml.dump(meta_dict, default_flow_style=False, allow_unicode=True)
        file_content = f"---\n{frontmatter_block}---\n\n{skill.content}"
        file_path.write_text(file_content, encoding="utf-8")
        skill.file_path = str(file_path)
        self._skills[skill.meta.name] = skill
        logger.info("Upserted skill: %s", skill.meta.name)

    def update_stats(self, name: str, success: bool) -> None:
        """Update usage_count and success_rate for a skill after a session.

        Called by ContinualLearningLoop after session completes so skills that
        actually helped get promoted in future top_k retrieval.

        Seed skills: stats are written to ~/.eurekaclaw/seed_skill_stats.json
                     so the bundled .md files are never modified.
        Distilled skills: stats are written back into their own .md file in
                          ~/.eurekaclaw/skills/ as before.
        """
        skill = self.get(name)
        if not skill:
            return

        skill.meta.usage_count += 1
        prev_rate = skill.meta.success_rate
        if prev_rate is None:
            skill.meta.success_rate = 1.0 if success else 0.0
        else:
            # Exponential moving average (α=0.3) so recent outcomes matter more
            skill.meta.success_rate = 0.7 * prev_rate + 0.3 * (1.0 if success else 0.0)

        if skill.meta.source == "seed":
            # Persist to external JSON — never touch the .md file
            stats = self._load_seed_stats()
            stats[name] = {
                "usage_count": skill.meta.usage_count,
                "success_rate": skill.meta.success_rate,
            }
            self._save_seed_stats(stats)
        else:
            import yaml

            if not skill.file_path:
                return
            path = Path(skill.file_path)
            if not path.exists():
                return
            meta_dict = skill.meta.model_dump(mode="json")
            meta_dict = {k: v for k, v in meta_dict.items() if v is not None}
            frontmatter_block = yaml.dump(meta_dict, default_flow_style=False, allow_unicode=True)
            path.write_text(f"---\n{frontmatter_block}---\n\n{skill.content}", encoding="utf-8")

        logger.debug(
            "Updated skill stats: %s usage=%d success_rate=%.2f",
            name, skill.meta.usage_count, skill.meta.success_rate or 0,
        )

    def reload(self) -> None:
        self._loaded = False
        self._ensure_loaded()


if __name__ == "__main__":
    registry = SkillRegistry()
    all_skills = registry.load_all()
    print(f"Loaded {len(all_skills)} skills:")
    for skill in all_skills:
        print(f"- {skill.meta.name}")
        # registry.upsert(skill)