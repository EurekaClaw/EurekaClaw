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
        self.started_at = datetime.now().astimezone()

    def mark_completed(self, outputs: dict[str, Any] | None = None) -> None:
        self.status = TaskStatus.COMPLETED
        self.completed_at = datetime.now().astimezone()
        if outputs:
            self.outputs.update(outputs)

    def mark_failed(self, error: str) -> None:
        self.status = TaskStatus.FAILED
        self.error_message = error
        self.completed_at = datetime.now().astimezone()


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
    """User-provided input at the start of a research session.

    Three mutually exclusive modes control which pipeline stages are active:

    ``"detailed"`` — Level 1: Prove a specific conjecture.
        The user supplies a precise mathematical statement in ``conjecture``.
        The IdeationAgent's direction-generation step is bypassed entirely;
        the conjecture is used verbatim as the theorem to prove.
        Required field: ``conjecture``.

    ``"reference"`` — Level 2: Explore gaps around known papers.
        The user supplies one or more paper identifiers in ``paper_ids``
        (arXiv IDs or Semantic Scholar IDs) and/or raw texts in
        ``paper_texts``.  The SurveyAgent fetches and analyses those
        papers, then the IdeationAgent identifies research gaps and
        generates novel hypotheses before selecting the best direction.
        Required field: ``paper_ids`` or ``paper_texts`` (at least one).

    ``"exploration"`` — Level 3: Open-ended domain exploration.
        The user specifies only a research domain in ``domain`` and an
        optional guiding ``query``.  The system autonomously surveys the
        frontier, identifies open problems, proposes five research
        directions, and selects the most promising one before proceeding
        to the theory and writing stages.
        Required field: ``domain``.
    """

    mode: Literal["detailed", "reference", "exploration"]
    # Level 1: detailed conjecture
    conjecture: str | None = None
    # Level 2: reference-based (paper IDs or raw texts)
    paper_ids: list[str] = Field(default_factory=list)
    paper_texts: list[str] = Field(default_factory=list)
    # Level 3: open exploration
    domain: str = ""
    # Shared across all modes
    query: str = ""
    additional_context: str = ""
    selected_skills: list[str] = Field(default_factory=list)


class ResearchOutput(BaseModel):
    """Final output artifacts from a completed research session."""
    session_id: str
    latex_paper: str = ""
    pdf_path: str | None = None
    theory_state_json: str = ""
    experiment_result_json: str = ""
    research_brief_json: str = ""
    bibliography_json: str = ""
    eval_report_json: str = ""
    skills_distilled: list[str] = Field(default_factory=list)
    completed_at: datetime = Field(default_factory=datetime.utcnow)
