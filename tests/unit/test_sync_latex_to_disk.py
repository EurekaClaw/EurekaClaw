"""Tests for the _sync_latex_to_disk(run) helper."""

from dataclasses import dataclass
from typing import Any

import pytest

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus


@dataclass
class _FakeSession:
    bus: Any


@dataclass
class _FakeRun:
    output_dir: str | None
    eureka_session: Any
    eureka_session_id: str = "test-sync-001"


@pytest.fixture
def run_with_bus(tmp_path):
    bus = KnowledgeBus("test-sync-001")
    writer = Task(
        task_id="w1",
        name="writer",
        agent_role="writer",
        description="Write paper",
        status=TaskStatus.COMPLETED,
        outputs={"latex_paper": r"\section{Memory} v1"},
    )
    bus.put_pipeline(TaskPipeline(
        pipeline_id="p1", session_id="test-sync-001", tasks=[writer],
    ))
    session = _FakeSession(bus=bus)
    output_dir = tmp_path / "run-output"
    output_dir.mkdir()
    return _FakeRun(output_dir=str(output_dir), eureka_session=session), output_dir, bus


def test_sync_writes_paper_tex_when_disk_empty(run_with_bus):
    from eurekaclaw.ui.server import _sync_latex_to_disk

    run, output_dir, _bus = run_with_bus
    tex_path = output_dir / "paper.tex"
    assert not tex_path.exists()

    changed, latex = _sync_latex_to_disk(run)

    assert changed is True
    assert latex == r"\section{Memory} v1"
    assert tex_path.read_text(encoding="utf-8") == r"\section{Memory} v1"


def test_sync_no_change_when_disk_matches(run_with_bus):
    from eurekaclaw.ui.server import _sync_latex_to_disk

    run, output_dir, _bus = run_with_bus
    tex_path = output_dir / "paper.tex"
    tex_path.write_text(r"\section{Memory} v1", encoding="utf-8")

    changed, latex = _sync_latex_to_disk(run)

    assert changed is False
    assert latex == r"\section{Memory} v1"


def test_sync_writes_when_bus_differs_from_disk(run_with_bus):
    from eurekaclaw.ui.server import _sync_latex_to_disk

    run, output_dir, bus = run_with_bus
    tex_path = output_dir / "paper.tex"
    tex_path.write_text(r"\section{Old}", encoding="utf-8")

    pipeline = bus.get_pipeline()
    pipeline.tasks[0].outputs["latex_paper"] = r"\section{Memory} v2"
    bus.put_pipeline(pipeline)

    changed, latex = _sync_latex_to_disk(run)

    assert changed is True
    assert latex == r"\section{Memory} v2"
    assert tex_path.read_text(encoding="utf-8") == r"\section{Memory} v2"


def test_sync_never_touches_paper_pdf(run_with_bus):
    """The helper must not unlink paper.pdf even when .tex changes."""
    from eurekaclaw.ui.server import _sync_latex_to_disk

    run, output_dir, bus = run_with_bus
    tex_path = output_dir / "paper.tex"
    tex_path.write_text("old", encoding="utf-8")
    pdf_path = output_dir / "paper.pdf"
    pdf_path.write_bytes(b"%PDF-1.5\nstub")

    pipeline = bus.get_pipeline()
    pipeline.tasks[0].outputs["latex_paper"] = "new"
    bus.put_pipeline(pipeline)

    _sync_latex_to_disk(run)

    assert pdf_path.exists()
    assert pdf_path.read_bytes() == b"%PDF-1.5\nstub"


def test_sync_no_bus_returns_false_empty(tmp_path):
    from eurekaclaw.ui.server import _sync_latex_to_disk

    output_dir = tmp_path / "x"
    output_dir.mkdir()
    run = _FakeRun(output_dir=str(output_dir), eureka_session=None)

    changed, latex = _sync_latex_to_disk(run)

    assert changed is False
    assert latex == ""


def test_sync_no_output_dir_returns_false_empty(tmp_path):
    from eurekaclaw.ui.server import _sync_latex_to_disk

    bus = KnowledgeBus("no-dir")
    session = _FakeSession(bus=bus)
    run = _FakeRun(output_dir=None, eureka_session=session)

    changed, latex = _sync_latex_to_disk(run)

    assert changed is False
    assert latex == ""
