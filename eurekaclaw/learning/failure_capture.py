"""FailureCapturer — intercepts warnings, retries, and dead-ends during a run."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


@dataclass
class TaskFailure:
    task_id: str
    task_name: str
    agent_role: str
    error: str
    retries: int


@dataclass
class ProofTrajectory:
    """A full proof attempt trajectory for PRM scoring."""
    session_id: str
    lemma_id: str
    steps: list[str]   # proof steps taken
    outcome: str       # "proved", "failed", "counterexample"
    score: float = 0.0


class FailureCapturer:
    """Collects failures and proof trajectories during a run for post-run distillation."""

    def __init__(self) -> None:
        self._task_failures: list[TaskFailure] = []
        self._proof_trajectories: list[ProofTrajectory] = []

    def record_task_failure(self, task: Task, error: str) -> None:
        self._task_failures.append(TaskFailure(
            task_id=task.task_id,
            task_name=task.name,
            agent_role=task.agent_role,
            error=error,
            retries=task.retries,
        ))
        logger.debug("Captured task failure: %s — %s", task.name, error[:100])

    def record_proof_trajectory(self, trajectory: ProofTrajectory) -> None:
        self._proof_trajectories.append(trajectory)

    def drain(self) -> list[TaskFailure]:
        """Return and clear all recorded failures."""
        failures = list(self._task_failures)
        self._task_failures.clear()
        return failures

    def get_proof_trajectories(self) -> list[ProofTrajectory]:
        return list(self._proof_trajectories)

    def clear(self) -> None:
        self._task_failures.clear()
        self._proof_trajectories.clear()
