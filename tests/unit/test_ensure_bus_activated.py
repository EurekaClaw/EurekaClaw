"""Tests for the _ensure_bus_activated(run) helper."""

from dataclasses import dataclass
from typing import Any

import pytest

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus


@dataclass
class _FakeSession:
    bus: Any
    session_id: str = "test-bus-001"


@dataclass
class _FakeRun:
    eureka_session: Any
    eureka_session_id: str = "test-bus-001"


def _make_hydrated_bus(session_id: str) -> KnowledgeBus:
    bus = KnowledgeBus(session_id)
    bus.put_pipeline(TaskPipeline(
        pipeline_id="p1", session_id=session_id,
        tasks=[Task(
            task_id="w1", name="writer", agent_role="writer",
            description="", status=TaskStatus.COMPLETED,
            outputs={"latex_paper": r"\section{x}"},
        )],
    ))
    bus.put_research_brief(ResearchBrief(
        session_id=session_id, input_mode="exploration",
        domain="test", query="q",
    ))
    return bus


def test_returns_existing_bus_when_already_attached():
    from eurekaclaw.ui.server import _ensure_bus_activated

    bus = _make_hydrated_bus("test-bus-001")
    run = _FakeRun(eureka_session=_FakeSession(bus=bus))

    got_bus, pipeline, brief = _ensure_bus_activated(run)

    assert got_bus is bus
    assert pipeline is not None
    assert brief is not None


def test_loads_via_session_loader_when_not_attached(monkeypatch):
    from eurekaclaw.ui import server as srv

    bus = _make_hydrated_bus("test-bus-002")

    class _StubLoader:
        @staticmethod
        def load(session_id):
            return bus, bus.get_research_brief(), bus.get_pipeline()

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.session_loader.SessionLoader", _StubLoader
    )

    run = _FakeRun(eureka_session=None, eureka_session_id="test-bus-002")
    got_bus, pipeline, brief = srv._ensure_bus_activated(run)

    assert got_bus is bus
    assert run.eureka_session is not None
    assert run.eureka_session.bus is bus


def test_raises_value_error_when_pipeline_missing(monkeypatch):
    from eurekaclaw.ui.server import _ensure_bus_activated

    bus = KnowledgeBus("test-bus-003")  # no pipeline, no brief
    run = _FakeRun(eureka_session=_FakeSession(bus=bus))

    with pytest.raises(ValueError, match="pipeline or brief"):
        _ensure_bus_activated(run)


def test_propagates_file_not_found_from_loader(monkeypatch):
    from eurekaclaw.ui import server as srv

    class _StubLoader:
        @staticmethod
        def load(session_id):
            raise FileNotFoundError(f"Session '{session_id}' not found")

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.session_loader.SessionLoader", _StubLoader
    )

    run = _FakeRun(eureka_session=None, eureka_session_id="missing")
    with pytest.raises(FileNotFoundError, match="not found"):
        srv._ensure_bus_activated(run)
