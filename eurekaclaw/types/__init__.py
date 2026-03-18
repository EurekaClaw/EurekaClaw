"""Shared Pydantic v2 models — the lingua franca of all EurekaClaw modules."""

from eurekaclaw.types.agents import AgentMessage, AgentResult, AgentRole
from eurekaclaw.types.artifacts import (
    Bibliography,
    Counterexample,
    ExperimentResult,
    FailedAttempt,
    LemmaNode,
    Paper,
    ProofRecord,
    ResearchBrief,
    ResearchDirection,
    TheoryState,
)
from eurekaclaw.types.memory import CrossRunRecord, EpisodicEntry, KnowledgeNode
from eurekaclaw.types.skills import SkillMeta, SkillRecord
from eurekaclaw.types.tasks import InputSpec, ResearchOutput, Task, TaskPipeline, TaskStatus

__all__ = [
    "AgentMessage",
    "AgentResult",
    "AgentRole",
    "Bibliography",
    "Counterexample",
    "CrossRunRecord",
    "EpisodicEntry",
    "ExperimentResult",
    "FailedAttempt",
    "InputSpec",
    "KnowledgeNode",
    "LemmaNode",
    "Paper",
    "ProofRecord",
    "ResearchBrief",
    "ResearchDirection",
    "ResearchOutput",
    "SkillMeta",
    "SkillRecord",
    "Task",
    "TaskPipeline",
    "TaskStatus",
    "TheoryState",
]
