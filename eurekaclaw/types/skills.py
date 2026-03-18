"""Skill types — mirrors the .md frontmatter schema."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class SkillMeta(BaseModel):
    name: str
    version: str = "1.0"
    tags: list[str] = Field(default_factory=list)
    agent_roles: list[str] = Field(default_factory=list)   # AgentRole values
    pipeline_stages: list[str] = Field(default_factory=list)
    description: str = ""
    source: Literal["seed", "distilled", "manual"] = "seed"
    created_at: datetime = Field(default_factory=datetime.utcnow)
    usage_count: int = 0
    success_rate: float | None = None


class SkillRecord(BaseModel):
    meta: SkillMeta
    content: str            # Full .md body after frontmatter
    file_path: str = ""     # Absolute path to .md file
    embedding: list[float] | None = None

    @property
    def full_markdown(self) -> str:
        return self.content
