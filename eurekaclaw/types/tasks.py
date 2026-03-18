"""Task pipeline types for orchestrator-driven agent coordination."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field


class TaskStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    AWAITING_GATE = "awaiting_gate"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class Task(BaseModel):
    task_id: str
    name: str
    agent_role: str   # AgentRole value as string to avoid circular import
    description: str = ""
    inputs: dict[str, Any] = Field(default_factory=dict)
    outputs: dict[str, Any] = Field(default_factory=dict)
    status: TaskStatus = TaskStatus.PENDING
    depends_on: list[str] = Field(default_factory=list)  # task_ids
    gate_required: bool = False
    retries: int = 0
    max_retries: int = 3
    error_message: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    started_at: datetime | None = None
    completed_at: datetime | None = None

    def mark_started(self) -> None:
        self.status = TaskStatus.IN_PROGRESS
        self.started_at = datetime.utcnow()

    def mark_completed(self, outputs: dict[str, Any] | None = None) -> None:
        self.status = TaskStatus.COMPLETED
        self.completed_at = datetime.utcnow()
        if outputs:
            self.outputs.update(outputs)

    def mark_failed(self, error: str) -> None:
        self.status = TaskStatus.FAILED
        self.error_message = error
        self.completed_at = datetime.utcnow()


class TaskPipeline(BaseModel):
    pipeline_id: str
    session_id: str
    tasks: list[Task] = Field(default_factory=list)
    current_task_index: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)

    def get_task(self, task_id: str) -> Task | None:
        return next((t for t in self.tasks if t.task_id == task_id), None)

    def next_pending(self) -> Task | None:
        return next((t for t in self.tasks if t.status == TaskStatus.PENDING), None)


class InputSpec(BaseModel):
    """User-provided input at the start of a research session."""
    mode: Literal["detailed", "reference", "exploration"]
    # Level 1: detailed idea
    conjecture: str | None = None
    # Level 2: reference-based
    paper_ids: list[str] = Field(default_factory=list)
    paper_texts: list[str] = Field(default_factory=list)
    # Level 3: open exploration
    domain: str = ""
    # Shared
    query: str = ""
    additional_context: str = ""


class ResearchOutput(BaseModel):
    """Final output artifacts from a completed research session."""
    session_id: str
    latex_paper: str = ""
    pdf_path: str | None = None
    theory_state_json: str = ""
    experiment_result_json: str = ""
    research_brief_json: str = ""
    eval_report_json: str = ""
    skills_distilled: list[str] = Field(default_factory=list)
    completed_at: datetime = Field(default_factory=datetime.utcnow)
