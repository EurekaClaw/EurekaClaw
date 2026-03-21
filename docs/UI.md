# EurekaClaw UI — Changelog & Design Notes

A full record of every UI feature, redesign, and fix shipped on the `chenggong` branch.

---

## Version history

### [v0.5] — Pause / Resume — State Machine & Real-Time Feedback

**Goal**: Make pause/resume feel instant with no perceptible lag; expose every intermediate state to the user with animated transitions.

#### Backend (`eurekaclaw/ui/server.py`)

- **New `SessionRun` fields**
  - `pause_requested_at: datetime | None` — timestamp written the moment a pause is requested (before the agent thread completes the current lemma)
  - `paused_stage: str` — the pipeline stage name (`LemmaDeveloper`, `Verifier`, …) where the proof halted; sourced from `ProofPausedException.stage_name`

- **`pause_run()` — intermediate `"pausing"` status**
  - Immediately sets `run.status = "pausing"` and `run.pause_requested_at` on the HTTP thread, then persists to disk
  - The background agent thread transitions `pausing → paused` when `ProofPausedException` is caught
  - Before this change: status stayed `"running"` until the thread finished the lemma — up to several seconds of frontend blindness

- **`resume_run()` — intermediate `"resuming"` status**
  - Sets `run.status = "resuming"` before starting the resume thread and persists to disk
  - Background thread transitions `resuming → running` at the start of `_execute_resume`
  - Before this change: status jumped from `paused` straight to `running` with no intermediate feedback

- **`_execute_run` / `_execute_resume` — capture stage on pause**
  - `ProofPausedException` handler now sets `run.paused_stage = exc.stage_name` and clears `pause_requested_at`

- **`_load_persisted_runs` — transient statuses cleaned on restart**
  - `"pausing"` and `"resuming"` are now treated as `"failed"` on server restart (they cannot survive a restart, unlike `"paused"` which has a checkpoint on disk)

- **`snapshot_run()` — new fields exposed**
  - `pause_requested_at` (ISO timestamp or null)
  - `paused_stage` (stage name string or empty)

#### Frontend — 4-State Proof Control Panel

Four mutually exclusive sub-panels inside `#proof-ctrl`:

| `#proof-ctrl-running` | Shows "Pause proof" button + caption |
|---|---|
| `#proof-ctrl-pausing` | Amber spinner + "Pausing…" + elapsed timer + "Finishing current lemma…" |
| `#proof-ctrl-paused` | Amber dot + "Proof paused" + stage name + session ID + Resume + Copy buttons |
| `#proof-ctrl-resuming` | Green spinner + "Resuming…" + "Loading checkpoint and rebuilding agent context" |

#### Frontend — Optimistic UI

- **Pause click** → instantly switches to the pausing panel and starts the elapsed timer *before* the API call returns; rolls back on error
- **Resume click** → instantly switches to the resuming panel *before* the API call returns; rolls back on error
- No more disabled-button flicker or blank state while the network round-trip completes

#### Frontend — Adaptive Polling

| Condition | Poll interval |
|---|---|
| Any session in `pausing` or `resuming` | **500 ms** |
| Any session `running` or `queued` | **1 200 ms** |
| All sessions terminal | **3 000 ms** |

`restartPollingFast()` immediately resets the interval to 500 ms on any user-initiated pause/resume, then `_pollTick` recalculates the correct interval after every response.

Previously: fixed 2 000 ms regardless of state.

#### Frontend — Animations & Visual Design

- `ctrl-flash-in` — 300 ms spring animation plays when the paused or running panel first becomes visible (entry from a transition state)
- `ctrl-slide-in` — 220 ms slide-in for the pausing/resuming bars
- Status pill: `pausing` = amber pulsing pill; `resuming` = green pulsing pill
- Sidebar dot: `pausing` = amber pulsing dot with ring ripple; `resuming` = green pulsing dot with ring ripple
- Sidebar micro-tag: colour-coded `pausing…` / `resuming…` tags matching their respective pill colours
- Elapsed timer inside the pausing bar — shows seconds since pause was requested; hidden if < 2 s

---

### [v0.4] — Guide / Tutorial Page Redesign

**Goal**: Rewrite the 7-step onboarding wizard to be approachable for mathematicians with no CS background.

#### Changes

- **Step 1 — Welcome**: Visual pipeline diagram `📚 Survey → 💡 Ideation → 📐 Theory → 🧪 Experiment → ✍️ Paper` with plain-English caption
- **Step 2 — Install**: Commands merged into multi-line blocks; clearer copy
- **Step 3 — Connect AI Model**: Replaced numbered list with a 2 × 2 option card grid (Anthropic / Claude Pro / OpenRouter / Local)
- **Step 4 — Key Settings**: Added formatted settings table (Setting / What it controls / Default) + plain-English GATE_MODE explanations
- **Step 5 — Optional Tools**: Items marked optional (○ bullet + badge); LaTeX shows macOS/Linux platform badge
- **Step 6 — Skills**: Clearer descriptions; "Add your own" marked optional
- **Step 7 — Launch**: Three research-mode cards (Explore / Prove / From Papers) each with description + copyable command

#### Renderer enhancements

- `visual` field — injects raw HTML before the items list (used for pipeline diagram, option cards, settings table, mode cards)
- `optional: true` on items — renders a `○` bullet and `.is-optional` styling instead of a numbered circle
- `badge` field — inline tag next to the item label (e.g., `macOS / Linux`)

New CSS classes: `.wiz-pipeline`, `.wiz-pipe-step`, `.wiz-options-grid`, `.wiz-option-card`, `.wiz-settings-table`, `.wiz-settings-row`, `.wiz-modes-grid`, `.wiz-mode-card`, `.wizard-item-badge`

---

### [v0.3] — ChatGPT-style Workspace & Session Management

**Goal**: Replace the always-visible flat grid with a blank-canvas / session-detail two-pane model; add rename, restart, delete.

#### Workspace layout

- **Blank canvas** (`#new-session-pane`) — shown when no session is selected; centered card with the launch form, `.canvas-form-body`, `.canvas-launch-btn`
- **Session detail pane** (`#session-detail-pane`) — shown when a session is selected; contains topbar, status row, proof controls, pipeline/agent/artifact/log panels
- `renderRun(null)` → `showNewSessionPane()`; `renderRun(run)` → `showSessionDetailPane()`

#### Session topbar

- `#session-topbar-name` — displays custom name or truncated query
- Pencil icon (`#session-topbar-rename-btn`) → inline rename input in the topbar
- `#run-status-pill` — live status pill in the topbar right

#### Session CRUD

| Action | Backend endpoint | Frontend trigger |
|---|---|---|
| Rename | `POST /api/runs/<id>/rename` | Pencil icon in topbar or sidebar |
| Restart (failed only) | `POST /api/runs/<id>/restart` | "Restart session" button in failed note + sidebar icon |
| Delete | `DELETE /api/runs/<id>` | Trash icon in sidebar |

Rules:
- Running/queued sessions cannot be deleted
- Failed sessions show a Restart button in the failed-session note
- Restart carries the custom name to the new run

#### Session persistence (server restart survival)

- `_persist_run()` — writes `~/.eurekaclaw/ui_sessions/<run_id>.json` on every status change
- `_load_persisted_runs()` — called on `UIServerState.__init__`; marks `running`/`queued` as `failed` with "interrupted by server restart" message
- `snapshot_run()` includes `"name": run.name`

#### Polling fix — per-session independence

- `_pollTick` now fetches only `GET /api/runs` (all sessions in one request)
- Sidebar status dots for all sessions update simultaneously
- Pausing/resuming session A no longer stops polling for session B
- `startPolling` guards against double-start with `if (pollTimer) return`

---

### [v0.2] — Pause / Resume Buttons (initial implementation)

**Goal**: Add pause and resume controls to the session detail view.

#### Backend

- `POST /api/runs/<id>/pause` — calls `ProofCheckpoint(run.eureka_session_id).request_pause()`; returns `{"ok": true}`
- `POST /api/runs/<id>/resume` — validates checkpoint exists; spawns `_execute_resume` thread
- `_execute_resume` — loads checkpoint, restores `TheoryState` into the bus, runs `TheoryInnerLoopYaml.run()` from `next_stage`
- `SessionRun.paused_at` — set when `ProofPausedException` is caught

#### Frontend

- `#proof-ctrl` — container hidden unless session is running or paused
- `#proof-ctrl-running` — "Pause proof" button + caption "Stops gracefully at the next lemma boundary"
- `#proof-ctrl-paused` — amber status dot + session ID `<code>` + "Resume proof" button + "Copy command" button
- Copy button writes `eurekaclaw resume <session_id>` to clipboard with a ✓ confirmation tick

---

### [v0.1] — Tutorial Skip Button

**Goal**: Let returning users skip the onboarding wizard without seeing it every page load.

#### Changes

- `localStorage` key `eurekaclaw_tutorial_skipped` — set to `"1"` when the skip button is clicked
- On page load: if the key is set, navigate directly to the Research tab instead of the Guide tab
- "Skip tutorial" link added to the wizard footer on every step
- "Show tutorial again" link in the Guide tab header lets users re-open the wizard at any time

---

### [v0.0] — Token Limit Alignment

**Goal**: Match `max_tokens_*` defaults in `config.py` to the values documented in `docs/token-limits.md` and used by the agent loop.

| Field | Old default | New default |
|---|---|---|
| `MAX_TOKENS_ASSEMBLER` | 6 000 | **6 144** |
| `MAX_TOKENS_ARCHITECT` | 3 000 | **3 072** |
| `MAX_TOKENS_ANALYST` | 1 600 | **1 536** |

---

## Architecture reference

### Pause / Resume data flow

```
User clicks "Pause"
  │
  ├─ Optimistic UI: show pausing bar + start elapsed timer
  │
  └─ POST /api/runs/<id>/pause
       │
       ├─ HTTP thread: run.status = "pausing", persist
       │
       └─ Agent thread: polls pause.flag at each lemma boundary
            │
            └─ ProofPausedException raised
                 │
                 ├─ run.status = "paused"
                 ├─ run.paused_stage = exc.stage_name
                 └─ checkpoint.json written to disk

User clicks "Resume"
  │
  ├─ Optimistic UI: show resuming bar
  │
  └─ POST /api/runs/<id>/resume
       │
       ├─ HTTP thread: run.status = "resuming", persist
       │
       └─ _execute_resume thread starts
            │
            ├─ run.status = "running"
            ├─ cp.load() → restore TheoryState into bus
            ├─ cp.clear_pause_flag()
            └─ TheoryInnerLoopYaml.run() continues from next_stage
```

### Checkpoint files

```
~/.eurekaclaw/sessions/<session_id>/
  pause.flag         # touched to request pause; deleted on resume
  checkpoint.json    # written when paused; deleted after successful resume

~/.eurekaclaw/ui_sessions/
  <run_id>.json      # UI session metadata; survives server restarts
```

### Frontend state machine

```
queued ──► running ──► pausing ──► paused ──► resuming ──► running
                │                                              │
                └──────────────► completed ◄──────────────────┘
                │
                └──────────────► failed
```
