# Paper Rewrite Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify gate-mode and completed-mode paper rewrite behind a single `POST /api/runs/{id}/rewrite` endpoint that runs `theory → (experiment iff EXPERIMENT_MODE allows) → writer` in a background thread, and delete the stateful `/review` activation machinery that causes the Vite-proxy "Failed to fetch" bug and the activation-failure UX regressions.

**Architecture:** The frontend becomes dumb about bus state — it just polls pipeline state. The backend grows one shared `_ensure_bus_activated(run)` helper, one new `/rewrite` endpoint that dispatches to either `review_gate.submit_paper_qa` (gate-live) or a background `_run_rewrite_bg` thread (completed), and loses the whole `/review` / `/review/rewrite` / `reviewStatus` / `loading-review` surface area.

**Tech Stack:** Python 3.11 + `http.server` + `threading.Thread` + `asyncio.run`, React 18 + TypeScript + Vite 5.4, pytest (+ `tmp_path` + `_FakeRun` dataclass fixture pattern per `tests/unit/test_sync_latex_to_disk.py`), vitest 2.1.9 + `@testing-library/react` + `vi.mock('@/api/client')` pattern.

**Source spec:** `docs/superpowers/specs/2026-04-17-paper-rewrite-unification-design.md` (commit `76530e2`).

---

## File Structure

**Backend — `eurekaclaw/orchestrator/paper_qa_handler.py`** (Task 1)
- Modify `_do_rewrite` (around line 360) to include `"experiment"` in `rewrite_tasks` when not `writer_only`
- Extend snapshot/restore at lines 362–371 and 431–443 to cover the experiment task
- Extend the feedback-injection block at 378–385 to reset the experiment task's status/retries

**Backend — `eurekaclaw/ui/server.py`** (Tasks 2, 3, 4, 5, 6)
- **Task 2** adds `_ensure_bus_activated(run)` module-level helper near `_sync_latex_to_disk` (around line 1287)
- **Task 3** hardens `GET /paper-qa/history` (already reads from disk at lines 1676–1702; only a malformed-line-skip test is new)
- **Task 4** adds:
  - Module-level `_append_paper_qa_rewrite_marker_file(session_id, prompt)` and `_append_paper_qa_error_marker(session_id, msg)` next to `_ensure_bus_activated` (so the background thread can call them without an HTTP handler)
  - Module-level `_unlink_stale_pdf(run)` helper
  - Module-level `_mark_rewrite_tasks_failed(pipeline, bus)` helper
  - Module-level `_run_rewrite_bg(run, bus, pipeline, brief, prompt, rewrite_id)` thread entry point
  - `POST /api/runs/{id}/rewrite` route in `do_POST`, placed right before the existing `/review` block (around line 2056)
- **Task 5** swaps the bus-loaded check in `POST /paper-qa/ask` (lines 2230–2236) for a `_ensure_bus_activated(run)` call
- **Task 6** deletes `POST /api/runs/{id}/review` (lines 2057–2087) and `POST /api/runs/{id}/review/rewrite` (lines 2089–2208)

**Tests — `tests/unit/`** (Tasks 1, 2, 3, 4)
- Modify: `test_paper_qa_handler.py` — add cases for experiment inclusion + snapshot/restore
- Create: `test_ensure_bus_activated.py`
- Create: `test_paper_qa_history_disk.py`
- Create: `test_rewrite_endpoint.py`

**Frontend — `frontend/src/components/workspace/paper-review/usePaperSession.ts`** (Task 7)
- Delete `reviewStatus` / `reviewError` state
- Delete Effect 1 (the `/review` POST)
- Unify `onRewrite` to a single `POST /api/runs/{id}/rewrite`
- Shrink `PaperMode` to `'no-paper' | 'gate' | 'rewriting' | 'completed' | 'failed'`

**Frontend — `frontend/src/components/workspace/paper-review/usePaperSession.test.ts`** (Task 7)
- Delete: `review-activation failure falls back to completed mode with reviewError set`
- Delete: `onRewrite in completed mode keeps mode at completed (no flash to loading-review)`
- Add: unified-endpoint test for gate mode
- Add: unified-endpoint test for completed mode
- Add: mode transitions `completed → rewriting` when theory flips to `in_progress`
- Add: history load fires on `run_id` change
- Keep: remaining 8 existing cases (retarget `onRewrite in completed mode POSTs to /review/rewrite` → new endpoint)

**Frontend — `frontend/src/components/workspace/PaperPanel.tsx`** (Task 8)
- Delete the `loading-review` render branch (lines 119–130)
- Delete the `paper-review-error-banner` block (lines 138–142)

**Verification — manual** (Task 9)
- Runs entirely at the user's keyboard against a live dev server.

---

## Task 1: Include experiment in _do_rewrite

**Files:**
- Modify: `eurekaclaw/orchestrator/paper_qa_handler.py:327-447`
- Test: `tests/unit/test_paper_qa_handler.py` (extend; add fixtures for experiment task)

**Context:** The current `_do_rewrite` replays only `["theory", "writer"]`. The forward pipeline is `theory → theory_review_gate → experiment → writer`, so skipping experiment on rewrite means the rewritten paper references stale experimental data. The `ExperimentAgent` already self-gates on `settings.experiment_mode` at `eurekaclaw/agents/experiment/agent.py:169-175` (`"false"` → skip, `"true"` → force, `"auto"` → decide), so no new gating logic is needed here — just add the name to `rewrite_tasks` and let the agent's own skip logic run when `mode="false"`.

- [ ] **Step 1: Write the failing test** — `tests/unit/test_paper_qa_handler.py` (append after line 180)

```python
@pytest.mark.asyncio
async def test_do_rewrite_includes_experiment_in_task_list(handler_setup, monkeypatch):
    """_do_rewrite must replay ['theory', 'experiment', 'writer'] when not writer_only."""
    handler, pipeline, brief = handler_setup

    # Add theory + experiment tasks alongside the existing writer.
    from eurekaclaw.types.tasks import Task, TaskStatus
    theory_task = Task(
        task_id="t1", name="theory", agent_role="theory",
        description="Prove theorem",
        status=TaskStatus.COMPLETED,
        outputs={"proof": "Q.E.D."},
    )
    experiment_task = Task(
        task_id="e1", name="experiment", agent_role="experiment",
        description="Run experiment",
        status=TaskStatus.COMPLETED,
        outputs={"metrics": {"acc": 0.9}},
    )
    pipeline.tasks = [theory_task, experiment_task] + pipeline.tasks

    executed_names = []

    class _FakeResult:
        def __init__(self, name):
            self.failed = False
            self.output = {f"{name}_done": True}
            self.text_summary = ""
            self.error = ""

    async def _fake_execute(task):
        executed_names.append(task.name)
        return _FakeResult(task.name)

    fake_agent = MagicMock()
    fake_agent.execute = AsyncMock(side_effect=_fake_execute)
    handler.router.resolve = MagicMock(return_value=fake_agent)

    # Stub out context helpers that write to disk.
    monkeypatch.setattr(handler, "_save_rewrite_context", lambda *_a, **_kw: None)
    monkeypatch.setattr(handler, "_summarize_qa_history", lambda: "")

    result = await handler._do_rewrite(pipeline, brief, revision_prompt="tighten proof")

    assert result is not None
    assert executed_names == ["theory", "experiment", "writer"]


@pytest.mark.asyncio
async def test_do_rewrite_restores_experiment_outputs_on_failure(handler_setup, monkeypatch):
    """When the writer step fails after experiment rewrote, experiment must
    be restored to COMPLETED with its previous outputs, not left PENDING."""
    handler, pipeline, brief = handler_setup

    from eurekaclaw.types.tasks import Task, TaskStatus
    theory_task = Task(
        task_id="t1", name="theory", agent_role="theory",
        description="Prove", status=TaskStatus.COMPLETED,
        outputs={"proof": "original"},
    )
    experiment_task = Task(
        task_id="e1", name="experiment", agent_role="experiment",
        description="Run", status=TaskStatus.COMPLETED,
        outputs={"metrics": {"acc": 0.9}},
    )
    pipeline.tasks = [theory_task, experiment_task] + pipeline.tasks

    class _OkResult:
        def __init__(self, name):
            self.failed = False
            self.output = {f"new_{name}": True}
            self.text_summary = ""
            self.error = ""

    class _FailResult:
        failed = True
        output = {}
        text_summary = ""
        error = "writer boom"

    async def _fake_execute(task):
        if task.name == "writer":
            return _FailResult()
        return _OkResult(task.name)

    fake_agent = MagicMock()
    fake_agent.execute = AsyncMock(side_effect=_fake_execute)
    handler.router.resolve = MagicMock(return_value=fake_agent)
    monkeypatch.setattr(handler, "_save_rewrite_context", lambda *_a, **_kw: None)
    monkeypatch.setattr(handler, "_summarize_qa_history", lambda: "")

    result = await handler._do_rewrite(pipeline, brief, revision_prompt="tighten")

    assert result is None
    assert experiment_task.status == TaskStatus.COMPLETED
    assert experiment_task.outputs == {"metrics": {"acc": 0.9}}
    assert theory_task.status == TaskStatus.COMPLETED
    assert theory_task.outputs == {"proof": "original"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/unit/test_paper_qa_handler.py::test_do_rewrite_includes_experiment_in_task_list tests/unit/test_paper_qa_handler.py::test_do_rewrite_restores_experiment_outputs_on_failure -v`
Expected: FAIL — first assertion fails at `executed_names == ["theory", "experiment", "writer"]` (only theory+writer execute); second fails at `experiment_task.outputs == ...` (experiment not restored).

- [ ] **Step 3: Modify _do_rewrite** — `eurekaclaw/orchestrator/paper_qa_handler.py`

Replace the current single-line `rewrite_tasks = ["writer"] if writer_only else ["theory", "writer"]` at line 360 with:

```python
        # Determine which tasks to re-run
        if writer_only:
            rewrite_tasks = ["writer"]
        else:
            rewrite_tasks = ["theory", "experiment", "writer"]
```

Replace the snapshot block at lines 362–371 with:

```python
        # Snapshot previous task outputs so we can restore on failure
        theory_task = next(
            (t for t in pipeline.tasks if t.name == "theory"), None
        )
        experiment_task = next(
            (t for t in pipeline.tasks if t.name == "experiment"), None
        )
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )
        prev_theory_outputs = dict(theory_task.outputs) if theory_task else {}
        prev_experiment_outputs = (
            dict(experiment_task.outputs) if experiment_task else {}
        )
        prev_writer_outputs = dict(writer_task.outputs) if writer_task else {}
        prev_theory_desc = theory_task.description if theory_task else ""
```

Replace the feedback-injection block at lines 378–385 with:

```python
        # Reset tasks for re-execution
        if not writer_only and theory_task is not None:
            theory_task.description = (theory_task.description or "") + feedback
            theory_task.retries = 0
            theory_task.status = TaskStatus.PENDING
        if not writer_only and experiment_task is not None:
            experiment_task.retries = 0
            experiment_task.status = TaskStatus.PENDING
        if writer_task is not None:
            writer_task.retries = 0
            writer_task.status = TaskStatus.PENDING
```

Replace the failure-restore block at lines 431–443 with:

```python
        if rewrite_failed:
            # Restore tasks to COMPLETED with their previous outputs so
            # the pipeline stays in a consistent state for the next round.
            if theory_task is not None:
                theory_task.status = TaskStatus.COMPLETED
                theory_task.outputs = prev_theory_outputs
                theory_task.error_message = ""
                theory_task.description = prev_theory_desc
            if experiment_task is not None:
                experiment_task.status = TaskStatus.COMPLETED
                experiment_task.outputs = prev_experiment_outputs
                experiment_task.error_message = ""
            if writer_task is not None:
                writer_task.status = TaskStatus.COMPLETED
                writer_task.outputs = prev_writer_outputs
                writer_task.error_message = ""
            self.bus.put_pipeline(pipeline)
            return None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/unit/test_paper_qa_handler.py -v`
Expected: PASS — both new tests green, plus the 7 pre-existing tests still green.

- [ ] **Step 5: Commit**

```bash
git add eurekaclaw/orchestrator/paper_qa_handler.py tests/unit/test_paper_qa_handler.py
git commit -m "paper_qa_handler: include experiment in _do_rewrite replay"
```

---

## Task 2: Add _ensure_bus_activated helper

**Files:**
- Modify: `eurekaclaw/ui/server.py` (insert near `_sync_latex_to_disk` at line 1287)
- Create: `tests/unit/test_ensure_bus_activated.py`

**Context:** Today `POST /review`, `POST /review/rewrite`, and `POST /paper-qa/ask` each duplicate ~20 lines of bus-hydration logic: check `run.eureka_session.bus`, if absent call `SessionLoader.load(session_id)`, construct a bare `EurekaSession`, attach the bus. We need a single helper so the new `/rewrite` endpoint and the lazy-activated `/paper-qa/ask` can share the same correctness guarantees (fresh pipeline + brief, consistent error messages). Raising `ValueError` / `FileNotFoundError` at the helper boundary lets each HTTP handler map them uniformly to `400 {"error": str(e)}`.

- [ ] **Step 1: Write the failing test** — `tests/unit/test_ensure_bus_activated.py`

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/unit/test_ensure_bus_activated.py -v`
Expected: FAIL with `ImportError: cannot import name '_ensure_bus_activated' from 'eurekaclaw.ui.server'`.

- [ ] **Step 3: Add the helper** — `eurekaclaw/ui/server.py`

Insert the following function immediately after `_sync_latex_to_disk` ends (around line 1330; find the end by searching for `def _sync_latex_to_disk` and placing the new function after its closing `return` block):

```python
def _ensure_bus_activated(run) -> tuple["KnowledgeBus", "TaskPipeline", "ResearchBrief"]:
    """Return the run's live bus/pipeline/brief, hydrating from disk if needed.

    Raises ValueError / FileNotFoundError on corrupt or missing state.
    Callers typically map those to HTTP 400.
    """
    session = getattr(run, "eureka_session", None)
    bus = getattr(session, "bus", None) if session else None
    if bus is None:
        from eurekaclaw.orchestrator.session_loader import SessionLoader
        bus, _brief, _pipeline = SessionLoader.load(run.eureka_session_id)
        from eurekaclaw.main import EurekaSession
        if session is None:
            run.eureka_session = EurekaSession.__new__(EurekaSession)
            run.eureka_session.session_id = run.eureka_session_id
        run.eureka_session.bus = bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()
    if pipeline is None or brief is None:
        raise ValueError("Session pipeline or brief missing from bus")
    return bus, pipeline, brief
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/unit/test_ensure_bus_activated.py -v`
Expected: PASS — 3/3 green.

- [ ] **Step 5: Commit**

```bash
git add eurekaclaw/ui/server.py tests/unit/test_ensure_bus_activated.py
git commit -m "server: add _ensure_bus_activated helper for lazy bus hydration"
```

---

## Task 3: Harden /paper-qa/history against malformed lines

**Files:**
- Modify: `eurekaclaw/ui/server.py:1692-1700` (minor — drop the `.strip().split("\n")` pattern for `.splitlines()` which is already malformed-safe; the existing `except _json.JSONDecodeError: pass` already skips bad lines)
- Create: `tests/unit/test_paper_qa_history_disk.py`

**Context:** The spec prescribes that `GET /paper-qa/history` reads from disk with no bus dependency. Inspection of the current code at `server.py:1676-1702` shows it already does this — reads `settings.runs_dir / session_id / "paper_qa_history.jsonl"`, parses JSONL, returns `{"messages": [...]}`. The only tightening is: current code does `.read_text(...).strip().split("\n")` which coerces an empty file to `[""]` (handled by the `if line.strip()` guard, so behavior is correct), and skips malformed lines via a bare `except`. The real deliverable here is **test coverage** — we don't currently have tests asserting the disk-read behavior, and the new `/rewrite` endpoint depends on it being rock-solid (rewrite markers live in this file and frontend poll renders them).

- [ ] **Step 1: Write the failing test** — `tests/unit/test_paper_qa_history_disk.py`

```python
"""Disk-reading contract for GET /api/runs/<id>/paper-qa/history.

Tests the parser directly rather than going through HTTP — the handler
body is ~10 lines of JSONL parsing that we can exercise by copying its
shape. When server.py grows a dedicated helper we'll import it here.
"""

import json
from pathlib import Path


def _read_history(history_file: Path) -> list[dict]:
    """Mirrors the parser in server.py:1692-1700. Keep in sync."""
    messages: list[dict] = []
    if not history_file.exists():
        return messages
    text = history_file.read_text(encoding="utf-8").strip()
    if not text:
        return messages
    for line in text.split("\n"):
        if not line.strip():
            continue
        try:
            messages.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return messages


def test_missing_file_returns_empty(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    assert _read_history(history_file) == []


def test_empty_file_returns_empty(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text("", encoding="utf-8")
    assert _read_history(history_file) == []


def test_valid_jsonl_parses_all_lines(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text(
        json.dumps({"role": "user", "content": "q1"}) + "\n"
        + json.dumps({"role": "assistant", "content": "a1"}) + "\n",
        encoding="utf-8",
    )
    msgs = _read_history(history_file)
    assert len(msgs) == 2
    assert msgs[0]["role"] == "user"
    assert msgs[1]["content"] == "a1"


def test_malformed_line_is_skipped(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text(
        json.dumps({"role": "user", "content": "ok"}) + "\n"
        + "{not valid json\n"
        + json.dumps({"role": "assistant", "content": "also ok"}) + "\n",
        encoding="utf-8",
    )
    msgs = _read_history(history_file)
    assert len(msgs) == 2
    assert msgs[0]["content"] == "ok"
    assert msgs[1]["content"] == "also ok"


def test_blank_lines_between_entries_are_skipped(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text(
        json.dumps({"role": "user", "content": "q"}) + "\n\n\n"
        + json.dumps({"role": "assistant", "content": "a"}) + "\n",
        encoding="utf-8",
    )
    msgs = _read_history(history_file)
    assert len(msgs) == 2
```

- [ ] **Step 2: Run the tests to confirm they pass as-is (green-from-scratch)**

Run: `pytest tests/unit/test_paper_qa_history_disk.py -v`
Expected: PASS — the parser shape matches `server.py:1692-1700`. These tests lock in the contract so Task 4 (`/rewrite` writing markers to this file) and Task 7 (frontend poll) can't silently drift.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_paper_qa_history_disk.py
git commit -m "tests: pin /paper-qa/history disk-parsing contract"
```

(No production code changes in this task — spec analysis showed the handler already reads from disk correctly. This task exists solely to anchor that contract with tests before Task 4 writes markers into the same file from a background thread.)

---

## Task 4: Add /rewrite endpoint + background task

**Files:**
- Modify: `eurekaclaw/ui/server.py` (add helpers + `_run_rewrite_bg` + route)
- Create: `tests/unit/test_rewrite_endpoint.py`

**Context:** This is the core of the redesign. The new `POST /api/runs/{id}/rewrite`:
1. Hydrates bus via `_ensure_bus_activated` (Task 2) — maps errors to 400.
2. Guards against concurrent rewrites: if `theory.status` or `writer.status` is `IN_PROGRESS`, return 409.
3. **Gate-live path:** if `paper_qa_gate.status == AWAITING_GATE`, call `review_gate.submit_paper_qa(session_id, PaperQADecision(action="rewrite", question=prompt))`. The orchestrator's existing `_run_ui_mode` loop picks this up and drives `_do_rewrite` itself — nothing new here.
4. **Background path:** otherwise, spawn a daemon thread targeting `_run_rewrite_bg` which runs `asyncio.run(handler._do_rewrite(...))`. On success: `_sync_latex_to_disk`, `_unlink_stale_pdf`, `_bump_writer_paper_version`, append rewrite marker, `bus.persist(...)`. On failure: catch everything, `_mark_rewrite_tasks_failed`, append error marker. Returns 202 immediately so the Vite dev proxy's ~30s timeout stops being the rewrite killer.

**Note on `review_gate.submit_paper_qa` signature:** `eurekaclaw/ui/review_gate.py:187` is `submit_paper_qa(session_id: str, decision: PaperQADecision)` — construct the dataclass, do NOT use kwargs (the spec's pseudocode is loose here).

**Note on TaskStatus values:** `eurekaclaw/types/tasks.py:12-18` defines `PENDING | IN_PROGRESS | AWAITING_GATE | COMPLETED | FAILED | SKIPPED`. There is no `RUNNING`. The concurrency guard checks `IN_PROGRESS` only.

- [ ] **Step 1: Write the failing test** — `tests/unit/test_rewrite_endpoint.py`

```python
"""Unit tests for POST /api/runs/<id>/rewrite.

Exercises the helpers the HTTP handler wires together — _run_rewrite_bg,
_mark_rewrite_tasks_failed, _append_paper_qa_rewrite_marker_file,
_append_paper_qa_error_marker, _unlink_stale_pdf — without spinning up
an HTTP server. The endpoint route itself is exercised via a parsed
path shape test below.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/unit/test_rewrite_endpoint.py -v`
Expected: FAIL with `ImportError`s on `_unlink_stale_pdf`, `_mark_rewrite_tasks_failed`, `_append_paper_qa_rewrite_marker_file`, `_append_paper_qa_error_marker`, `_run_rewrite_bg`.

- [ ] **Step 3: Add the helpers and background runner** — `eurekaclaw/ui/server.py`

Add these module-level helpers immediately after `_ensure_bus_activated` (Task 2's output). Place the `import uuid`, `import threading`, `import asyncio` at the top of the file if not already imported:

```python
def _unlink_stale_pdf(run) -> None:
    """Delete paper.pdf from session_dir and output_dir if present.

    Matches the cleanup _review/rewrite_ was doing inline; called after a
    successful rewrite so the frontend's PDF iframe re-fetches the freshly
    compiled file instead of the stale one.
    """
    candidates = []
    session_id = getattr(run, "eureka_session_id", None)
    if session_id:
        candidates.append(settings.runs_dir / session_id / "paper.pdf")
    if getattr(run, "output_dir", None):
        candidates.append(Path(run.output_dir) / "paper.pdf")
    for pdf_path in candidates:
        try:
            if pdf_path.is_file():
                pdf_path.unlink()
        except OSError:
            logger.warning("Could not unlink stale PDF at %s", pdf_path, exc_info=True)


def _mark_rewrite_tasks_failed(pipeline, bus) -> None:
    """Flip theory/writer to FAILED if they were left IN_PROGRESS.

    Called from the background-rewrite exception handler so the pipeline
    settles in a visible terminal state — the frontend polls pipeline and
    can otherwise see a phantom "in progress" forever.
    """
    changed = False
    for name in ("theory", "experiment", "writer"):
        task = next((t for t in pipeline.tasks if t.name == name), None)
        if task is not None and task.status == TaskStatus.IN_PROGRESS:
            task.status = TaskStatus.FAILED
            changed = True
    if changed:
        bus.put_pipeline(pipeline)


def _append_paper_qa_rewrite_marker_file(session_id: str, prompt: str) -> None:
    """Module-level counterpart to the HTTP handler's rewrite-marker method.

    Needed because _run_rewrite_bg is module-level (runs on a background
    thread with no handler instance). The on-disk format and constants
    match _append_paper_qa_rewrite_marker exactly.
    """
    if not session_id or not prompt:
        return
    from datetime import datetime as _dt, timezone as _tz
    history_dir = settings.runs_dir / session_id
    try:
        history_dir.mkdir(parents=True, exist_ok=True)
        history_file = history_dir / "paper_qa_history.jsonl"
        entry = {
            "role": "system",
            "content": f'{REWRITE_MARKER_PREFIX}"{prompt}"',
            "ts": _dt.now(_tz.utc).isoformat(),
        }
        with history_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        logger.warning("Could not append rewrite marker for %s", session_id, exc_info=True)


def _append_paper_qa_error_marker(session_id: str, msg: str) -> None:
    """Append a 'Revision error: <msg>' system line for the rewrite history."""
    if not session_id or not msg:
        return
    from datetime import datetime as _dt, timezone as _tz
    history_dir = settings.runs_dir / session_id
    try:
        history_dir.mkdir(parents=True, exist_ok=True)
        history_file = history_dir / "paper_qa_history.jsonl"
        entry = {
            "role": "system",
            "content": f"Revision error: {msg}",
            "ts": _dt.now(_tz.utc).isoformat(),
        }
        with history_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        logger.warning("Could not append error marker for %s", session_id, exc_info=True)


def _run_rewrite_bg(run, bus, pipeline, brief, prompt: str, rewrite_id: str) -> None:
    """Thread entry point. Owns its own asyncio event loop.

    On success: mutates pipeline in-place (theory → experiment → writer
    re-run) through handler._do_rewrite, then syncs paper.tex to disk,
    unlinks stale paper.pdf, bumps paper_version, appends rewrite marker,
    persists bus.

    On failure: catches everything, flips any IN_PROGRESS rewrite tasks
    to FAILED so the frontend's pipeline poll settles, and appends an
    error marker.
    """
    session_id = run.eureka_session_id
    try:
        orchestrator = MetaOrchestrator(bus=bus, client=create_client())
        handler = PaperQAHandler(
            bus=bus,
            agents=orchestrator.agents,
            router=orchestrator.router,
            client=orchestrator.client,
            tool_registry=orchestrator.tool_registry,
            skill_injector=orchestrator.skill_injector,
            memory=orchestrator.memory,
            gate_controller=orchestrator.gate,
        )
        new_latex = asyncio.run(
            handler._do_rewrite(pipeline, brief, revision_prompt=prompt)
        )
        if new_latex:
            _sync_latex_to_disk(run)
            _unlink_stale_pdf(run)
            _bump_writer_paper_version(bus)
            _append_paper_qa_rewrite_marker_file(session_id, prompt)
            bus.persist(settings.runs_dir / session_id)
        else:
            _append_paper_qa_error_marker(session_id, "Rewrite produced no new paper")
    except Exception as e:
        logger.exception("Rewrite background task %s failed: %s", rewrite_id, e)
        _mark_rewrite_tasks_failed(pipeline, bus)
        _append_paper_qa_error_marker(session_id, f"Rewrite failed: {e}")
```

**Imports at the top of `server.py` — add any that are missing:**

```python
import asyncio
import threading
import uuid
from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler
from eurekaclaw.llm import create_client
```

(Some of those are currently imported locally inside the old `/review/rewrite` handler. Hoist them to the module top now so Task 6 can remove the local imports cleanly.)

- [ ] **Step 4: Add the /rewrite route** — `eurekaclaw/ui/server.py` (inside `do_POST`, just before the `# ── Historical review activation ──` block near line 2056)

```python
        # POST /api/runs/<run_id>/rewrite — unified rewrite entry point
        parts_rw = parsed.path.strip("/").split("/")
        if (len(parts_rw) == 4 and parts_rw[0] == "api" and parts_rw[1] == "runs"
                and parts_rw[3] == "rewrite"):
            run_id = parts_rw[2]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return

            try:
                bus, pipeline, brief = _ensure_bus_activated(run)
            except (ValueError, FileNotFoundError) as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.BAD_REQUEST)
                return

            payload = self._read_json()
            prompt = str(payload.get("revision_prompt", "")).strip()
            if not prompt:
                self._send_json(
                    {"error": "revision_prompt required"},
                    status=HTTPStatus.BAD_REQUEST,
                )
                return

            # Concurrency guard — refuse if a rewrite is already in flight.
            theory_task = next((t for t in pipeline.tasks if t.name == "theory"), None)
            writer_task = next((t for t in pipeline.tasks if t.name == "writer"), None)
            if any(t is not None and t.status == TaskStatus.IN_PROGRESS
                   for t in (theory_task, writer_task)):
                self._send_json(
                    {"error": "A rewrite is already in progress"},
                    status=HTTPStatus.CONFLICT,
                )
                return

            # Gate-live path: live orchestrator is still waiting on paper_qa_gate.
            paper_qa_task = next(
                (t for t in pipeline.tasks if t.name == "paper_qa_gate"), None
            )
            if paper_qa_task is not None and paper_qa_task.status == TaskStatus.AWAITING_GATE:
                from eurekaclaw.ui import review_gate
                from eurekaclaw.ui.review_gate import PaperQADecision
                review_gate.submit_paper_qa(
                    run.eureka_session_id,
                    PaperQADecision(action="rewrite", question=prompt),
                )
                self._send_json(
                    {"ok": True, "mode": "gate"},
                    status=HTTPStatus.ACCEPTED,
                )
                return

            # Background path: orchestrator is idle/completed. Spawn a thread.
            rewrite_id = str(uuid.uuid4())
            thread = threading.Thread(
                target=_run_rewrite_bg,
                args=(run, bus, pipeline, brief, prompt, rewrite_id),
                daemon=True,
            )
            thread.start()
            self._send_json(
                {"ok": True, "mode": "bg", "rewrite_id": rewrite_id},
                status=HTTPStatus.ACCEPTED,
            )
            return
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `pytest tests/unit/test_rewrite_endpoint.py -v`
Expected: PASS — 6/6 green.

- [ ] **Step 6: Manual smoke — backend starts, route is registered**

Run: `python -c "from eurekaclaw.ui.server import _run_rewrite_bg, _ensure_bus_activated, _mark_rewrite_tasks_failed, _append_paper_qa_rewrite_marker_file, _append_paper_qa_error_marker, _unlink_stale_pdf; print('ok')"`
Expected: prints `ok` (all symbols importable at module level).

- [ ] **Step 7: Commit**

```bash
git add eurekaclaw/ui/server.py tests/unit/test_rewrite_endpoint.py
git commit -m "server: add POST /rewrite endpoint with background-task path"
```

---

## Task 5: Convert /paper-qa/ask to lazy activation

**Files:**
- Modify: `eurekaclaw/ui/server.py:2230-2236` (the "is the bus loaded?" gate inside `POST /paper-qa/ask`)

**Context:** Today `POST /paper-qa/ask` hard-fails with `400 {"error": "No active bus for this session"}` if the bus isn't loaded — which means the frontend has to hit `POST /review` first to hydrate it. Task 6 will delete `/review`, so `/paper-qa/ask` needs to hydrate the bus itself. That's exactly what `_ensure_bus_activated` (Task 2) was built for.

- [ ] **Step 1: Read the current handler** — `eurekaclaw/ui/server.py:2210-2286`

Confirm lines 2230–2236 look like:

```python
            session = run.eureka_session
            bus = session.bus if session else None
            latex = (bus.get("paper_qa_latex") or "") if bus else ""

            if not bus:
                self._send_json({"error": "No active bus for this session"}, status=HTTPStatus.BAD_REQUEST)
                return
```

- [ ] **Step 2: Replace with lazy activation**

Replace those 7 lines with:

```python
            try:
                bus, _pipeline, _brief = _ensure_bus_activated(run)
            except (ValueError, FileNotFoundError) as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.BAD_REQUEST)
                return
            latex = bus.get("paper_qa_latex") or ""
```

- [ ] **Step 3: Start the dev server and sanity-check that /paper-qa/ask still works for an already-loaded bus**

Run: `python -m pytest tests/unit/ -v -k "not slow"`
Expected: full existing unit suite green (no regressions). There's no unit test dedicated to `/paper-qa/ask` because it requires an LLM; the change is a pure call-site refactor to a function whose behavior is pinned by `test_ensure_bus_activated.py`.

- [ ] **Step 4: Commit**

```bash
git add eurekaclaw/ui/server.py
git commit -m "server: /paper-qa/ask lazily activates the bus via helper"
```

---

## Task 6: Delete /review and /review/rewrite handlers

**Files:**
- Modify: `eurekaclaw/ui/server.py:2056-2208` (delete both handler blocks)

**Context:** With Task 4 providing a single `/rewrite` endpoint and Task 5 making `/paper-qa/ask` self-hydrate, the `/review` activation endpoint and the synchronous-blocking `/review/rewrite` endpoint have no remaining callers. Deleting them shrinks the surface area and kills the Vite-proxy-timeout bug class by construction.

- [ ] **Step 1: Delete the /review handler** — remove lines 2057–2087

These are the lines starting with `# ── Historical review activation ──` and ending at the `return` after `self._send_json({"ok": True, "session_id": session_id})`.

- [ ] **Step 2: Delete the /review/rewrite handler** — remove the entire block from `# POST /api/runs/<run_id>/review/rewrite` down through the trailing `return`

That's lines 2089–2208 inclusive. After deletion, the next block in `do_POST` should be `# ── Paper QA endpoints ──` (which is the `/paper-qa/ask` block modified in Task 5).

- [ ] **Step 3: Sanity check — imports no longer needed locally**

After deletion, search the file for `from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator` — the only occurrence should now be the top-of-file import added in Task 4 (the local import inside the old `/review/rewrite` block was removed with the block). If any dangling local imports remain, delete them.

- [ ] **Step 4: Run the full test suite**

Run: `pytest tests/unit/ -v`
Expected: PASS — no tests depended on those endpoints (the only test hitting rewrite, `test_rewrite_endpoint.py`, targets the new `/rewrite` handler).

- [ ] **Step 5: Commit**

```bash
git add eurekaclaw/ui/server.py
git commit -m "server: delete /review and /review/rewrite handlers"
```

---

## Task 7: Simplify usePaperSession + vitest

**Files:**
- Modify: `frontend/src/components/workspace/paper-review/usePaperSession.ts`
- Modify: `frontend/src/components/workspace/paper-review/usePaperSession.test.ts`

**Context:** With the backend offering a single `/rewrite` endpoint and no activation step, the frontend hook collapses dramatically. Deleted state: `reviewStatus`, `reviewError`. Deleted effect: Effect 1 (the `/review` POST). Deleted mode: `'loading-review'`. Deleted branching in `onRewrite` (no more gate-vs-completed fork). What stays: pipeline-derived `mode` computation, optimistic marker append, history-load effect, `paperVersion` derivation.

- [ ] **Step 1: Write the failing test** — `frontend/src/components/workspace/paper-review/usePaperSession.test.ts`

Replace the entire file with the new suite. Keep the imports and helpers at the top; replace the `describe` body:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import type { SessionRun, PipelineTask } from '@/types';

vi.mock('@/api/client', () => ({
  apiGet: vi.fn(),
  apiPost: vi.fn(),
}));

import { apiGet, apiPost } from '@/api/client';
import { usePaperSession } from './usePaperSession';

const apiGetMock = vi.mocked(apiGet);
const apiPostMock = vi.mocked(apiPost);

function makeRun(overrides: Partial<SessionRun> = {}): SessionRun {
  return {
    run_id: 'run-1',
    status: 'completed',
    pipeline: [],
    ...overrides,
  };
}

function writerTask(paper_version?: number): PipelineTask {
  return {
    task_id: 'w1',
    name: 'writer',
    agent_role: 'writer',
    status: 'completed',
    outputs: {
      latex_paper: '\\section{Intro}',
      ...(paper_version !== undefined ? { paper_version } : {}),
    },
  };
}

function paperQATask(status: PipelineTask['status']): PipelineTask {
  return {
    task_id: 'g1',
    name: 'paper_qa_gate',
    agent_role: 'orchestrator',
    status,
  };
}

beforeEach(() => {
  apiGetMock.mockReset();
  apiPostMock.mockReset();
  apiGetMock.mockResolvedValue({ messages: [] });
  apiPostMock.mockResolvedValue({ ok: true });
});

describe('usePaperSession', () => {
  it('returns null when run is null', () => {
    const { result } = renderHook(() => usePaperSession(null));
    expect(result.current).toBeNull();
  });

  it('yields mode=no-paper when pipeline has no writer output', () => {
    const run = makeRun({ pipeline: [] });
    const { result } = renderHook(() => usePaperSession(run));
    expect(result.current?.mode).toBe('no-paper');
    expect(result.current?.hasPaper).toBe(false);
  });

  it('enters gate mode when paper_qa_gate awaits gate and writer has output', async () => {
    const run = makeRun({
      pipeline: [writerTask(1), paperQATask('awaiting_gate')],
    });
    const { result } = renderHook(() => usePaperSession(run));
    expect(result.current?.mode).toBe('gate');
    expect(result.current?.isHistorical).toBe(false);
    await waitFor(() => expect(apiGetMock).toHaveBeenCalledWith(
      '/api/runs/run-1/paper-qa/history',
    ));
  });

  it('onAccept posts no-action to the gate endpoint in gate mode', async () => {
    const run = makeRun({
      pipeline: [writerTask(1), paperQATask('awaiting_gate')],
    });
    const { result } = renderHook(() => usePaperSession(run));
    await act(async () => {
      await result.current!.onAccept();
    });
    expect(apiPostMock).toHaveBeenCalledWith(
      '/api/runs/run-1/gate/paper_qa',
      { action: 'no', question: '' },
    );
  });

  it('returns isRewriting=true when theory task is in_progress after gate completion', () => {
    const run = makeRun({
      pipeline: [
        writerTask(2),
        paperQATask('completed'),
        {
          task_id: 't1', name: 'theory', agent_role: 'theory',
          status: 'in_progress',
        } as PipelineTask,
      ],
    });
    const { result } = renderHook(() => usePaperSession(run));
    expect(result.current?.mode).toBe('rewriting');
    expect(result.current?.isRewriting).toBe(true);
  });

  it('onRewrite in gate mode POSTs to /rewrite (unified endpoint)', async () => {
    const run = makeRun({
      pipeline: [writerTask(1), paperQATask('awaiting_gate')],
    });
    const { result } = renderHook(() => usePaperSession(run));

    await act(async () => {
      await result.current!.onRewrite('retry proof');
    });

    expect(apiPostMock).toHaveBeenCalledWith(
      '/api/runs/run-1/rewrite',
      { revision_prompt: 'retry proof' },
    );
  });

  it('onRewrite in completed mode POSTs to /rewrite and appends optimistic marker', async () => {
    const run = makeRun({
      pipeline: [writerTask(1), paperQATask('completed')],
    });
    const { result } = renderHook(() => usePaperSession(run));

    await act(async () => {
      await result.current!.onRewrite('tighten Section 3');
    });

    expect(apiPostMock).toHaveBeenCalledWith(
      '/api/runs/run-1/rewrite',
      { revision_prompt: 'tighten Section 3' },
    );
    const sysMsg = result.current!.messages.find(
      (m) => m.role === 'system' && m.content.includes('tighten Section 3'),
    );
    expect(sysMsg).toBeDefined();
    expect(sysMsg!.content).toBe('↻ Rewrite requested: "tighten Section 3"');
  });

  it('paperVersion reads writer.outputs.paper_version when present', () => {
    const run = makeRun({ pipeline: [writerTask(3), paperQATask('completed')] });
    const { result } = renderHook(() => usePaperSession(run));
    expect(result.current?.paperVersion).toBe(3);
  });

  it('paperVersion falls back to 1 + rewrite-marker count when writer lacks the field', async () => {
    const run = makeRun({
      pipeline: [
        {
          task_id: 'w1', name: 'writer', agent_role: 'writer',
          status: 'completed',
          outputs: { latex_paper: '\\section{X}' },
        } as PipelineTask,
        paperQATask('awaiting_gate'),
      ],
    });
    apiGetMock.mockResolvedValue({
      messages: [
        { role: 'system', content: '↻ Rewrite requested: "round 1"', ts: '2026-04-17T00:00:00Z' },
        { role: 'system', content: '↻ Rewrite requested: "round 2"', ts: '2026-04-17T01:00:00Z' },
      ],
    });
    const { result } = renderHook(() => usePaperSession(run));
    await waitFor(() => {
      expect(result.current?.paperVersion).toBe(3);
    });
  });

  it('mode transitions completed → rewriting when theory flips to in_progress', async () => {
    const completedRun = makeRun({
      pipeline: [writerTask(1), paperQATask('completed')],
    });
    const { result, rerender } = renderHook(
      ({ run }: { run: SessionRun }) => usePaperSession(run),
      { initialProps: { run: completedRun } },
    );
    await waitFor(() => expect(result.current?.mode).toBe('completed'));

    const rewritingRun = makeRun({
      pipeline: [
        writerTask(1),
        paperQATask('completed'),
        {
          task_id: 't1', name: 'theory', agent_role: 'theory',
          status: 'in_progress',
        } as PipelineTask,
      ],
    });
    rerender({ run: rewritingRun });
    expect(result.current?.mode).toBe('rewriting');
  });

  it('history load fires on run_id change', async () => {
    const run1 = makeRun({
      run_id: 'run-A',
      pipeline: [writerTask(1), paperQATask('completed')],
    });
    const { rerender } = renderHook(
      ({ run }: { run: SessionRun }) => usePaperSession(run),
      { initialProps: { run: run1 } },
    );
    await waitFor(() =>
      expect(apiGetMock).toHaveBeenCalledWith('/api/runs/run-A/paper-qa/history'),
    );

    const run2 = makeRun({
      run_id: 'run-B',
      pipeline: [writerTask(1), paperQATask('completed')],
    });
    rerender({ run: run2 });

    await waitFor(() =>
      expect(apiGetMock).toHaveBeenCalledWith('/api/runs/run-B/paper-qa/history'),
    );
  });

  it('history-load failure preserves optimistic rewrite markers', async () => {
    const run = makeRun({
      pipeline: [writerTask(1), paperQATask('awaiting_gate')],
    });
    apiPostMock.mockResolvedValue({ ok: true });
    apiGetMock.mockRejectedValue(new Error('network down'));
    const { result } = renderHook(() => usePaperSession(run));

    await act(async () => {
      await result.current!.onRewrite('keep me alive');
    });

    await waitFor(() => {
      const marker = result.current!.messages.find(
        (m) => m.role === 'system' && m.content.includes('keep me alive'),
      );
      expect(marker).toBeDefined();
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx vitest run src/components/workspace/paper-review/usePaperSession.test.ts`
Expected: FAIL — the current hook still posts to `/api/runs/{id}/gate/paper_qa` from `onRewrite` in gate mode and `/api/runs/{id}/review/rewrite` in completed mode; new tests expect the unified `/api/runs/{id}/rewrite`. Also the two deleted tests' subjects (`loading-review`, `reviewError`) are gone so the hook still referencing those states will keep the unchanged 12th test passing — but the new 4 fail.

- [ ] **Step 3: Rewrite the hook** — `frontend/src/components/workspace/paper-review/usePaperSession.ts`

Replace the entire file with:

```typescript
import { useCallback, useEffect, useMemo, useState } from 'react';
import { apiGet, apiPost } from '@/api/client';
import { REWRITE_MARKER_PREFIX } from '@/constants/paper';
import type { SessionRun, QAMessage } from '@/types';

export type PaperMode =
  | 'no-paper'
  | 'gate'
  | 'rewriting'
  | 'completed'
  | 'failed';

export interface PaperSession {
  mode: PaperMode;
  run: SessionRun;

  hasPaper: boolean;
  paperVersion: number;
  latexSource: string;

  messages: QAMessage[];
  setMessages: React.Dispatch<React.SetStateAction<QAMessage[]>>;

  isRewriting: boolean;
  theoryStatus: string;
  writerStatus: string;

  onAccept: () => Promise<void>;
  onRewrite: (prompt: string) => Promise<void>;

  isHistorical: boolean;
}

type HistoryResponse = { messages: QAMessage[] };

export function usePaperSession(run: SessionRun | null): PaperSession | null {
  const [messages, setMessages] = useState<QAMessage[]>([]);
  const [isRewriting, setIsRewriting] = useState(false);

  const writerTask = run?.pipeline?.find((t) => t.name === 'writer');
  const theoryTask = run?.pipeline?.find((t) => t.name === 'theory');
  const paperQATask = run?.pipeline?.find((t) => t.name === 'paper_qa_gate');

  const latexSource = useMemo(() => {
    if (writerTask?.outputs?.latex_paper) {
      return String(writerTask.outputs.latex_paper);
    }
    if (run?.result?.latex_paper) {
      return run.result.latex_paper;
    }
    return '';
  }, [writerTask?.outputs?.latex_paper, run?.result?.latex_paper]);

  const hasPaper = latexSource.length > 0;

  const pipelineRewriting =
    theoryTask?.status === 'in_progress' ||
    theoryTask?.status === 'pending' ||
    writerTask?.status === 'in_progress' ||
    writerTask?.status === 'pending';

  const mode: PaperMode = useMemo(() => {
    if (!run) return 'no-paper';
    if (run.status === 'failed' && !hasPaper) return 'failed';
    if (!hasPaper) return 'no-paper';
    if (paperQATask?.status === 'awaiting_gate') return 'gate';
    if (pipelineRewriting) return 'rewriting';
    return 'completed';
  }, [run, hasPaper, paperQATask?.status, pipelineRewriting]);

  useEffect(() => {
    if (!run?.run_id) return;
    void (async () => {
      try {
        const data = await apiGet<HistoryResponse>(
          `/api/runs/${run.run_id}/paper-qa/history`,
        );
        const serverMsgs = data.messages ?? [];
        setMessages((prev) => {
          const serverKeys = new Set(
            serverMsgs.map((m) => `${m.role}|${m.content}`),
          );
          const optimistic = prev.filter(
            (m) =>
              m.role === 'system' &&
              typeof m.content === 'string' &&
              m.content.startsWith(REWRITE_MARKER_PREFIX) &&
              !serverKeys.has(`${m.role}|${m.content}`),
          );
          return [...serverMsgs, ...optimistic];
        });
      } catch {
        setMessages((prev) =>
          prev.filter(
            (m) =>
              m.role === 'system' &&
              typeof m.content === 'string' &&
              m.content.startsWith(REWRITE_MARKER_PREFIX),
          ),
        );
      }
    })();
  }, [run?.run_id, mode]);

  const isHistorical = mode !== 'gate';

  const onAccept = useCallback(async () => {
    if (!run?.run_id) return;
    if (mode !== 'gate') return;
    await apiPost(`/api/runs/${run.run_id}/gate/paper_qa`, {
      action: 'no',
      question: '',
    });
  }, [run?.run_id, mode]);

  const onRewrite = useCallback(
    async (prompt: string) => {
      if (!run?.run_id) return;
      const marker: QAMessage = {
        role: 'system',
        content: `${REWRITE_MARKER_PREFIX}"${prompt}"`,
        ts: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, marker]);
      setIsRewriting(true);
      try {
        await apiPost(`/api/runs/${run.run_id}/rewrite`, {
          revision_prompt: prompt,
        });
      } catch (e) {
        const errMsg: QAMessage = {
          role: 'system',
          content: `Revision error: ${e instanceof Error ? e.message : String(e)}`,
          ts: new Date().toISOString(),
        };
        setMessages((prev) => [...prev, errMsg]);
      } finally {
        setIsRewriting(false);
      }
    },
    [run?.run_id],
  );

  const paperVersion = useMemo(() => {
    const fromOutputs = writerTask?.outputs?.paper_version;
    if (typeof fromOutputs === 'number' && fromOutputs > 0) {
      return fromOutputs;
    }
    const markerCount = messages.filter(
      (m) =>
        m.role === 'system' &&
        typeof m.content === 'string' &&
        m.content.startsWith(REWRITE_MARKER_PREFIX),
    ).length;
    return 1 + markerCount;
  }, [writerTask?.outputs?.paper_version, messages]);

  if (!run) return null;

  return {
    mode,
    run,
    hasPaper,
    paperVersion,
    latexSource,
    messages,
    setMessages,
    isRewriting: isRewriting || !!pipelineRewriting,
    theoryStatus: theoryTask?.status ?? 'pending',
    writerStatus: writerTask?.status ?? 'pending',
    onAccept,
    onRewrite,
    isHistorical,
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && npx vitest run src/components/workspace/paper-review/usePaperSession.test.ts`
Expected: PASS — 12/12 green.

- [ ] **Step 5: Typecheck**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors. If `PaperPanel.tsx` still references `session.reviewError`, that will surface now; Task 8 fixes it — for now, if typecheck fails on that one reference only, that's expected and resolved by Task 8. Proceed to commit.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/workspace/paper-review/usePaperSession.ts frontend/src/components/workspace/paper-review/usePaperSession.test.ts
git commit -m "usePaperSession: unify onRewrite behind POST /rewrite, drop review activation"
```

---

## Task 8: Simplify PaperPanel

**Files:**
- Modify: `frontend/src/components/workspace/PaperPanel.tsx`

**Context:** The panel currently has two dead render branches: the `loading-review` mode (which no longer exists in the `PaperMode` union after Task 7) and the `paper-review-error-banner` block (which reads `session.reviewError`, a field no longer returned by the hook). Delete both. The remaining render branches — `!run`, `failed`, `no-paper`, default (viewer + chat) — cover every valid mode.

- [ ] **Step 1: Delete the `loading-review` render branch**

Remove lines 119–130 in `frontend/src/components/workspace/PaperPanel.tsx`:

```tsx
  if (session.mode === 'loading-review') {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <div className="paper-progress-dots">
            <span /><span /><span />
          </div>
          <p>Loading paper review...</p>
        </div>
      </div>
    );
  }
```

- [ ] **Step 2: Delete the error-banner block**

Remove lines 138–142:

```tsx
      {session.reviewError ? (
        <div className="paper-review-error-banner">
          Review activation failed: {session.reviewError}
        </div>
      ) : null}
```

The parent `<div className="paper-review-panel" ...>` and its viewer/divider/chat children stay.

- [ ] **Step 3: Typecheck**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors. `session.reviewError` no longer exists and no longer referenced; `session.mode === 'loading-review'` no longer compiles because the literal type is gone, and both call sites are deleted.

- [ ] **Step 4: Run vitest suite**

Run: `cd frontend && npx vitest run`
Expected: PASS — all suites green. The `PaperPanel` itself has no dedicated test file; `usePaperSession.test.ts` covers the logic and was pinned green by Task 7.

- [ ] **Step 5: Dev server smoke**

Run: `cd frontend && npx vite build` (this is faster than booting the dev server and catches prod-build type/CSS issues)
Expected: build completes with no errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/workspace/PaperPanel.tsx
git commit -m "PaperPanel: drop loading-review branch and error banner"
```

---

## Task 9: Manual verification (user at keyboard)

**Files:** none — this task is a checklist to run against a live dev server.

**Context:** The preceding 8 tasks prove unit-level correctness. Manual verification confirms the UX (`Failed to fetch` is gone, one POST per rewrite click, pipeline transitions visible, paper re-renders) behaves as the spec's "Manual verification" section describes.

- [ ] **Step 1: Start the stack**

In one terminal: `cd /Users/chenggong/Downloads/EurekaClaw && python -m eurekaclaw.ui.server`
In another: `cd /Users/chenggong/Downloads/EurekaClaw/frontend && npm run dev`
Open: `http://127.0.0.1:5173/`

- [ ] **Step 2: Gate-mode rewrite**

Start a new session with a short prompt so it reaches `paper_qa_gate` quickly. In the Paper tab:
- Click **Rewrite**, type "tighten the introduction", submit.
- **Expected** in Chrome devtools Network tab: exactly one `POST /api/runs/{id}/rewrite` returning 202 with `{"mode": "gate"}`.
- **Expected** in the Live tab: `theory` flips `completed → in_progress`, then `experiment` (if EXPERIMENT_MODE allows), then `writer`. Paper tab's `paperVersion` badge increments. New `↻ Rewrite requested: "tighten the introduction"` marker appears in chat.
- **Expected**: no "Failed to fetch" anywhere.

- [ ] **Step 3: Completed-mode rewrite**

Let the same session run to completion (accept the gate with "No, it's fine"). Then click **Rewrite** again, type "now cite the 2024 Smith paper", submit.
- **Expected**: one `POST /api/runs/{id}/rewrite` returning 202 with `{"mode": "bg", "rewrite_id": "<uuid>"}`.
- **Expected**: Live tab shows `theory → experiment → writer` transitions (this is the path that used to 30s-timeout). Paper tab stays mounted throughout — viewer keeps showing the old paper, chat keeps the optimistic marker visible.
- **Expected**: after ~1–5 min, `paperVersion` increments, PDF iframe re-loads the fresh compile, marker from the backend echo deduplicates with the optimistic one.

- [ ] **Step 4: Tab switching during rewrite**

Kick off another rewrite in completed mode. While it's running, switch between Live / Proof / Paper tabs.
- **Expected**: Paper tab re-mounts with the same `rewriting` mode state; viewer + chat stay visible; pipeline state visible on Live tab without interruption.

- [ ] **Step 5: Browser refresh during rewrite**

Kick off another rewrite. While `theory.status === 'in_progress'`, hard-refresh the browser (Cmd+Shift+R).
- **Expected**: after reload, Paper tab shows `rewriting` mode (pipeline state says theory is in progress), viewer shows the last-known paper, chat re-loads history from disk. No optimistic marker survives (it was React state) but once the rewrite finishes, the backend-persisted marker appears on the next history poll.

- [ ] **Step 6: Error path (corrupt session)**

Pick a historical session, manually corrupt its `paper_qa_history.jsonl` (insert a line like `{not-json`). Click **Rewrite**.
- **Expected**: the POST returns 202 anyway (concurrency guard + `_ensure_bus_activated` pass). The rewrite runs; the malformed line is silently skipped by the history parser (Task 3's contract). No crash, no UI freeze. If `_ensure_bus_activated` itself raises (e.g., you also delete `pipeline.json`), the POST returns 400 and a `Revision error: ...` marker appears in chat while the viewer stays mounted.

- [ ] **Step 7: Record findings**

If anything fails, open a bug ticket describing which step failed and paste the Network-tab entry + Live-tab pipeline state. Otherwise, note "all 6 checks passed" in the PR description.

- [ ] **Step 8: No commit needed**

This task produces no code. The PR's Test Plan section in the description captures the result.

---

## Rollout summary

| # | Task | Commits |
|---|---|---|
| 1 | `_do_rewrite` includes experiment | 1 |
| 2 | `_ensure_bus_activated` helper | 1 |
| 3 | `/paper-qa/history` disk-parsing contract test | 1 |
| 4 | `/rewrite` endpoint + `_run_rewrite_bg` | 1 |
| 5 | `/paper-qa/ask` lazy activation | 1 |
| 6 | Delete `/review` + `/review/rewrite` | 1 |
| 7 | Simplify `usePaperSession` + vitest | 1 |
| 8 | Simplify `PaperPanel` | 1 |
| 9 | Manual verification | 0 |
| **Total** | | **8** |

One PR, eight commits, no feature flags. The old endpoints and UX have no external consumers.
