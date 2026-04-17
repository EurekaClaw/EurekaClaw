"""Unit tests for POST /api/runs/<id>/rewrite.

Exercises the helpers the HTTP handler wires together — _run_rewrite_bg,
_mark_rewrite_tasks_failed, _append_paper_qa_rewrite_marker_file,
_append_paper_qa_error_marker, _unlink_stale_pdf — without spinning up
an HTTP server. The endpoint route itself is exercised via a parsed
path shape test below.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import pytest

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus


@dataclass
class _FakeSession:
    bus: Any
    session_id: str = "test-rewrite-001"


@dataclass
class _FakeRun:
    output_dir: str | None
    eureka_session: Any
    eureka_session_id: str = "test-rewrite-001"


@pytest.fixture
def run_with_bus(tmp_path, monkeypatch):
    # Point settings.runs_dir at tmp_path so helpers that write markers
    # do so inside the test sandbox.
    from eurekaclaw.ui import server as srv
    monkeypatch.setattr(srv.settings, "runs_dir", tmp_path)

    session_id = "test-rewrite-001"
    bus = KnowledgeBus(session_id)
    theory = Task(
        task_id="t1", name="theory", agent_role="theory",
        description="Prove", status=TaskStatus.COMPLETED,
        outputs={"proof": "Q.E.D."},
    )
    writer = Task(
        task_id="w1", name="writer", agent_role="writer",
        description="Write", status=TaskStatus.COMPLETED,
        outputs={"latex_paper": r"\section{x} v1", "paper_version": 1},
    )
    qa_gate = Task(
        task_id="g1", name="paper_qa_gate", agent_role="orchestrator",
        description="gate", status=TaskStatus.COMPLETED,
    )
    bus.put_pipeline(TaskPipeline(
        pipeline_id="p1", session_id=session_id,
        tasks=[theory, writer, qa_gate],
    ))
    bus.put_research_brief(ResearchBrief(
        session_id=session_id, input_mode="exploration",
        domain="test", query="q",
    ))

    output_dir = tmp_path / "run-output"
    output_dir.mkdir()
    (output_dir / "paper.tex").write_text(r"\section{x} v1", encoding="utf-8")
    (output_dir / "paper.pdf").write_bytes(b"%PDF-old")

    run = _FakeRun(
        output_dir=str(output_dir),
        eureka_session=_FakeSession(bus=bus, session_id=session_id),
        eureka_session_id=session_id,
    )
    return run, bus, tmp_path


def test_unlink_stale_pdf_removes_pdf_from_output_dir(run_with_bus):
    from eurekaclaw.ui.server import _unlink_stale_pdf

    run, _bus, _runs_dir = run_with_bus
    pdf_path = Path(run.output_dir) / "paper.pdf"
    assert pdf_path.exists()

    _unlink_stale_pdf(run)

    assert not pdf_path.exists()


def test_mark_rewrite_tasks_failed_sets_theory_and_writer_to_failed(run_with_bus):
    from eurekaclaw.ui.server import _mark_rewrite_tasks_failed

    _run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    theory = next(t for t in pipeline.tasks if t.name == "theory")
    writer = next(t for t in pipeline.tasks if t.name == "writer")
    theory.status = TaskStatus.IN_PROGRESS
    writer.status = TaskStatus.IN_PROGRESS
    bus.put_pipeline(pipeline)

    _mark_rewrite_tasks_failed(pipeline, bus)

    pipeline = bus.get_pipeline()
    assert next(t for t in pipeline.tasks if t.name == "theory").status == TaskStatus.FAILED
    assert next(t for t in pipeline.tasks if t.name == "writer").status == TaskStatus.FAILED


def test_mark_rewrite_tasks_failed_also_covers_experiment(run_with_bus):
    """experiment is in the rewrite replay set (Task 1) and must be reset too.

    If this test fails because someone shrank the helper's loop back to
    theory+writer, the /rewrite concurrency guard in do_POST has the same
    scope bug — they must stay aligned.
    """
    from eurekaclaw.ui.server import _mark_rewrite_tasks_failed

    _run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    experiment = Task(
        task_id="e1", name="experiment", agent_role="experiment",
        description="Run experiment", status=TaskStatus.IN_PROGRESS,
    )
    pipeline.tasks.append(experiment)
    bus.put_pipeline(pipeline)

    _mark_rewrite_tasks_failed(pipeline, bus)

    pipeline = bus.get_pipeline()
    assert next(t for t in pipeline.tasks if t.name == "experiment").status == TaskStatus.FAILED


def test_append_rewrite_marker_writes_jsonl_line(run_with_bus):
    from eurekaclaw.ui.server import _append_paper_qa_rewrite_marker_file

    _run, _bus, runs_dir = run_with_bus

    _append_paper_qa_rewrite_marker_file("test-rewrite-001", "tighten")

    history_file = runs_dir / "test-rewrite-001" / "paper_qa_history.jsonl"
    assert history_file.exists()
    import json
    line = history_file.read_text(encoding="utf-8").strip()
    entry = json.loads(line)
    assert entry["role"] == "system"
    assert entry["content"] == '↻ Rewrite requested: "tighten"'


def test_append_error_marker_writes_jsonl_line(run_with_bus):
    from eurekaclaw.ui.server import _append_paper_qa_error_marker

    _run, _bus, runs_dir = run_with_bus

    _append_paper_qa_error_marker("test-rewrite-001", "rewrite blew up")

    history_file = runs_dir / "test-rewrite-001" / "paper_qa_history.jsonl"
    assert history_file.exists()
    import json
    entry = json.loads(history_file.read_text(encoding="utf-8").strip())
    assert entry["role"] == "system"
    assert entry["content"] == "Revision error: rewrite blew up"


def test_run_rewrite_bg_happy_path_bumps_version_and_appends_marker(run_with_bus, monkeypatch):
    """Success: _do_rewrite returns new latex → version bump + marker."""
    from eurekaclaw.ui import server as srv

    run, bus, runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    # Ensure writer's bus latex gets updated like _do_rewrite would.
    writer = next(t for t in pipeline.tasks if t.name == "writer")
    writer.outputs["latex_paper"] = r"\section{x} v2"
    bus.put_pipeline(pipeline)

    async def _fake_do_rewrite(self, pipe, br, revision_prompt=None, writer_only=False):
        return r"\section{x} v2"

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.paper_qa_handler.PaperQAHandler._do_rewrite",
        _fake_do_rewrite,
    )

    # Stub out MetaOrchestrator so we don't need LLM credentials in tests.
    fake_orch = MagicMock()
    fake_orch.agents = {}
    fake_orch.router = MagicMock()
    fake_orch.client = MagicMock()
    fake_orch.tool_registry = MagicMock()
    fake_orch.skill_injector = MagicMock()
    fake_orch.memory = MagicMock()
    fake_orch.gate = MagicMock()
    monkeypatch.setattr(srv, "MetaOrchestrator", MagicMock(return_value=fake_orch))
    monkeypatch.setattr(srv, "create_client", MagicMock())

    srv._run_rewrite_bg(run, bus, pipeline, brief, "tighten Section 3", "rw-1")

    # paper_version bumped
    writer = next(t for t in bus.get_pipeline().tasks if t.name == "writer")
    assert writer.outputs["paper_version"] == 2
    # marker appended
    history_file = runs_dir / "test-rewrite-001" / "paper_qa_history.jsonl"
    assert history_file.exists()
    assert "tighten Section 3" in history_file.read_text(encoding="utf-8")


def test_run_rewrite_bg_catches_exceptions_and_marks_failed(run_with_bus, monkeypatch):
    from eurekaclaw.ui import server as srv

    run, bus, runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    # Flip theory + writer to IN_PROGRESS so the failure-marker path has
    # work to do.
    theory = next(t for t in pipeline.tasks if t.name == "theory")
    writer = next(t for t in pipeline.tasks if t.name == "writer")
    theory.status = TaskStatus.IN_PROGRESS
    writer.status = TaskStatus.IN_PROGRESS
    bus.put_pipeline(pipeline)

    async def _boom(self, pipe, br, revision_prompt=None, writer_only=False):
        raise RuntimeError("simulated agent crash")

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.paper_qa_handler.PaperQAHandler._do_rewrite",
        _boom,
    )

    fake_orch = MagicMock()
    for attr in ("agents", "router", "client", "tool_registry",
                 "skill_injector", "memory", "gate"):
        setattr(fake_orch, attr, MagicMock() if attr != "agents" else {})
    monkeypatch.setattr(srv, "MetaOrchestrator", MagicMock(return_value=fake_orch))
    monkeypatch.setattr(srv, "create_client", MagicMock())

    # Must not raise.
    srv._run_rewrite_bg(run, bus, pipeline, brief, "tighten", "rw-2")

    pipeline = bus.get_pipeline()
    assert next(t for t in pipeline.tasks if t.name == "theory").status == TaskStatus.FAILED
    assert next(t for t in pipeline.tasks if t.name == "writer").status == TaskStatus.FAILED

    history_file = runs_dir / "test-rewrite-001" / "paper_qa_history.jsonl"
    assert history_file.exists()
    text = history_file.read_text(encoding="utf-8")
    assert "Revision error" in text
    assert "simulated agent crash" in text
