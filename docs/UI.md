# EurekaClaw UI — Design Notes & Changelog

A full record of every UI feature, redesign, and fix shipped on the `chenggong` branch.

---

## Running the UI

### One-line commands

```bash
# Production — build frontend, open browser, serve on :8080
make open

# Production — build frontend, serve on :8080 (no browser)
make start

# Development — hot-reload Vite on :5173 + Python backend on :7860
make dev

# Or use the CLI directly (serves last build from eurekaclaw/ui/static/)
eurekaclaw ui --open-browser
```

### How it works

| Mode | Frontend | Backend | URL |
|---|---|---|---|
| **Production** (`make start`) | Pre-built bundle in `eurekaclaw/ui/static/` | Python `SimpleHTTPRequestHandler` + API on same port | `http://localhost:8080` |
| **Dev** (`make dev`) | Vite dev server with HMR | Python API on `:7860`; Vite proxies `/api/*` | `http://localhost:5173` |

### First-time setup

```bash
pip install -e "."          # Python backend
make install                 # installs both pip package + npm deps
eurekaclaw install-skills   # copy seed skills (once)
cp .env.example .env        # add ANTHROPIC_API_KEY
```

### Frontend build (when you change React code)

```bash
make build       # tsc + vite build → eurekaclaw/ui/static/
make typecheck   # type-check only, no output
```

---

## Version history

### [v0.8] — Gate System Finalization, Paper Panel, Theme Unification

**Goal**: Adopt the unified gate system from `main`, enhance all gate modals, build a full-featured Paper tab, add session status indicators, and unify the entire UI to a consistent blue/white theme.

#### Gate system — backend reset to `main`

The `chenggong` branch's exception-based gate code (`AwaitingDirectionException`, `AwaitingReviewException`, `run_from_direction`, `run_from_review`) was replaced by `main`'s working thread-based gate system:

| Component | Mechanism |
|---|---|
| `review_gate.py` | Thread-safe `threading.Event` blocking waits with `SurveyDecision`, `DirectionDecision`, `TheoryDecision` dataclasses |
| `server.py` | `POST /api/runs/<id>/gate/{survey\|direction\|theory}` endpoints call `review_gate.submit_*()` to unblock the pipeline thread |
| `meta_orchestrator.py` | Uses `EUREKACLAW_UI_MODE` env var + `review_gate.wait_*()` for UI-mode gates |
| Pipeline tasks | `TaskStatus.AWAITING_GATE` on individual pipeline tasks signals the frontend |

Three gates: **Survey** (0 papers found), **Direction** (0 directions), **Theory Review** (proof approval).

#### Gate overlay modals — redesigned

| Gate | Changes |
|---|---|
| **Survey** | Blue/white theme, enlarged textarea and buttons |
| **Direction** | Compact modal (560px), open problems list with clickable "Use" buttons, key objects tags, simplified description text, no verbose hints |
| **Theory Review** | `--wide` card (740px), enlarged theorem preview (200px), **new "Flag a concern" section** with styled lemma picker (clickable cards with blue ID pill, checkmark selection, blue border highlight) replacing the plain `<select>` dropdown |

All gate modals share: `max-height: 85vh; overflow-y: auto` to prevent page overflow.

#### Paper tab — full rewrite (`PaperPanel.tsx`)

| Feature | Details |
|---|---|
| **Status badge** | Color-coded pill — green (completed), blue (running), red (failed) |
| **Theory stats** | Proven lemmas count + open goals inline |
| **Output directory** | Shown for completed runs with folder icon |
| **Download PDF** | Button appears if PDF exists on disk |
| **Generate PDF** | Triggers `POST /api/runs/<id>/compile-pdf` with spinner animation; appears when no PDF exists |
| **Download .tex / .bib** | Secondary buttons to download LaTeX source and bibliography |
| **LaTeX source viewer** | Collapsible dark-themed code viewer with file size indicator, **Copy LaTeX** button with checkmark feedback, 400px scrollable area |

#### Backend — new API endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/runs/<id>/artifacts/<filename>` | Serves artifact files (paper.pdf, paper.tex, references.bib, etc.) with security allowlist |
| `POST /api/runs/<id>/compile-pdf` | Triggers pdflatex compilation on the server; returns success or descriptive error |

#### Backend — robust PDF compilation (`main.py`)

- `_resolve_latex_bin()` — searches `PATH` + common TeX directories (`/Library/TeX/texbin`, `/usr/local/texlive/*/bin/*/`, `/opt/homebrew/bin`) so pdflatex works even when not on the server process's PATH
- `_compile_pdf()` failure is now caught in `save_artifacts()` — PDF generation never crashes the run
- `_send_file()` method added to `UIRequestHandler` for binary file downloads with proper Content-Type and Content-Disposition headers

#### Sidebar session list — status indicators

| Status | Visual |
|---|---|
| **Completed** | Green `FINISHED` tag + green left border accent on the session item |
| **Running** | Blue `RUNNING` tag |
| **Failed** | Red `FAILED` tag + dimmed opacity |
| **Paused** | Amber `PAUSED` tag |
| **Pausing** | Dark orange `PAUSING…` tag with pulse animation |
| **Resuming** | Green `RESUMING…` tag with pulse animation |

All tags use a shared `.session-item-status-tag` base class.

#### Theme unification — blue/white

All accent colors unified to the `--primary` / `--primary-soft` / `--primary-strong` palette:

| Element | Before | After |
|---|---|---|
| `.btn-primary` | `var(--accent)` (brown) | `var(--primary)` (blue) |
| Gate borders | `var(--amber)` / `var(--cyan)` | `var(--primary-soft)` |
| Review gate lemma badges | Red / amber / cyan | Blue theme |
| Focus rings | Brown accent | Blue `box-shadow` |

#### Polling — auto-refresh on pause/resume

- **`isPausingRequested` clearing**: When backend confirms `paused` or `running`, the optimistic flag is cleared so polling returns to normal interval
- **Auto-tab switch**: `paused/resuming → running` automatically switches to the Live tab so users see proof progress resume in real-time

#### Layout changes

| Change | Details |
|---|---|
| **Guide button** | Moved from Sidebar to `App.tsx` bottom-right corner (`position: absolute`) |
| **Skills page** | Swapped layout — "Install built-in seed skills" on the left, ClawHub external install on the right |

#### Updated component tree

```
App
├── FlashOverlay
├── Sidebar
│   └── SessionList (with status tags: finished/running/failed/paused/pausing/resuming)
├── <active view>
│   ├── WorkspaceView
│   │   └── SessionDetailPane
│   │       ├── SessionTopBar
│   │       ├── ProofCtrl
│   │       ├── WorkspaceSplit
│   │       │   ├── AgentTrack
│   │       │   └── WorkspaceTabs
│   │       │       ├── LivePanel
│   │       │       ├── ProofPanel
│   │       │       ├── PaperPanel (PDF download, Generate PDF, LaTeX viewer, copy)
│   │       │       └── LogsPanel
│   │       ├── AgentDrawer
│   │       └── GateOverlay
│   │           ├── SurveyGate
│   │           ├── DirectionGate (open problems, key objects, compact)
│   │           └── TheoryReviewGate (lemma picker cards, feedback section)
│   ├── SkillsView (seed skills left, ClawHub right)
│   ├── ConfigView
│   └── OnboardingView
└── Guide button (bottom-right)
```

---

### [v0.7] — React + TypeScript + Vite Migration

**Goal**: Replace the 7 000-line monolithic frontend (`app.js` / `styles.css` / `index.html`) with a properly typed, component-split Vite 5 + React 18 + TypeScript 5 project that is maintainable by humans and agents alike.

#### Tech stack

| Layer | Before | After |
|---|---|---|
| Bundler | None (raw file) | **Vite 5** |
| Language | Vanilla JS (no types) | **TypeScript 5** (strict mode, zero errors) |
| Framework | Imperative DOM manipulation | **React 18** (functional components + hooks) |
| State | Module-level `let` variables | **Zustand 5** stores |
| Styles | Single 3 900-line CSS file | 19 domain-specific CSS files |

#### New project structure

```
frontend/
├── index.html                  # Vite entry point (fonts, root div)
├── vite.config.ts              # build → eurekaclaw/ui/static/; dev proxy /api → :7860
├── package.json                # React 18, Zustand, Vite 5, TypeScript 5, concurrently
├── _legacy/                    # original app.js / styles.css / index.html (archived)
└── src/
    ├── types/                  # TypeScript interfaces
    │   ├── run.ts              # SessionRun, PipelineTask, Artifacts, InputSpec, RunStatus
    │   ├── skill.ts            # Skill, SkillSource
    │   ├── config.ts           # AppConfig, Capability, LLMBackend, AuthMode
    │   └── wizard.ts           # WizardStep, WizardItem
    ├── api/client.ts           # typed apiGet / apiPost / apiDelete wrappers
    ├── lib/
    │   ├── formatters.ts       # escapeHtml, titleCase, formatRelativeTime, parseServerTimestamp
    │   ├── statusHelpers.ts    # statusClass, liveStatusDetail, getActiveOuterStage, friendlyInnerStage
    │   └── agentManifest.ts    # AGENT_MANIFEST, STAGE_TASK_MAP, INNER_STAGE_LABELS, agentNarrativeLine
    ├── store/
    │   ├── sessionStore.ts     # sessions[], currentRunId, currentLogPage, isPausingRequested
    │   ├── skillStore.ts       # availableSkills[], selectedSkills[], pagination, search
    │   └── uiStore.ts          # activeView, activeWsTab, openAgentDrawerRole, flash state
    ├── hooks/
    │   ├── usePolling.ts       # adaptive-rate polling (500 / 1 200 / 3 000 ms)
    │   ├── useElapsedTimer.ts  # seconds-since-pause counter
    │   └── useLocalStorage.ts  # generic localStorage hook (tutorial skip key)
    └── components/             # 35 React components
        ├── layout/             # Sidebar, FlashOverlay
        ├── session/            # SessionList, NewSessionForm, SessionDetailPane, SessionTopBar
        ├── workspace/          # WorkspaceSplit, AgentTrack, AgentStepCard, WorkspaceTabs,
        │                       # LivePanel, ProofPanel, PaperPanel, LogsPanel
        ├── controls/           # ProofCtrl, StageTrack, TheoryFeedback, FailedSessionNote
        ├── agent/              # AgentDrawer, SurveyDrawerBody, IdeationDrawerBody,
        │                       # TheoryDrawerBody, ExperimentDrawerBody, WriterDrawerBody
        ├── skills/             # SkillsView, SkillLibrary, SkillCard, ClawHubPanel, SelectedSkillsPanel
        ├── config/             # ConfigView, ConfigForm, AuthGuidance
        ├── onboarding/         # OnboardingView, WizardPanel
        └── shared/             # StatusPill
```

#### Build output

`vite build` emits 77 modules → **231 kB JS** + **56 kB CSS** → `eurekaclaw/ui/static/`. The Python `SimpleHTTPRequestHandler` serves these files identically to before — no server changes required.

#### Developer workflow

| Task | Command |
|---|---|
| Start full dev environment | `make dev` |
| Build for production | `make build` |
| Type-check only | `make typecheck` |
| Run linter | `cd frontend && npm run typecheck` |

---

### [v0.6] — Research Workspace Redesign

**Goal**: Replace the flat grid of panels with a focused, mathematician-friendly workspace: a clickable agent track on the left, tabbed content on the right, and a humanistic agent drawer replacing raw terminal output.

#### Layout change: flat grid → workspace split

| Before | After |
|---|---|
| `session-panels-grid` — all panels always visible | `workspace-split` — 270 px agent track + tabbed main |
| Separate pipeline, agents, artifacts, log, output panels | Four tabs: **Live · Proof · Paper · Logs** |

#### Agent track (left column, `AgentTrack`)

- One card per pipeline stage: 📚 Survey · 💡 Ideation · 📐 Theory · 🧪 Validation · ✍️ Writing
- Colour-coded status badges: `active` (blue), `done` (green), `failed` (red), `pending` (grey)
- Each card shows a one-line humanized narrative derived from the current artifact state
- Click any card → slides open the **Agent Drawer** for that stage

#### Agent drawer (`AgentDrawer` + 5 role bodies)

Slide-in panel (440 px, CSS `transform` transition) with per-agent content:

| Agent | Drawer content |
|---|---|
| Survey | Papers list (year + title) · open problems · key mathematical objects |
| Ideation | Selected research direction blockquote · domain |
| Theory | Theorem statement block + lemma chain with confidence badges |
| Experiment | Alignment score · bounds verification table (theoretical vs empirical) |
| Writer | Word count · LaTeX paper excerpt |

Empty state shown for agents that haven't run yet.

#### Live tab (`LivePanel`)

- **Thinking dots animation** (`@keyframes thinking-bounce`) shown while a stage is running
- **Direction gate card** shown when ideation returns 0 directions (explains fallback to conjecture)
- **State messages** for paused / completed / failed runs

#### Proof tab (`ProofPanel`)

- **Theorem block** — formal statement or proof skeleton in monospace
- **Lemma chain** — numbered rows, each with name, formal text snippet, and confidence badge
  - `badge-verified` (green) · `badge-medium` (amber) · `badge-low` (grey)
- **Counterexample warning** banner when `counterexamples[]` is non-empty
- Auto-populated from `theory_state` artifact; shows empty state before theory runs

#### Theory feedback section (`TheoryFeedback`)

Shown only when session is **paused**; lives inside the paused proof-ctrl card:

- Collapsible toggle: "📐 Guide the proof before resuming"
- **Lemma chips** — one chip per lemma; clicking a chip pre-fills the textarea with `Lemma "<name>": `
- **Textarea** — freeform guidance; sent as `{feedback}` in the `POST /api/runs/<id>/resume` body
- On resume: feedback is injected into the theory domain context as `[Human guidance for this proof attempt]: <text>` and cleared after use

#### Backend additions for theory feedback (`eurekaclaw/ui/server.py`)

- `SessionRun.theory_feedback: str` — stores pending feedback between pause and resume
- `resume_run(run_id, feedback)` — new `feedback` parameter; stored in `run.theory_feedback`
- `_execute_resume()` — prepends `[Human guidance…]` to `domain` string, clears `theory_feedback`
- `snapshot_run()` — exposes `theory_feedback` field to frontend

#### Skills page additions

- `POST /api/skills/install` — installs a named ClawHub skill or copies seed skills
- `DELETE /api/skills/<name>` — removes a user-installed skill from `~/.eurekaclaw/skills/`
- Skills payload now includes `file_path` so the frontend can distinguish deletable vs seed skills
- **Source badges**: seed (blue) · auto-learned (teal) · manual (grey) · ClawHub (orange)
- **Stats bar**: usage count + success rate progress bar per skill
- **ClawHub install panel**: slug input + Install button + Install seeds button
- **Select all** button; library auto-reloads after install or delete

#### Humanized logs

`humanizeLogMessage(taskName, event)` maps raw task names to readable entries:

| Raw | Humanized |
|---|---|
| `survey` started | 📚 Literature survey started — scanning recent papers |
| `theory` completed | 📐 Proof complete — theorem sketch ready for review |
| `experiment` error | ⚠ Validation encountered an issue: … |

#### Auto tab-switching

- Moves to **Proof** tab when the theory task transitions `in_progress → completed`
- Moves to **Paper** tab when the whole run transitions to `completed`

---

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

| Panel | Content |
|---|---|
| `proof-ctrl-running` | "Pause proof" button + stage caption |
| `proof-ctrl-pausing` | Amber spinner + "Pausing…" + elapsed timer + "Finishing current lemma…" |
| `proof-ctrl-paused` | Amber dot + "Proof paused" + stage name + session ID + Resume + Copy buttons |
| `proof-ctrl-resuming` | Green spinner + "Resuming…" + "Loading checkpoint and rebuilding agent context" |

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

`restartPollingFast()` immediately resets the interval to 500 ms on any user-initiated pause/resume, then recalculates the correct interval after every response.

#### Frontend — Animations & Visual Design

- `ctrl-flash-in` — 300 ms spring animation plays when the paused or running panel first becomes visible
- `ctrl-slide-in` — 220 ms slide-in for the pausing/resuming bars
- Status pill: `pausing` = amber pulsing pill; `resuming` = green pulsing pill
- Sidebar dot: `pausing` = amber pulsing dot with ring ripple; `resuming` = green pulsing dot with ring ripple
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

- **Blank canvas** (`#new-session-pane`) — shown when no session is selected; centered card with the launch form
- **Session detail pane** (`#session-detail-pane`) — shown when a session is selected; contains topbar, status row, proof controls, pipeline/agent/artifact/log panels

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
- `#proof-ctrl-paused` — amber status dot + session ID + "Resume proof" button + "Copy command" button
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

### Component tree (v0.7+)

```
App
├── FlashOverlay
├── Sidebar
│   └── SessionList
└── <active view>
    ├── WorkspaceView
    │   ├── NewSessionForm         (when no session selected)
    │   └── SessionDetailPane      (when a session is selected)
    │       ├── SessionTopBar
    │       ├── ProofCtrl
    │       │   ├── StageTrack
    │       │   ├── RunningState
    │       │   ├── PausingState
    │       │   ├── PausedState
    │       │   │   └── TheoryFeedback
    │       │   └── ResumingState
    │       ├── WorkspaceSplit
    │       │   ├── AgentTrack
    │       │   │   └── AgentStepCard × 5
    │       │   └── WorkspaceTabs
    │       │       ├── LivePanel
    │       │       ├── ProofPanel
    │       │       ├── PaperPanel
    │       │       └── LogsPanel
    │       └── AgentDrawer
    │           └── {Survey|Ideation|Theory|Experiment|Writer}DrawerBody
    ├── SkillsView
    │   ├── SelectedSkillsPanel
    │   ├── ClawHubPanel
    │   └── SkillLibrary → SkillCard × n
    ├── ConfigView
    │   ├── CapabilityPanel
    │   └── ConfigForm → AuthGuidance
    └── OnboardingView
        └── WizardPanel
```

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

User clicks "Resume" (optionally with feedback text)
  │
  ├─ Optimistic UI: show resuming bar, clear feedback textarea
  │
  └─ POST /api/runs/<id>/resume  {feedback: "..."}
       │
       ├─ HTTP thread: run.status = "resuming", run.theory_feedback = feedback, persist
       │
       └─ _execute_resume thread starts
            │
            ├─ run.status = "running"
            ├─ if theory_feedback: domain += "[Human guidance]: <feedback>", clear
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

### Session status state machine

```
queued ──► running ──► pausing ──► paused ──► resuming ──► running
                │                                              │
                └──────────────► completed ◄──────────────────┘
                │
                └──────────────► failed
```
