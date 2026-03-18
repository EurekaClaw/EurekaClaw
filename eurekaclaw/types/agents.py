"""Agent role and message types."""

from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class AgentRole(str, Enum):
    SURVEY = "survey"
    IDEATION = "ideation"
    THEORY = "theory"
    EXPERIMENT = "experiment"
    WRITER = "writer"
    ORCHESTRATOR = "orchestrator"


class AgentMessage(BaseModel):
    role: str       # "user" | "assistant"
    content: str
    tool_calls: list[dict[str, Any]] = Field(default_factory=list)
    tool_results: list[dict[str, Any]] = Field(default_factory=list)


class AgentResult(BaseModel):
    task_id: str
    agent_role: AgentRole
    success: bool
    output: dict[str, Any] = Field(default_factory=dict)
    text_summary: str = ""
    error: str = ""
    token_usage: dict[str, int] = Field(default_factory=dict)

    @property
    def failed(self) -> bool:
        return not self.success
