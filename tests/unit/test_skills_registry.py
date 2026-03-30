"""Unit tests for the skills registry and injector."""

import tempfile
from pathlib import Path

import pytest

from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.types.skills import SkillMeta, SkillRecord
from eurekaclaw.types.tasks import Task


@pytest.fixture
def tmp_skills_dir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def populated_registry(tmp_skills_dir):
    registry = SkillRegistry(skills_dir=tmp_skills_dir)

    skill_content = """\
---
name: test_induction
version: "1.0"
tags: [theory, proof, induction]
agent_roles: [theory]
pipeline_stages: [proof_attempt]
description: Test induction skill
source: seed
---

# Test Induction Skill
Apply induction to prove properties.
"""
    skill_dir = tmp_skills_dir / "test_induction"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(skill_content)
    registry.reload()
    return registry


def test_registry_loads_skills(populated_registry):
    skills = populated_registry.load_all()
    # Should include the test skill plus any seed skills found
    names = [s.meta.name for s in skills]
    assert "test_induction" in names


def test_registry_get_by_role(populated_registry):
    theory_skills = populated_registry.get_by_role("theory")
    assert any(s.meta.name == "test_induction" for s in theory_skills)


def test_registry_get_by_tags(populated_registry):
    induction_skills = populated_registry.get_by_tags(["induction"])
    assert any(s.meta.name == "test_induction" for s in induction_skills)


def test_registry_upsert(tmp_skills_dir):
    registry = SkillRegistry(skills_dir=tmp_skills_dir)
    meta = SkillMeta(name="new_skill", description="A new skill", tags=["test"], agent_roles=["survey"])
    record = SkillRecord(meta=meta, content="# New Skill\n\nContent here.")
    registry.upsert(record)

    loaded = registry.get("new_skill")
    assert loaded is not None
    assert loaded.meta.name == "new_skill"


def test_injector_render_for_prompt(populated_registry):
    injector = SkillInjector(populated_registry)
    task = Task(task_id="t1", name="prove lemma", agent_role="theory")
    skills = injector.top_k(task, role="theory", k=3)
    rendered = injector.render_for_prompt(skills)
    assert "<skills>" in rendered
    assert "</skills>" in rendered
