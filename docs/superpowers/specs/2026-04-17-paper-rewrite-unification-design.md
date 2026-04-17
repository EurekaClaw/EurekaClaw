# Paper Rewrite Unification — Design Spec

**Date:** 2026-04-17
**Branch:** `shiyuan/paper-qa-gate`
**Supersedes the rewrite handling introduced in:** the earlier Paper Session Redesign (commit `680009e`).

## Goal

One rewrite code path — same UX, same endpoint, same scope of work — whether the orchestrator is still running a live session (gate mode) or has already exited (completed mode). Kill the proxy-timeout class of bug (`Failed to fetch`) and the activation-failure UX regressions Codex surfaced, by removing the stateful `/review` activation dance entirely.

## Background

### Current rewrite paths (two of them)

**Gate mode** — session is still running, `paper_qa_handler._run_ui_mode()` is waiting on `review_gate.wait_paper_qa()`:

1. Frontend: `POST /api/runs/{id}/gate/paper_qa` with `{action: "rewrite", question: prompt}`
2. Backend resolves the gate; the handler's loop calls `_do_rewrite(pipeline, brief, revision_prompt=prompt)` — re-runs `theory` then `writer`.
3. Pipeline state transitions live; frontend polls and sees progress.

**Completed mode** — orchestrator has exited, run is historical:

1. Frontend: `POST /api/runs/{id}/review/rewrite` with `{revision_prompt: prompt}`
2. Backend re-instantiates the orchestrator, loads the bus, runs `loop.run_until_complete(handler._do_rewrite(...))` **synchronously** inside the HTTP request thread.
3. `_do_rewrite` takes minutes. Vite dev proxy drops proxied requests at 30s, so the browser throws `TypeError: Failed to fetch` even when the backend is still working. The rewrite often does complete in the background, but the UI has already given up.

### Activation-failure UX regressions

To make completed-mode QA work at all, the frontend today calls `POST /api/runs/{id}/review` on mount to re-hydrate the bus on the backend. Two regressions Codex flagged on the current `shiyuan/paper-qa-gate` branch:

1. **"Broken chat state on activation failure"** — when `/review` rejects (corrupt files, missing session dir), the rendered panel shows an error banner but still mounts the full QAChat (history empty, Accept/Rewrite/Send buttons all non-functional — every click error-toasts).
2. **"Completed-run rewrite UX flash"** — `onRewrite` in completed mode resets `reviewStatus='idle'`, which flips mode back to `loading-review` while Effect 1 re-POSTs `/review`. Viewer and chat vanish for the duration of the re-activation round-trip.

Both regressions stem from the same underlying model mismatch: the frontend is being made to care about a backend implementation detail (whether a bus is loaded in memory) that has no business being user-visible.

## Approach (decided)

- **Q1 — scope of rewrite:** `theory → (experiment iff EXPERIMENT_MODE allows) → writer`. Matches the forward pipeline exactly; no new user-facing toggle.
- **Q2 — execution model:** background task. POST returns `202` immediately. Pipeline state is the source of truth; the frontend already polls it.
- **Q3 — activation model:** eliminate `/review` and the `reviewStatus` / `loading-review` / `reviewError` machinery. The bus is a backend implementation detail. Endpoints that need a bus call a shared `_ensure_bus_activated(run)` helper lazily.

## Architecture

```
┌─ frontend: usePaperSession ─┐            ┌─ backend: server.py ─────────────────┐
│ onRewrite(prompt)           │            │ POST /api/runs/{id}/rewrite          │
│   append optimistic marker  │───────────▶│   bus, pipeline, brief =             │
│   POST /rewrite             │ 202 OK     │     _ensure_bus_activated(run)       │
│                             │◀───────────│   if gate_waiting(paper_qa):         │
│ polls pipeline every ~1s    │            │     resolve_gate(rewrite, prompt)    │
│   sees theory → writer →    │            │     return 202 {mode: "gate"}        │
│   paper_version bump        │            │   else:                              │
│                             │            │     spawn_bg(_do_rewrite,            │
│ modes: no-paper | gate |    │            │       pipeline, brief, prompt)       │
│        rewriting |          │            │     return 202 {mode: "bg",          │
│        completed | failed   │            │                 rewrite_id}          │
│                             │            │                                      │
│ (no 'loading-review')       │            │ GET /paper-qa/history                │
│ (no reviewStatus/Error)     │            │   read jsonl from disk (no bus)      │
└─────────────────────────────┘            │                                      │
                                           │ POST /paper-qa/ask                   │
                                           │   _ensure_bus_activated(run); ask    │
                                           │                                      │
                                           │ DELETED: /review, /review/rewrite    │
                                           └──────────────────────────────────────┘
```

## Backend changes

### New shared helper — `_ensure_bus_activated(run) → (bus, pipeline, brief)`

Lives in `eurekaclaw/ui/server.py` near `_sync_latex_to_disk`. Consolidates the bus-hydration logic that `/review`, `/review/rewrite`, and `/paper-qa/ask` each duplicate today.

```python
def _ensure_bus_activated(run) -> tuple[KnowledgeBus, TaskPipeline, ResearchBrief]:
    """Return the run's live bus/pipeline/brief, hydrating from disk if needed.

    Raises ValueError with a human-readable message on corrupt/missing state.
    """
    session = run.eureka_session
    if session and session.bus:
        bus = session.bus
    else:
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

Callers catch `ValueError` / `FileNotFoundError` and return `400 {"error": str(e)}`.

### New endpoint — `POST /api/runs/{id}/rewrite`

Single entry point. Replaces `/review/rewrite` entirely and absorbs the rewrite semantics of `/gate/paper_qa` when a gate is waiting.

```python
# POST /api/runs/<run_id>/rewrite
parts = parsed.path.strip("/").split("/")
if (len(parts) == 4 and parts[0] == "api" and parts[1] == "runs"
        and parts[3] == "rewrite"):
    run_id = parts[2]
    run = self.state.get_run(run_id)
    if run is None:
        return self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)

    try:
        bus, pipeline, brief = _ensure_bus_activated(run)
    except (ValueError, FileNotFoundError) as e:
        return self._send_json({"error": str(e)}, status=HTTPStatus.BAD_REQUEST)

    payload = self._read_json()
    prompt = str(payload.get("revision_prompt", "")).strip()
    if not prompt:
        return self._send_json({"error": "revision_prompt required"}, status=HTTPStatus.BAD_REQUEST)

    # Concurrency guard
    theory_task = next((t for t in pipeline.tasks if t.name == "theory"), None)
    writer_task = next((t for t in pipeline.tasks if t.name == "writer"), None)
    if any(t and t.status in (TaskStatus.IN_PROGRESS, TaskStatus.RUNNING)
           for t in (theory_task, writer_task)):
        return self._send_json(
            {"error": "A rewrite is already in progress"},
            status=HTTPStatus.CONFLICT,
        )

    # Gate-live path
    paper_qa_task = next((t for t in pipeline.tasks if t.name == "paper_qa_gate"), None)
    if paper_qa_task and paper_qa_task.status == TaskStatus.AWAITING_GATE:
        from eurekaclaw.ui import review_gate
        review_gate.submit_paper_qa(run.eureka_session_id, action="rewrite", question=prompt)
        return self._send_json({"ok": True, "mode": "gate"}, status=HTTPStatus.ACCEPTED)

    # Background-task path
    rewrite_id = str(uuid.uuid4())
    thread = threading.Thread(
        target=_run_rewrite_bg,
        args=(run, bus, pipeline, brief, prompt, rewrite_id),
        daemon=True,
    )
    thread.start()
    return self._send_json(
        {"ok": True, "mode": "bg", "rewrite_id": rewrite_id},
        status=HTTPStatus.ACCEPTED,
    )
```

### Background task — `_run_rewrite_bg`

```python
def _run_rewrite_bg(run, bus, pipeline, brief, prompt: str, rewrite_id: str) -> None:
    """Thread entry point. Owns its own asyncio event loop.

    Mutates pipeline state in-place through _do_rewrite; on failure marks
    theory/writer as failed and appends a system error marker so the
    frontend doesn't see a phantom in-progress forever.
    """
    session_id = run.eureka_session_id
    try:
        orchestrator = MetaOrchestrator(bus=bus, client=create_client())
        handler = PaperQAHandler(
            bus=bus, agents=orchestrator.agents, router=orchestrator.router,
            client=orchestrator.client, tool_registry=orchestrator.tool_registry,
            skill_injector=orchestrator.skill_injector, memory=orchestrator.memory,
            gate_controller=orchestrator.gate,
        )
        new_latex = asyncio.run(
            handler._do_rewrite(pipeline, brief, revision_prompt=prompt)
        )
        if new_latex:
            _sync_latex_to_disk(run)
            _unlink_stale_pdf(run)
            _bump_writer_paper_version(bus)
            _append_paper_qa_rewrite_marker(session_id, prompt)
            bus.persist(settings.runs_dir / session_id)
        else:
            _append_paper_qa_error_marker(session_id, "Rewrite produced no new paper")
    except Exception as e:
        logger.exception("Rewrite background task failed: %s", e)
        _mark_rewrite_tasks_failed(pipeline, bus)
        _append_paper_qa_error_marker(session_id, f"Rewrite failed: {e}")
```

`_mark_rewrite_tasks_failed` sets `theory.status` and `writer.status` to `FAILED` if either was left in `IN_PROGRESS`, so the frontend sees the pipeline settle.

`_append_paper_qa_error_marker` writes a `{role: "system", content: f"Revision error: {msg}", ts, version}` line to `paper_qa_history.jsonl` — frontend renders it the same way as any other system marker.

`_unlink_stale_pdf` deletes `paper.pdf` from both the session dir and the output dir if present, matching today's behavior.

### `GET /paper-qa/history` — read from disk

```python
hist_path = settings.runs_dir / session_id / "paper_qa_history.jsonl"
if not hist_path.is_file():
    return self._send_json({"messages": []})
messages = []
for line in hist_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        messages.append(json.loads(line))
    except json.JSONDecodeError:
        continue
return self._send_json({"messages": messages})
```

No bus activation. Missing file = empty list.

### `POST /paper-qa/ask` — lazy activation

Current handler begins with a "is the bus loaded?" check that errors out if not. Replace that check with `bus, pipeline, brief = _ensure_bus_activated(run)`. Rest of the handler unchanged.

### `_do_rewrite` — include experiment in rewrite_tasks

In `eurekaclaw/orchestrator/paper_qa_handler.py` at line 360, replace:

```python
rewrite_tasks = ["writer"] if writer_only else ["theory", "writer"]
```

with:

```python
if writer_only:
    rewrite_tasks = ["writer"]
else:
    rewrite_tasks = ["theory", "experiment", "writer"]
```

The `ExperimentAgent` already honors `settings.experiment_mode` internally (agents/experiment/agent.py:169–175): `mode="false"` → skip, `mode="true"` → force, `mode="auto"` → decide. No extra gating here — just add `"experiment"` to the list and let the agent's own logic run. When experiment skips, it marks the task completed with empty outputs and moves on.

Snapshot/restore logic at lines 362–371 extends analogously:

```python
experiment_task = next((t for t in pipeline.tasks if t.name == "experiment"), None)
prev_experiment_outputs = dict(experiment_task.outputs) if experiment_task else {}
```

And the failure-restore block at lines 431–443 adds the same `COMPLETED + prev_experiment_outputs` restore for `experiment_task`.

The feedback-injection block (line 378–385) also resets `experiment_task.status = TaskStatus.PENDING` and `experiment_task.retries = 0` when not `writer_only`, so it actually re-executes in the loop.

### Deletions

- `POST /api/runs/{id}/review` handler in `server.py` (currently ~lines 2057–2087).
- `POST /api/runs/{id}/review/rewrite` handler in `server.py` (currently ~lines 2089–2180+).

## Frontend changes

### `usePaperSession` — simpler state

Delete `reviewStatus`, `reviewError`, Effect 1 (the `/review` POST). `PaperMode` becomes:

```ts
export type PaperMode = 'no-paper' | 'gate' | 'rewriting' | 'completed' | 'failed';
```

Mode computation:

```ts
const mode: PaperMode = useMemo(() => {
  if (!run) return 'no-paper';
  if (run.status === 'failed' && !hasPaper) return 'failed';
  if (!hasPaper) return 'no-paper';
  if (paperQATask?.status === 'awaiting_gate') return 'gate';
  if (pipelineRewriting) return 'rewriting';
  return 'completed';
}, [run, hasPaper, paperQATask?.status, pipelineRewriting]);
```

History-load effect fires on `run_id` change or when mode transitions from `'rewriting' → 'completed'`:

```ts
useEffect(() => {
  if (!run?.run_id) return;
  void (async () => {
    try {
      const data = await apiGet<HistoryResponse>(`/api/runs/${run.run_id}/paper-qa/history`);
      const serverMsgs = data.messages ?? [];
      setMessages((prev) => {
        const serverKeys = new Set(serverMsgs.map((m) => `${m.role}|${m.content}`));
        const optimistic = prev.filter(
          (m) => m.role === 'system'
            && typeof m.content === 'string'
            && m.content.startsWith(REWRITE_MARKER_PREFIX)
            && !serverKeys.has(`${m.role}|${m.content}`),
        );
        return [...serverMsgs, ...optimistic];
      });
    } catch {
      setMessages((prev) => prev.filter(
        (m) => m.role === 'system'
          && typeof m.content === 'string'
          && m.content.startsWith(REWRITE_MARKER_PREFIX),
      ));
    }
  })();
}, [run?.run_id, mode]);
```

### Unified `onRewrite`

```ts
const onRewrite = useCallback(async (prompt: string) => {
  if (!run?.run_id) return;
  const marker: QAMessage = {
    role: 'system',
    content: `${REWRITE_MARKER_PREFIX}"${prompt}"`,
    ts: new Date().toISOString(),
  };
  setMessages((prev) => [...prev, marker]);
  setIsRewriting(true);
  try {
    await apiPost(`/api/runs/${run.run_id}/rewrite`, { revision_prompt: prompt });
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
}, [run?.run_id]);
```

No more mode-forking, no `setReviewStatus('idle')` cascade. `onAccept` is unchanged — still POSTs `/api/runs/{id}/gate/paper_qa` with `{action: 'no'}`.

### `PaperPanel`

Delete the `loading-review` render branch entirely. Delete the `paper-review-error-banner` block. Four render branches remain:

- `!run` → empty state "Launch a session..."
- `session.mode === 'failed'` → empty state with `run.error`
- `session.mode === 'no-paper'` → empty state / dots if `run.status === 'running'`
- default (`'gate'` | `'rewriting'` | `'completed'`) → viewer + draggable divider + QAChat (unchanged layout)

### `QAChat`

No changes. Props unchanged.

### Tests

Delete (their states no longer exist):

- `review-activation failure falls back to completed mode with reviewError set`
- `onRewrite in completed mode keeps mode at completed (no flash to loading-review)`

Add:

- `onRewrite posts to /api/runs/{id}/rewrite regardless of mode` (two renders: gate + completed, both hit the same URL)
- `mode transitions completed → rewriting when theory flips to in_progress`
- `history load fires on run_id change and on mode transition`

Keep (unchanged):

- `returns null when run is null`
- `yields mode=no-paper when pipeline has no writer output`
- `enters gate mode when paper_qa_gate awaits gate and writer has output`
- `onAccept posts no-action to the gate endpoint in gate mode`
- `returns isRewriting=true when theory task is in_progress after gate completion`
- `paperVersion reads writer.outputs.paper_version when present`
- `paperVersion falls back to 1 + rewrite-marker count when writer lacks the field`
- `history-load failure preserves optimistic rewrite markers`

## Data flow

### Happy path — completed mode

```
1. user types "tighten Section 3" → clicks Rewrite
2. hook appends optimistic marker "↻ Rewrite requested: ..."
3. POST /api/runs/{id}/rewrite → 202 {mode:"bg", rewrite_id}  (~instant)
4. background thread runs asyncio.run(handler._do_rewrite(...)):
     a. theory_task.status = in_progress         │ polling frontend:
     b. theory agent runs (~30s–few min)         │   mode = 'rewriting'
     c. theory_task.status = completed           │   isRewriting = true
     d. (experiment runs iff EXPERIMENT_MODE)    │   viewer shows old paper
     e. writer_task.status = in_progress         │
     f. writer agent runs                        │
     g. writer.outputs.latex_paper = new_latex   │
     h. writer.outputs.paper_version += 1        │   paper_version changes
     i. writer_task.status = completed           │   mode = 'completed'
5. _sync_latex_to_disk writes paper.tex, deletes paper.pdf
6. append marker to paper_qa_history.jsonl
7. frontend's next /paper-qa/history poll picks up the marker
8. PDF iframe re-fetches /compile-pdf → new PDF renders
```

### Happy path — gate mode

Same frontend UX. Step 3's 202 carries `{"mode":"gate"}`; backend calls `review_gate.submit_paper_qa(session_id, action="rewrite", question=prompt)`. The orchestrator's live `_run_ui_mode` loop then drives steps 4–8 exactly as it does today.

## Error handling

| Failure | Backend response / state | User sees |
|---|---|---|
| `_ensure_bus_activated` raises | `400 {"error": str(e)}` | Optimistic marker stays; `Revision error: <detail>` marker appended |
| Concurrency: rewrite already in progress | `409 {"error": "A rewrite is already in progress"}` | Same toast pattern |
| `theory._do_rewrite` raises inside bg thread | bg catches; marks theory/writer `FAILED`; appends error marker | Pipeline settles with failed status; new error marker on next poll; paper unchanged |
| Writer raises inside bg thread | Same | Same |
| Browser offline on POST | `apiPost` throws TypeError | Optimistic marker stays; error marker appended by `onRewrite` catch |
| Background thread crashes uncaught (OS-level) | Outer `try/except` in `_run_rewrite_bg` catches all exceptions and calls `_mark_rewrite_tasks_failed` | Pipeline settles; error marker appended |
| User refreshes browser mid-rewrite | Pipeline state still reflects in-progress; history loads from disk (includes optimistic marker? no — optimistic lives in React state only; will be re-appended on next rewrite) | `rewriting` mode + isRewriting=true; no duplicate marker |

## Testing

### Backend

Add `tests/unit/test_ensure_bus_activated.py`:

- returns existing bus when already attached
- loads via SessionLoader when not attached
- raises `ValueError` with a readable message on missing pipeline / brief

Add `tests/unit/test_rewrite_endpoint.py` (uses the same `_FakeRun` / `KnowledgeBus` pattern as `test_sync_latex_to_disk.py`):

- POST returns 202 with `mode:"gate"` when paper_qa_gate is `AWAITING_GATE`
- POST returns 202 with `mode:"bg"` when paper_qa_gate is `COMPLETED`
- POST returns 409 when theory is `IN_PROGRESS`
- POST returns 400 when `revision_prompt` is empty
- POST returns 400 when `_ensure_bus_activated` raises

Add `tests/unit/test_paper_qa_history_disk.py`:

- returns `{messages: []}` when file is missing
- parses JSONL correctly
- skips malformed lines instead of failing

Extend `tests/unit/test_paper_qa_rewrite.py` (or create if missing):

- `_do_rewrite` iterates `["theory", "experiment", "writer"]` when not `writer_only`
- experiment task is reset to `PENDING` before the loop and restored on rewrite failure
- when `settings.experiment_mode == "false"`, the agent's own skip logic leaves experiment as a no-op (test via agent-level mock, not by re-gating inside `_do_rewrite`)

### Frontend

Update `usePaperSession.test.ts` per the "Tests" section above.

### Manual verification (post-merge, at keyboard)

1. Fresh session reaches `paper_qa_gate` → clicking Rewrite in the QA chat issues one POST to `/api/runs/{id}/rewrite` (check Network tab). Pipeline transitions visibly; new paper_version shows; new system marker appears in history.
2. Kill the orchestrator (or wait for it to complete naturally). In a historical run, click Rewrite — same one POST, same pipeline transitions visible (theory → writer), same paper version bump. No "Failed to fetch" at 30 s.
3. Switch Live/Proof/Paper tabs freely during a rewrite; paper tab keeps the viewer + chat mounted, pipeline state visible on Live tab.
4. Refresh the browser mid-rewrite; paper tab shows `rewriting` mode with the in-progress pipeline; after completion the new paper and history marker appear.
5. With a broken session (corrupt `paper_qa_history.jsonl` or missing session dir): rewrite POST returns 400; error marker appears in chat; paper viewer unaffected.

## Rollout

One branch, one PR. Suggested commit sequence in the implementation plan:

1. Backend: extend `_do_rewrite` to include experiment in `rewrite_tasks` + snapshot/restore + unit tests.
2. Backend: add `_ensure_bus_activated` helper + unit tests.
3. Backend: add disk-reading `/paper-qa/history` handler + unit tests.
4. Backend: add `/rewrite` endpoint + `_run_rewrite_bg` background-task machinery + unit tests.
5. Backend: convert `/paper-qa/ask` to lazy activation.
6. Backend: delete `/review` and `/review/rewrite` handlers.
7. Frontend: simplify `usePaperSession` (delete `reviewStatus` / `reviewError` / Effect 1; unify `onRewrite`); update vitest suite.
8. Frontend: simplify `PaperPanel` (delete `loading-review` branch, delete error banner).
9. Manual verification at keyboard.

No feature flags. The old endpoints and UX have no external consumers.

## What gets deleted

- `POST /api/runs/{id}/review` handler (server.py)
- `POST /api/runs/{id}/review/rewrite` handler (server.py)
- `reviewStatus`, `reviewError`, Effect 1 in `frontend/src/components/workspace/paper-review/usePaperSession.ts`
- `'loading-review'` from the `PaperMode` union
- `loading-review` render branch and `paper-review-error-banner` block in `frontend/src/components/workspace/PaperPanel.tsx`
- Vitest cases `review-activation failure…` and `onRewrite in completed mode keeps mode at completed`

## Non-goals

- Redesigning the QA `/ask` experience (question-answering flow). Stays as-is; just gets lazy bus activation.
- Changing the pipeline graph (stages stay the same; rewrite still calls into `_do_rewrite`, which already handles the `theory → experiment → writer` replay).
- Persisting the optimistic marker to disk before the POST succeeds. It's React state only; survives a successful POST via the server echo, and re-appears on retry after a crash.
