# Historical Session QA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable users to review, QA, and rewrite papers from completed sessions via CLI (`eurekaclaw sessions`, `eurekaclaw review`) and UI ("Review Paper" button).

**Architecture:** New `SessionLoader` module reconstructs a `KnowledgeBus` from disk artifacts. `PaperQAHandler` gains a `run_historical()` method that skips the gate prompt and enters the review loop directly. Two new CLI commands and two new server endpoints expose the feature. Frontend adds a "Review Paper" button on PaperPanel and a `reviewSessionId` flag in the UI store.

**Tech Stack:** Python 3.11, Click (CLI), Rich (tables), React 18, TypeScript, Zustand

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `eurekaclaw/orchestrator/session_loader.py` | Create | Reconstruct bus + artifacts from disk |
| `tests/unit/test_session_loader.py` | Create | Unit tests for session loading |
| `eurekaclaw/orchestrator/paper_qa_handler.py` | Modify | Add `run_historical()` method |
| `eurekaclaw/cli.py` | Modify | Add `sessions` and `review` subcommands |
| `eurekaclaw/ui/server.py` | Modify | Add `/review` and `/review/rewrite` endpoints |
| `frontend/src/store/uiStore.ts` | Modify | Add `reviewSessionId` state |
| `frontend/src/components/workspace/PaperPanel.tsx` | Modify | Add "Review Paper" button |
| `frontend/src/components/workspace/WorkspaceTabs.tsx` | Modify | Add `reviewModeActive` condition |
| `frontend/src/components/workspace/paper-review/PaperReviewPanel.tsx` | Modify | Handle historical mode |
| `frontend/src/components/workspace/paper-review/QAChat.tsx` | Modify | Conditional label/action for historical mode |
| `frontend/src/styles/paper-review.css` | Modify | Style for review button |

---

### Task 1: SessionLoader — Tests

**Files:**
- Create: `tests/unit/test_session_loader.py`

- [ ] **Step 1: Write tests for SessionLoader**

```python
"""Unit tests for SessionLoader — reconstruct session from disk."""

import json
import pytest
from pathlib import Path

from eurekaclaw.orchestrator.session_loader import SessionLoader


@pytest.fixture
def mock_session_dir(tmp_path, monkeypatch):
    """Create a fake session directory with persisted artifacts."""
    from eurekaclaw.config import settings
    monkeypatch.setattr(settings, "runs_dir", tmp_path)

    session_id = "test-session-001"
    session_dir = tmp_path / session_id
    session_dir.mkdir()

    # Research brief
    brief = {
        "session_id": session_id,
        "input_mode": "detailed",
        "domain": "spectral_graph",
        "query": "Convergence of spectral methods",
    }
    (session_dir / "research_brief.json").write_text(json.dumps(brief))

    # Pipeline with completed writer
    pipeline = {
        "pipeline_id": "p1",
        "session_id": session_id,
        "tasks": [
            {
                "task_id": "w1",
                "name": "writer",
                "agent_role": "writer",
                "status": "completed",
                "outputs": {"latex_paper": "\\section{Intro}\nTest paper."},
            },
            {
                "task_id": "g1",
                "name": "paper_qa_gate",
                "agent_role": "orchestrator",
                "status": "completed",
            },
        ],
    }
    (session_dir / "pipeline.json").write_text(json.dumps(pipeline))

    return session_id, session_dir


def test_load_session_returns_bus_brief_pipeline(mock_session_dir):
    session_id, _ = mock_session_dir
    bus, brief, pipeline = SessionLoader.load(session_id)
    assert bus.session_id == session_id
    assert brief.domain == "spectral_graph"
    assert pipeline is not None
    assert any(t.name == "writer" for t in pipeline.tasks)


def test_load_session_puts_latex_on_bus(mock_session_dir):
    session_id, _ = mock_session_dir
    bus, _, _ = SessionLoader.load(session_id)
    assert "Test paper" in (bus.get("paper_qa_latex") or "")


def test_load_session_not_found(tmp_path, monkeypatch):
    from eurekaclaw.config import settings
    monkeypatch.setattr(settings, "runs_dir", tmp_path)
    with pytest.raises(FileNotFoundError):
        SessionLoader.load("nonexistent-session")


def test_load_session_no_latex_raises(tmp_path, monkeypatch):
    from eurekaclaw.config import settings
    monkeypatch.setattr(settings, "runs_dir", tmp_path)

    session_id = "no-paper-session"
    session_dir = tmp_path / session_id
    session_dir.mkdir()

    brief = {"session_id": session_id, "input_mode": "detailed", "domain": "test", "query": "test"}
    (session_dir / "research_brief.json").write_text(json.dumps(brief))

    pipeline = {
        "pipeline_id": "p1",
        "session_id": session_id,
        "tasks": [{"task_id": "w1", "name": "writer", "agent_role": "writer", "status": "failed", "outputs": {}}],
    }
    (session_dir / "pipeline.json").write_text(json.dumps(pipeline))

    with pytest.raises(ValueError, match="No paper"):
        SessionLoader.load(session_id)


def test_load_session_partial_id(mock_session_dir, tmp_path, monkeypatch):
    from eurekaclaw.config import settings
    monkeypatch.setattr(settings, "runs_dir", tmp_path)
    session_id, _ = mock_session_dir
    prefix = session_id[:12]
    bus, brief, _ = SessionLoader.load(prefix)
    assert bus.session_id == session_id
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && source .venv/bin/activate && python -m pytest tests/unit/test_session_loader.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eurekaclaw.orchestrator.session_loader'`

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_session_loader.py
git commit -m "test: add unit tests for SessionLoader"
```

---

### Task 2: SessionLoader — Implementation

**Files:**
- Create: `eurekaclaw/orchestrator/session_loader.py`

- [ ] **Step 1: Implement SessionLoader**

```python
"""SessionLoader — reconstruct a runnable session from persisted artifacts."""

from __future__ import annotations

import logging
from pathlib import Path

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import TaskPipeline

logger = logging.getLogger(__name__)


class SessionLoader:
    """Reconstruct bus, brief, and pipeline from a persisted session directory."""

    @staticmethod
    def load(session_id: str) -> tuple[KnowledgeBus, ResearchBrief, TaskPipeline]:
        """Load a session from disk.

        Args:
            session_id: Full or partial (prefix, min 8 chars) session ID.

        Returns:
            (bus, brief, pipeline) tuple ready for PaperQAHandler.

        Raises:
            FileNotFoundError: Session directory not found.
            ValueError: No paper LaTeX found in session artifacts.
        """
        session_dir = SessionLoader._resolve_session_dir(session_id)
        resolved_id = session_dir.name

        bus = KnowledgeBus.load(resolved_id, session_dir)

        brief = bus.get_research_brief()
        if brief is None:
            raise FileNotFoundError(
                f"No research_brief.json in session {resolved_id}"
            )

        pipeline = bus.get_pipeline()
        if pipeline is None:
            raise FileNotFoundError(
                f"No pipeline.json in session {resolved_id}"
            )

        # Extract LaTeX from writer task outputs
        latex = ""
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )
        if writer_task and writer_task.outputs:
            latex = writer_task.outputs.get("latex_paper", "")

        # Fallback: check for paper.tex on disk
        if not latex:
            tex_path = session_dir / "paper.tex"
            if tex_path.is_file():
                latex = tex_path.read_text(encoding="utf-8")

        # Also check UI output dirs
        if not latex:
            for output_dir in settings.eurekaclaw_dir.glob("**/launch_from_ui"):
                tex_path = output_dir / f"{resolved_id}" / "paper.tex"
                if tex_path.is_file():
                    latex = tex_path.read_text(encoding="utf-8")
                    break

        if not latex:
            raise ValueError(
                f"No paper LaTeX found in session {resolved_id}. "
                "The writer may not have completed successfully."
            )

        bus.put("paper_qa_latex", latex)

        return bus, brief, pipeline

    @staticmethod
    def _resolve_session_dir(session_id: str) -> Path:
        """Resolve full or partial session ID to a directory path."""
        runs_dir = settings.runs_dir

        # Exact match
        exact = runs_dir / session_id
        if exact.is_dir():
            return exact

        # Prefix match (min 8 chars)
        if len(session_id) >= 8:
            matches = [
                d for d in runs_dir.iterdir()
                if d.is_dir() and d.name.startswith(session_id)
            ]
            if len(matches) == 1:
                return matches[0]
            if len(matches) > 1:
                names = ", ".join(m.name[:16] + "..." for m in matches[:5])
                raise FileNotFoundError(
                    f"Ambiguous session ID '{session_id}' matches {len(matches)} "
                    f"sessions: {names}. Use a longer prefix."
                )

        raise FileNotFoundError(
            f"Session '{session_id}' not found in {runs_dir}"
        )

    @staticmethod
    def list_sessions() -> list[dict]:
        """List all persisted sessions, sorted by modification time (newest first).

        Returns list of dicts with keys: session_id, domain, query, status, modified.
        """
        import json

        runs_dir = settings.runs_dir
        if not runs_dir.is_dir():
            return []

        sessions = []
        for session_dir in runs_dir.iterdir():
            if not session_dir.is_dir():
                continue
            brief_path = session_dir / "research_brief.json"
            if not brief_path.exists():
                continue

            try:
                brief = json.loads(brief_path.read_text(encoding="utf-8"))
            except Exception:
                continue

            # Determine status from pipeline
            status = "unknown"
            pipeline_path = session_dir / "pipeline.json"
            if pipeline_path.exists():
                try:
                    pipeline = json.loads(
                        pipeline_path.read_text(encoding="utf-8")
                    )
                    tasks = pipeline.get("tasks", [])
                    if tasks:
                        last_status = tasks[-1].get("status", "unknown")
                        if all(
                            t.get("status") in ("completed", "skipped")
                            for t in tasks
                        ):
                            status = "completed"
                        elif any(t.get("status") == "failed" for t in tasks):
                            status = "failed"
                        else:
                            status = last_status
                except Exception:
                    pass

            # Check if paper exists
            has_paper = False
            if pipeline_path.exists():
                try:
                    pipeline = json.loads(
                        pipeline_path.read_text(encoding="utf-8")
                    )
                    writer = next(
                        (t for t in pipeline.get("tasks", []) if t.get("name") == "writer"),
                        None,
                    )
                    if writer and writer.get("outputs", {}).get("latex_paper"):
                        has_paper = True
                except Exception:
                    pass
            if not has_paper:
                has_paper = (session_dir / "paper.tex").is_file()

            sessions.append({
                "session_id": session_dir.name,
                "domain": brief.get("domain", ""),
                "query": brief.get("query", ""),
                "status": status,
                "has_paper": has_paper,
                "modified": session_dir.stat().st_mtime,
            })

        sessions.sort(key=lambda s: s["modified"], reverse=True)
        return sessions
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && source .venv/bin/activate && python -m pytest tests/unit/test_session_loader.py -v`
Expected: All 5 tests PASS

- [ ] **Step 3: Commit**

```bash
git add eurekaclaw/orchestrator/session_loader.py
git commit -m "feat: add SessionLoader for reconstructing sessions from disk"
```

---

### Task 3: PaperQAHandler — run_historical() Method

**Files:**
- Modify: `eurekaclaw/orchestrator/paper_qa_handler.py`

- [ ] **Step 1: Add run_historical method**

In `eurekaclaw/orchestrator/paper_qa_handler.py`, add after the `run()` method (after the `await self._review_loop(pipeline, brief, latex)` line at the end of `run()`):

```python
    async def run_historical(
        self, pipeline: TaskPipeline, brief: ResearchBrief
    ) -> None:
        """Enter review loop for a historical session (skip the y/N prompt).

        Used by CLI `eurekaclaw review` and UI "Review Paper" button.
        """
        latex = self._get_latex_from_pipeline(pipeline)
        if not latex:
            # Fallback: check bus directly (SessionLoader puts it there)
            latex = self.bus.get("paper_qa_latex") or ""
        if not latex:
            console.print("[red]No paper LaTeX found in this session.[/red]")
            return

        self._save_paper_version(latex)
        self.bus.put("paper_qa_latex", latex)

        # Load existing QA history from disk if available
        history_file = self._session_dir / "paper_qa_history.jsonl"
        if history_file.exists():
            import json as _json
            for line in history_file.read_text(encoding="utf-8").strip().split("\n"):
                if line.strip():
                    try:
                        self._history.append(_json.loads(line))
                    except _json.JSONDecodeError:
                        pass

        await self._review_loop(pipeline, brief, latex)
```

- [ ] **Step 2: Run existing handler tests to verify no regressions**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && source .venv/bin/activate && python -m pytest tests/unit/test_paper_qa_handler.py -v`
Expected: All 5 tests PASS

- [ ] **Step 3: Commit**

```bash
git add eurekaclaw/orchestrator/paper_qa_handler.py
git commit -m "feat: add run_historical() to PaperQAHandler for session review"
```

---

### Task 4: CLI Commands — `sessions` and `review`

**Files:**
- Modify: `eurekaclaw/cli.py`

- [ ] **Step 1: Add `sessions` command**

In `eurekaclaw/cli.py`, add after the `resume` command (after the `resume` function ends):

```python
@main.command()
def sessions() -> None:
    """List all past research sessions.

    Example: eurekaclaw sessions
    """
    from eurekaclaw.orchestrator.session_loader import SessionLoader
    from rich.table import Table

    all_sessions = SessionLoader.list_sessions()
    if not all_sessions:
        console.print("[dim]No sessions found.[/dim]")
        return

    table = Table(title="Research Sessions", show_header=True, header_style="bold cyan")
    table.add_column("#", style="dim", width=3)
    table.add_column("Session ID", style="cyan", width=12)
    table.add_column("Domain", width=20)
    table.add_column("Query", width=40)
    table.add_column("Status", width=10)
    table.add_column("Paper", width=5)

    from datetime import datetime
    for i, s in enumerate(all_sessions, 1):
        status_color = {"completed": "green", "failed": "red"}.get(s["status"], "yellow")
        dt = datetime.fromtimestamp(s["modified"]).strftime("%Y-%m-%d")
        table.add_row(
            str(i),
            s["session_id"][:12] + "...",
            s["domain"][:20],
            s["query"][:40],
            f"[{status_color}]{s['status']}[/{status_color}]",
            "[green]yes[/green]" if s["has_paper"] else "[dim]no[/dim]",
        )

    console.print(table)
```

- [ ] **Step 2: Add `review` command**

Add immediately after the `sessions` command:

```python
@main.command()
@click.argument("session_id")
def review(session_id: str) -> None:
    """Review and QA a paper from a completed session.

    Loads the session from disk and enters the interactive QA/rewrite loop.
    Accepts full or partial session IDs (minimum 8 characters).

    Example: eurekaclaw review 0a370c0a
    """
    from eurekaclaw.orchestrator.session_loader import SessionLoader
    from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler
    from eurekaclaw.orchestrator.gate import GateController
    from eurekaclaw.orchestrator.router import TaskRouter
    from eurekaclaw.skills.injector import SkillInjector
    from eurekaclaw.skills.registry import SkillRegistry
    from eurekaclaw.memory.manager import MemoryManager
    from eurekaclaw.tools.registry import build_default_registry
    from eurekaclaw.llm import create_client
    from eurekaclaw.types.agents import AgentRole

    try:
        bus, brief, pipeline = SessionLoader.load(session_id)
    except FileNotFoundError as e:
        console.print(f"[red]{e}[/red]")
        sys.exit(1)
    except ValueError as e:
        console.print(f"[red]{e}[/red]")
        sys.exit(1)

    console.print(
        f"\n[bold green]Loading session[/bold green] [cyan]{bus.session_id[:12]}[/cyan]"
    )
    console.print(f"Domain: {brief.domain} | Query: {brief.query}")

    theory_state = bus.get_theory_state()
    if theory_state:
        console.print(
            f"Proof: {theory_state.status} — {len(theory_state.proven_lemmas)} lemmas"
        )

    client = create_client()
    tool_registry = build_default_registry(bus=bus)
    skill_registry = SkillRegistry()
    skill_injector = SkillInjector(skill_registry)
    memory = MemoryManager(session_id=bus.session_id)
    gate = GateController(bus=bus)
    router = TaskRouter({})

    handler = PaperQAHandler(
        bus=bus,
        agents={},
        router=router,
        client=client,
        tool_registry=tool_registry,
        skill_injector=skill_injector,
        memory=memory,
        gate_controller=gate,
    )

    asyncio.run(handler.run_historical(pipeline, brief))
```

- [ ] **Step 3: Verify CLI commands register**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && source .venv/bin/activate && python -m eurekaclaw.cli --help`
Expected: `sessions` and `review` appear in the command list

- [ ] **Step 4: Commit**

```bash
git add eurekaclaw/cli.py
git commit -m "feat: add 'sessions' and 'review' CLI commands"
```

---

### Task 5: Backend — Review Endpoints

**Files:**
- Modify: `eurekaclaw/ui/server.py`

- [ ] **Step 1: Add POST /api/runs/{run_id}/review endpoint**

In `eurekaclaw/ui/server.py`, in the `do_POST` method, add before the Paper QA endpoints section (`# ── Paper QA endpoints`):

```python
        # ── Historical review activation ──────────────────────────────────
        parts_review = parsed.path.strip("/").split("/")
        if (len(parts_review) == 4 and parts_review[0] == "api" and parts_review[1] == "runs"
                and parts_review[3] == "review"):
            run_id = parts_review[2]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            session_id = run.eureka_session_id
            if not session_id:
                self._send_json({"error": "No session ID"}, status=HTTPStatus.BAD_REQUEST)
                return

            from eurekaclaw.orchestrator.session_loader import SessionLoader
            try:
                bus, brief, pipeline = SessionLoader.load(session_id)
            except (FileNotFoundError, ValueError) as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.BAD_REQUEST)
                return

            # Attach loaded bus to the run so /paper-qa/ask can access it
            from eurekaclaw.main import EurekaSession
            if run.eureka_session is None:
                run.eureka_session = EurekaSession.__new__(EurekaSession)
                run.eureka_session.bus = bus
                run.eureka_session.session_id = session_id
            else:
                run.eureka_session.bus = bus

            self._send_json({"ok": True, "session_id": session_id})
            return

        # POST /api/runs/<run_id>/review/rewrite
        if (len(parts_review) == 5 and parts_review[0] == "api" and parts_review[1] == "runs"
                and parts_review[3] == "review" and parts_review[4] == "rewrite"):
            run_id = parts_review[2]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            session_id = run.eureka_session_id
            if not session_id:
                self._send_json({"error": "No session ID"}, status=HTTPStatus.BAD_REQUEST)
                return

            session = run.eureka_session
            bus = session.bus if session else None
            if not bus:
                self._send_json({"error": "Review not activated. Call POST /review first."}, status=HTTPStatus.BAD_REQUEST)
                return

            payload = self._read_json()
            revision_prompt = str(payload.get("revision_prompt", "")).strip()
            if not revision_prompt:
                self._send_json({"error": "No revision_prompt provided"}, status=HTTPStatus.BAD_REQUEST)
                return

            # Reconstruct orchestrator and run rewrite
            import asyncio as _asyncio
            from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
            from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler

            try:
                orchestrator = MetaOrchestrator(bus=bus, client=create_client())
                pipeline = bus.get_pipeline()
                brief = bus.get_research_brief()
                if not pipeline or not brief:
                    self._send_json({"error": "Missing pipeline or brief"}, status=HTTPStatus.BAD_REQUEST)
                    return

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

                loop = _asyncio.new_event_loop()
                new_latex = loop.run_until_complete(
                    handler._do_rewrite(pipeline, brief, revision_prompt=revision_prompt)
                )
                loop.close()

                if new_latex:
                    # Persist updated artifacts
                    session_dir = settings.runs_dir / session_id
                    bus.persist(session_dir)
                    self._send_json({"ok": True, "latex_paper": new_latex[:500]})
                else:
                    self._send_json({"error": "Rewrite failed"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            except Exception as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return
```

- [ ] **Step 2: Verify server loads**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && source .venv/bin/activate && python -c "import eurekaclaw.ui.server; print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add eurekaclaw/ui/server.py
git commit -m "feat(api): add /review and /review/rewrite endpoints for historical sessions"
```

---

### Task 6: Frontend — UI Store + PaperPanel Button

**Files:**
- Modify: `frontend/src/store/uiStore.ts`
- Modify: `frontend/src/components/workspace/PaperPanel.tsx`

- [ ] **Step 1: Add reviewSessionId to uiStore**

In `frontend/src/store/uiStore.ts`, add to the `UiState` interface (after `isFlashing: boolean;`):

```typescript
  reviewSessionId: string | null;
  setReviewSessionId: (id: string | null) => void;
```

Add to the store implementation (after `isFlashing: false,`):

```typescript
  reviewSessionId: null,
  setReviewSessionId: (id) => set({ reviewSessionId: id }),
```

- [ ] **Step 2: Add "Review Paper" button to PaperPanel**

In `frontend/src/components/workspace/PaperPanel.tsx`, add the import:

```typescript
import { useUiStore } from '@/store/uiStore';
import { apiPost } from '@/api/client';
```

Inside the component function, add:

```typescript
  const setReviewSessionId = useUiStore((s) => s.setReviewSessionId);

  const handleReviewPaper = async () => {
    if (!run?.run_id) return;
    try {
      await apiPost(`/api/runs/${run.run_id}/review`, {});
      setReviewSessionId(run.run_id);
    } catch (e) {
      console.error('Failed to activate review:', e);
    }
  };
```

Then in the JSX, add the button near the existing download buttons, visible when `isCompleted && paperText`:

```typescript
{isCompleted && paperText && (
  <button className="btn btn-primary" onClick={handleReviewPaper} style={{ marginTop: '0.75rem' }}>
    Review Paper
  </button>
)}
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `cd /Users/chenggong/Downloads/EurekaClaw/frontend && npx tsc --noEmit`
Expected: No new errors

- [ ] **Step 4: Commit**

```bash
git add frontend/src/store/uiStore.ts frontend/src/components/workspace/PaperPanel.tsx
git commit -m "feat(ui): add reviewSessionId store and Review Paper button"
```

---

### Task 7: Frontend — WorkspaceTabs + PaperReviewPanel Historical Mode

**Files:**
- Modify: `frontend/src/components/workspace/WorkspaceTabs.tsx`
- Modify: `frontend/src/components/workspace/paper-review/PaperReviewPanel.tsx`
- Modify: `frontend/src/components/workspace/paper-review/QAChat.tsx`

- [ ] **Step 1: Update WorkspaceTabs to check reviewSessionId**

In `frontend/src/components/workspace/WorkspaceTabs.tsx`, add import:

```typescript
import { useUiStore } from '@/store/uiStore';
```

The store is already imported. Add after the existing `isRewriteRunning` logic:

```typescript
  const reviewSessionId = useUiStore((s) => s.reviewSessionId);
  const reviewModeActive = reviewSessionId === run?.run_id;
```

Update the condition:

```typescript
  const isReviewActive = isGateActive || isRewriteRunning || reviewModeActive;
```

- [ ] **Step 2: Update PaperReviewPanel for historical mode**

In `frontend/src/components/workspace/paper-review/PaperReviewPanel.tsx`, add import:

```typescript
import { useUiStore } from '@/store/uiStore';
```

Inside the component, add:

```typescript
  const reviewSessionId = useUiStore((s) => s.reviewSessionId);
  const setReviewSessionId = useUiStore((s) => s.setReviewSessionId);
  const paperQATask = run.pipeline?.find((t) => t.name === 'paper_qa_gate');
  const isHistorical = !paperQATask || paperQATask.status !== 'awaiting_gate';
```

Update `handleAccept`:

```typescript
  const handleAccept = useCallback(async () => {
    if (isHistorical) {
      setReviewSessionId(null);
      return;
    }
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/paper_qa`, { action: 'no', question: '' });
    } catch (e) {
      console.error('Failed to accept paper:', e);
    }
  }, [run.run_id, isHistorical, setReviewSessionId]);
```

Update `handleRewrite`:

```typescript
  const handleRewrite = useCallback(async (prompt: string) => {
    const sysMsg: QAMessage = {
      role: 'system',
      content: `↻ Rewrite requested: "${prompt}"`,
      ts: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, sysMsg]);
    try {
      if (isHistorical) {
        await apiPost(`/api/runs/${run.run_id}/review/rewrite`, { revision_prompt: prompt });
      } else {
        await apiPost(`/api/runs/${run.run_id}/gate/paper_qa`, { action: 'rewrite', question: prompt });
      }
    } catch (e) {
      console.error('Failed to trigger rewrite:', e);
    }
  }, [run.run_id, isHistorical]);
```

Pass `isHistorical` to QAChat:

```typescript
  <QAChat
    run={run}
    messages={messages}
    setMessages={setMessages}
    isRewriting={isRewriting}
    isHistorical={isHistorical}
    onAccept={handleAccept}
    onRewrite={handleRewrite}
  />
```

- [ ] **Step 3: Update QAChat for historical mode**

In `frontend/src/components/workspace/paper-review/QAChat.tsx`, add `isHistorical` to props:

```typescript
interface QAChatProps {
  run: SessionRun;
  messages: QAMessage[];
  setMessages: React.Dispatch<React.SetStateAction<QAMessage[]>>;
  isRewriting: boolean;
  isHistorical: boolean;
  onAccept: () => void;
  onRewrite: (prompt: string) => void;
}
```

Update the destructuring:

```typescript
export function QAChat({ run, messages, setMessages, isRewriting, isHistorical, onAccept, onRewrite }: QAChatProps) {
```

Update the accept button label:

```typescript
<button className="qa-accept-btn" onClick={onAccept} disabled={isRewriting || sending}>
  {isHistorical ? '✕ Close Review' : '✓ Accept Paper'}
</button>
```

- [ ] **Step 4: Build and verify**

Run: `cd /Users/chenggong/Downloads/EurekaClaw/frontend && npx tsc --noEmit && npm run build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/workspace/WorkspaceTabs.tsx frontend/src/components/workspace/paper-review/PaperReviewPanel.tsx frontend/src/components/workspace/paper-review/QAChat.tsx
git commit -m "feat(ui): add historical review mode to PaperReviewPanel and QAChat"
```

---

### Task 8: Build + Integration Test

**Files:**
- No new files

- [ ] **Step 1: Build frontend and copy assets**

Run:
```bash
cd /Users/chenggong/Downloads/EurekaClaw/frontend && npm run build
cp -r dist/* ../eurekaclaw/ui/static/
```
Expected: Build succeeds

- [ ] **Step 2: Run full backend test suite**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && source .venv/bin/activate && python -m pytest tests/ -v 2>&1 | tail -5`
Expected: All pass (137+), no new failures

- [ ] **Step 3: Verify CLI commands**

Run:
```bash
source .venv/bin/activate && python -m eurekaclaw.cli sessions
```
Expected: Shows table of past sessions (or "No sessions found" if none)

- [ ] **Step 4: Verify imports**

Run:
```bash
source .venv/bin/activate && python -c "
from eurekaclaw.orchestrator.session_loader import SessionLoader
from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler
print('All imports OK')
"
```
Expected: `All imports OK`

- [ ] **Step 5: Commit built assets**

```bash
git add eurekaclaw/ui/static/ frontend/src/
git commit -m "build: compile frontend with historical session review"
```
