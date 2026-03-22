"""Unit tests for shared types."""

import pytest

from eurekaclaw.types.artifacts import (
    LemmaNode,
    ResearchDirection,
    TheoryState,
)
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus


def test_research_direction_composite_score():
    d = ResearchDirection(
        direction_id="d1",
        title="Test",
        hypothesis="some hypothesis",
        novelty_score=0.8,
        soundness_score=0.6,
        transformative_score=0.4,
    )
    score = d.compute_composite()
    # Default weights: 0.4*0.8 + 0.35*0.6 + 0.25*0.4
    expected = 0.4 * 0.8 + 0.35 * 0.6 + 0.25 * 0.4
    assert abs(score - expected) < 1e-6


def test_theory_state_is_complete():
    state = TheoryState(
        session_id="s",
        theorem_id="t",
        informal_statement="test",
        open_goals=[],
        status="proved",
    )
    assert state.is_complete()

    state.open_goals = ["lemma_1"]
    assert not state.is_complete()


def test_task_lifecycle():
    task = Task(
        task_id="t1",
        name="survey",
        agent_role="survey",
    )
    assert task.status == TaskStatus.PENDING
    task.mark_started()
    assert task.status == TaskStatus.IN_PROGRESS
    assert task.started_at is not None

    task.mark_completed({"result": "done"})
    assert task.status == TaskStatus.COMPLETED
    assert task.outputs == {"result": "done"}


def test_lemma_node():
    node = LemmaNode(
        lemma_id="l1",
        statement="∀x. f(x) ≥ 0",
        informal="f is non-negative",
        dependencies=["l0"],
    )
    assert node.lemma_id == "l1"
    assert "l0" in node.dependencies
