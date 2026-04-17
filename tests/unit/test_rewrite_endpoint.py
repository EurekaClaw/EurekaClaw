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


def test_mark_rewrite_tasks_pending_flips_theory_experiment_writer(run_with_bus):
    """Handler-side PENDING flip BEFORE the bg thread spawns.

    Needed so the client's pipeline poll immediately sees pipelineRewriting
    (mode='rewriting') — otherwise there's a window between the 202 response
    and _do_rewrite's first mutation where the UI's isRewriting drops to
    false while the bg thread is still spinning up. That window is what
    allows a double-click to fire a second /rewrite and what hides an
    early bg failure (construction crash, etc) from the frontend.
    """
    from eurekaclaw.ui.server import _mark_rewrite_tasks_pending

    _run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    # Add an experiment task since the fixture doesn't include one.
    experiment = Task(
        task_id="e1", name="experiment", agent_role="experiment",
        description="Run", status=TaskStatus.COMPLETED,
    )
    pipeline.tasks.append(experiment)
    bus.put_pipeline(pipeline)

    _mark_rewrite_tasks_pending(pipeline, bus)

    refreshed = bus.get_pipeline()
    for name in ("theory", "experiment", "writer"):
        task = next(t for t in refreshed.tasks if t.name == name)
        assert task.status == TaskStatus.PENDING, (
            f"{name} should be PENDING so pipelineRewriting reports True"
        )


def test_mark_rewrite_tasks_failed_also_flips_pending_to_failed(run_with_bus):
    """If the handler flipped tasks to PENDING but the bg thread then
    crashed at orchestrator construction (before any task transitioned
    to IN_PROGRESS), the exception-recovery helper must still produce
    a visible terminal state. Otherwise tasks are left PENDING forever,
    pipelineRewriting stays true, and the UI shows phantom rewriting.
    """
    from eurekaclaw.ui.server import _mark_rewrite_tasks_failed

    _run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    theory = next(t for t in pipeline.tasks if t.name == "theory")
    writer = next(t for t in pipeline.tasks if t.name == "writer")
    # Simulate handler-side PENDING flip with no IN_PROGRESS transition.
    theory.status = TaskStatus.PENDING
    writer.status = TaskStatus.PENDING
    bus.put_pipeline(pipeline)

    _mark_rewrite_tasks_failed(pipeline, bus)

    refreshed = bus.get_pipeline()
    assert next(t for t in refreshed.tasks if t.name == "theory").status == TaskStatus.FAILED
    assert next(t for t in refreshed.tasks if t.name == "writer").status == TaskStatus.FAILED


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


def test_handle_stale_paper_qa_gate_noop_when_already_completed(run_with_bus):
    """Cleanup must NOT overwrite a legitimately completed gate.

    Scenario: user's Accept was processed, paper_qa_gate is COMPLETED, the
    orchestrator finished and unregistered the in-memory gate entry. A
    duplicate Accept click now fails submit_paper_qa and the cleanup helper
    runs. If the helper blindly flips the task to FAILED it corrupts a
    successful acceptance.
    """
    from eurekaclaw.ui.server import _handle_stale_paper_qa_gate

    _run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    qa = next(t for t in pipeline.tasks if t.name == "paper_qa_gate")
    qa.status = TaskStatus.COMPLETED
    bus.put_pipeline(pipeline)

    _handle_stale_paper_qa_gate(pipeline, bus, "test-rewrite-001")

    assert next(t for t in pipeline.tasks if t.name == "paper_qa_gate").status == TaskStatus.COMPLETED


def test_handle_stale_paper_qa_gate_flips_to_failed_and_persists(run_with_bus):
    """Stale-gate cleanup: AWAITING_GATE on disk with no live in-memory entry.

    When /rewrite's gate submit fails (orchestrator died / server restarted /
    gate entry cleared), the helper must flip paper_qa_gate to FAILED and
    persist the pipeline so the UI stops presenting Accept/Rewrite buttons
    and the endpoint can safely fall through to the background path.
    """
    from eurekaclaw.ui.server import _handle_stale_paper_qa_gate

    _run, bus, runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    qa = next(t for t in pipeline.tasks if t.name == "paper_qa_gate")
    qa.status = TaskStatus.AWAITING_GATE
    bus.put_pipeline(pipeline)

    _handle_stale_paper_qa_gate(pipeline, bus, "test-rewrite-001")

    # In-memory pipeline mutated.
    assert next(t for t in pipeline.tasks if t.name == "paper_qa_gate").status == TaskStatus.FAILED
    # And persisted — re-read from bus, which was persisted to runs_dir.
    reloaded_pipeline = bus.get_pipeline()
    assert next(t for t in reloaded_pipeline.tasks if t.name == "paper_qa_gate").status == TaskStatus.FAILED
    # Pipeline file on disk also shows FAILED.
    pipeline_file = runs_dir / "test-rewrite-001" / "pipeline.json"
    assert pipeline_file.exists()
    import json
    data = json.loads(pipeline_file.read_text(encoding="utf-8"))
    qa_on_disk = next(t for t in data["tasks"] if t["name"] == "paper_qa_gate")
    assert qa_on_disk["status"] == "failed"


def test_stale_paper_qa_response_accept_returns_ok():
    """Accept ('no') on a stale gate: cleanup closes the stranded UI and
    that IS what the user asked for. Success is honest."""
    from http import HTTPStatus
    from eurekaclaw.ui.server import _stale_paper_qa_response

    body, status = _stale_paper_qa_response("no")
    assert status == HTTPStatus.OK
    assert body.get("ok") is True
    assert body.get("stale_gate_cleaned") is True


def test_stale_paper_qa_response_rewrite_returns_conflict():
    """A stale-gate 'rewrite' submit did NOT queue a rewrite. Returning
    {ok:true} would lie to the client. Must return 409 so the client
    retries via the /rewrite endpoint."""
    from http import HTTPStatus
    from eurekaclaw.ui.server import _stale_paper_qa_response

    body, status = _stale_paper_qa_response("rewrite")
    assert status == HTTPStatus.CONFLICT
    assert "error" in body
    assert body.get("ok") is not True


def test_stale_paper_qa_response_unknown_action_returns_conflict():
    """Unknown / future actions: default to CONFLICT rather than silent ok."""
    from http import HTTPStatus
    from eurekaclaw.ui.server import _stale_paper_qa_response

    body, status = _stale_paper_qa_response("rebuttal")
    assert status == HTTPStatus.CONFLICT
    assert "error" in body


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


def test_claim_rewrite_slot_returns_false_on_second_call():
    """Concurrency guard: while one /rewrite bg thread is in flight for
    session X, a second /rewrite for session X must be refused.

    The status-based guard in the handler alone is insufficient — there is
    a small window between thread.start() and _do_rewrite flipping tasks
    to IN_PROGRESS where both requests would see all-COMPLETED tasks and
    both would spawn bg threads, racing on the same pipeline.
    """
    from eurekaclaw.ui.server import _claim_rewrite_slot, _release_rewrite_slot

    sid = "race-test-claim-1"
    try:
        assert _claim_rewrite_slot(sid) is True
        assert _claim_rewrite_slot(sid) is False
    finally:
        _release_rewrite_slot(sid)

    # After release, a fresh claim must succeed again.
    try:
        assert _claim_rewrite_slot(sid) is True
    finally:
        _release_rewrite_slot(sid)


def test_claim_rewrite_slot_is_per_session():
    """Claims must not cross-block unrelated sessions."""
    from eurekaclaw.ui.server import _claim_rewrite_slot, _release_rewrite_slot

    try:
        assert _claim_rewrite_slot("race-sess-A") is True
        assert _claim_rewrite_slot("race-sess-B") is True
    finally:
        _release_rewrite_slot("race-sess-A")
        _release_rewrite_slot("race-sess-B")


def test_claim_rewrite_slot_rejects_empty_session_id():
    """Empty/None session ids must not be claimable (defensive guard)."""
    from eurekaclaw.ui.server import _claim_rewrite_slot

    assert _claim_rewrite_slot("") is False


def test_run_rewrite_bg_releases_slot_on_success(run_with_bus, monkeypatch):
    """Successful bg rewrite must release the claim so a follow-up /rewrite
    can be accepted once the rewrite completes."""
    from eurekaclaw.ui import server as srv

    run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    async def _fake_do_rewrite(self, pipe, br, revision_prompt=None, writer_only=False):
        return r"\section{x} v2"

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.paper_qa_handler.PaperQAHandler._do_rewrite",
        _fake_do_rewrite,
    )
    fake_orch = MagicMock()
    for attr in ("agents", "router", "client", "tool_registry",
                 "skill_injector", "memory", "gate"):
        setattr(fake_orch, attr, MagicMock() if attr != "agents" else {})
    monkeypatch.setattr(srv, "MetaOrchestrator", MagicMock(return_value=fake_orch))
    monkeypatch.setattr(srv, "create_client", MagicMock())

    # Pre-claim the slot so we can verify the bg thread releases it.
    srv._claim_rewrite_slot(run.eureka_session_id)
    srv._run_rewrite_bg(run, bus, pipeline, brief, "tighten", "rw-rel-1")

    # After the bg thread exits, claim must be available again.
    assert srv._claim_rewrite_slot(run.eureka_session_id) is True
    srv._release_rewrite_slot(run.eureka_session_id)


def test_run_rewrite_bg_releases_slot_on_failure(run_with_bus, monkeypatch):
    """Failed bg rewrite must still release the claim (finally-path)."""
    from eurekaclaw.ui import server as srv

    run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    async def _boom(self, pipe, br, revision_prompt=None, writer_only=False):
        raise RuntimeError("simulated crash")

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

    srv._claim_rewrite_slot(run.eureka_session_id)
    srv._run_rewrite_bg(run, bus, pipeline, brief, "tighten", "rw-rel-2")

    # Even after failure, the slot must be released.
    assert srv._claim_rewrite_slot(run.eureka_session_id) is True
    srv._release_rewrite_slot(run.eureka_session_id)


def test_run_rewrite_bg_restores_bus_artifacts_on_none_return(run_with_bus, monkeypatch):
    """_do_rewrite returning None (soft failure) must not leak bus mutations.

    Theory/experiment agents write to non-task bus keys (resource_analysis,
    numerically_suspect_lemmas) that _do_rewrite's own task-output restore
    does not touch. If those mutations survive a failed rewrite, subsequent
    /rewrite or /paper-qa/ask calls read stale analysis that no longer
    matches the task outputs they coexist with.
    """
    from eurekaclaw.ui import server as srv

    run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    bus.put("resource_analysis", {"verdict": "original"})
    bus.put("numerically_suspect_lemmas", ["prev-L1"])

    async def _fake_do_rewrite(self, pipe, br, revision_prompt=None, writer_only=False):
        # Simulate theory/experiment agents mutating bus artifacts.
        self.bus.put("resource_analysis", {"verdict": "mutated-by-failed-rewrite"})
        self.bus.put("numerically_suspect_lemmas", ["mutated-L9"])
        return None  # Soft failure: no new paper.

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.paper_qa_handler.PaperQAHandler._do_rewrite",
        _fake_do_rewrite,
    )
    fake_orch = MagicMock()
    for attr in ("agents", "router", "client", "tool_registry",
                 "skill_injector", "memory", "gate"):
        setattr(fake_orch, attr, MagicMock() if attr != "agents" else {})
    monkeypatch.setattr(srv, "MetaOrchestrator", MagicMock(return_value=fake_orch))
    monkeypatch.setattr(srv, "create_client", MagicMock())

    srv._run_rewrite_bg(run, bus, pipeline, brief, "attempt", "rw-rollback-1")

    assert bus.get("resource_analysis") == {"verdict": "original"}
    assert bus.get("numerically_suspect_lemmas") == ["prev-L1"]


def test_run_rewrite_bg_restores_bus_artifacts_on_exception(run_with_bus, monkeypatch):
    """Exception path must also restore — the old /review/rewrite did a
    filesystem rollback for exactly this case."""
    from eurekaclaw.ui import server as srv

    run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    bus.put("resource_analysis", {"verdict": "original"})

    async def _boom(self, pipe, br, revision_prompt=None, writer_only=False):
        self.bus.put("resource_analysis", {"verdict": "mutated-mid-crash"})
        raise RuntimeError("crash after mutation")

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

    srv._run_rewrite_bg(run, bus, pipeline, brief, "crashy", "rw-rollback-2")

    assert bus.get("resource_analysis") == {"verdict": "original"}


def test_run_rewrite_bg_removes_newly_created_bus_artifacts_on_failure(run_with_bus, monkeypatch):
    """A failed rewrite must ALSO remove keys it newly created.

    If the pre-rewrite bus had no `resource_analysis` but the failed
    rewrite wrote one, restore-to-previous must remove the new key —
    leaving it behind means the next rewrite starts from a leaked
    partial state of the rejected attempt.
    """
    from eurekaclaw.ui import server as srv

    run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    # Ensure the key is NOT present before the rewrite.
    assert bus.get("resource_analysis") is None

    async def _fake_do_rewrite(self, pipe, br, revision_prompt=None, writer_only=False):
        # Newly create the key, then soft-fail.
        self.bus.put("resource_analysis", {"verdict": "leaked-from-failure"})
        return None

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.paper_qa_handler.PaperQAHandler._do_rewrite",
        _fake_do_rewrite,
    )
    fake_orch = MagicMock()
    for attr in ("agents", "router", "client", "tool_registry",
                 "skill_injector", "memory", "gate"):
        setattr(fake_orch, attr, MagicMock() if attr != "agents" else {})
    monkeypatch.setattr(srv, "MetaOrchestrator", MagicMock(return_value=fake_orch))
    monkeypatch.setattr(srv, "create_client", MagicMock())

    srv._run_rewrite_bg(run, bus, pipeline, brief, "leaky", "rw-leak-1")

    # Must be back to "not present", not a lingering new value.
    assert bus.get("resource_analysis") is None


def test_run_rewrite_bg_preserves_successful_bus_mutations(run_with_bus, monkeypatch):
    """On success, the agents' intended mutations MUST persist — the
    rollback logic must only fire on failure paths."""
    from eurekaclaw.ui import server as srv

    run, bus, _runs_dir = run_with_bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()

    bus.put("resource_analysis", {"verdict": "original"})

    async def _successful(self, pipe, br, revision_prompt=None, writer_only=False):
        self.bus.put("resource_analysis", {"verdict": "new-from-successful-rewrite"})
        return r"\section{new}"

    monkeypatch.setattr(
        "eurekaclaw.orchestrator.paper_qa_handler.PaperQAHandler._do_rewrite",
        _successful,
    )
    fake_orch = MagicMock()
    for attr in ("agents", "router", "client", "tool_registry",
                 "skill_injector", "memory", "gate"):
        setattr(fake_orch, attr, MagicMock() if attr != "agents" else {})
    monkeypatch.setattr(srv, "MetaOrchestrator", MagicMock(return_value=fake_orch))
    monkeypatch.setattr(srv, "create_client", MagicMock())

    srv._run_rewrite_bg(run, bus, pipeline, brief, "ok", "rw-rollback-3")

    # Successful rewrite: new artifact value must persist.
    assert bus.get("resource_analysis") == {"verdict": "new-from-successful-rewrite"}


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
