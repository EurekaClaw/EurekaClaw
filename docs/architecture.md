# Architecture

## Overview

EurekaClaw is organized as a **multi-agent pipeline** coordinated by a `MetaOrchestrator`. Each agent is specialized for one stage of the research lifecycle. Artifacts are shared between agents via a central `KnowledgeBus`.

## Pipeline Stages

<p align="center">
  <img src="images/pipeline-main.svg" alt="EurekaClaw Main Pipeline" width="820"/>
</p>

## Core Components

### KnowledgeBus

Central in-memory artifact store shared by all agents. All data flows through it — no agent holds private state between turns.

```
KnowledgeBus
├── ResearchBrief    — survey findings, selected direction
├── TheoryState      — proof state machine (lemma DAG, proofs, goals)
├── Bibliography     — all papers found during survey
├── ExperimentResult — numerical validation results
└── TaskPipeline     — current task execution plan
```

Artifacts are persisted to `~/.eurekaclaw/runs/<session_id>/` at the end of each session.

### Agent Session & Context Compression

Each agent maintains a conversation history (`AgentSession`) through its tool-use loop. To prevent unbounded context growth:
- History is **compressed every N turns** (configurable via `CONTEXT_COMPRESS_AFTER_TURNS`, default 6)
- A fast model summarizes the history into bullet points
- The full conversation is replaced with the summary

### Skill Injection

Before each agent call, the `SkillInjector` retrieves the top-k most relevant skills from the skill bank and injects them into the system prompt as examples. This is the primary mechanism for cross-session learning.

### Domain Plugin System

Domain-specific behavior (tools, skills, workflow hints) is injected via `DomainPlugin` classes. The correct plugin is auto-detected from the domain string or conjecture keywords. See [domains.md](domains.md).

## Data Models

### TheoryState — Proof State Machine

```
TheoryState
├── informal_statement      — plain-English conjecture
├── formal_statement        — LaTeX-formalized theorem
├── known_results[]         — KnownResult extracted from literature
├── research_gap            — GapAnalyst's finding
├── proof_plan[]            — ProofPlan (provenance: known/adapted/new)
├── lemma_dag{}             — LemmaNode graph (dependencies)
├── proven_lemmas{}         — lemma_id → ProofRecord
├── open_goals[]            — remaining lemma_ids to prove
├── failed_attempts[]       — FailedAttempt history
├── counterexamples[]       — Counterexample discoveries
├── assembled_proof         — final combined proof text
└── status                  — pending/in_progress/proved/refuted/abandoned
```

### ResearchBrief — Planning State

```
ResearchBrief
├── domain, query, conjecture
├── directions[]            — ResearchDirection (scored 0-1)
│     ├── novelty_score
│     ├── soundness_score
│     ├── transformative_score
│     └── composite_score   — weighted average
├── selected_direction      — chosen after convergence
└── open_problems[], key_mathematical_objects[]
```

## Theory Agent Inner Loop (7 Stages)

The `TheoryAgent` runs a **bottom-up proof pipeline** implemented in `inner_loop_yaml.py`. The full loop structure including all retry paths is shown in the Pipeline Stages diagram above. Stage I/O summary:

| Stage | Class | Input | Output |
|---|---|---|---|
| 1 | `PaperReader` | Bibliography | `known_results[]` |
| 2 | `GapAnalyst` | known_results + conjecture | `research_gap` |
| 3 | `ProofArchitect` | research_gap | `proof_plan[]` (provenance-annotated) |
| 4 | `LemmaDeveloper` | proof_plan, open_goals | `proven_lemmas{}` |
| 5 | `Assembler` | proven_lemmas | `assembled_proof` |
| 6 | `TheoremCrystallizer` | assembled_proof | `formal_statement` |
| 7 | `ConsistencyChecker` | full TheoryState | consistency report |

The `LemmaDeveloper` runs its own inner loop per lemma:

<p align="center">
  <img src="images/pipeline-theory.svg" alt="TheoryAgent Inner Loop" width="860"/>
</p>

**Provenance:** Each lemma in the proof plan is tagged `known` (directly citable), `adapted` (needs modification), or `new` (must be fully proved). Only `adapted` and `new` lemmas enter the LemmaDeveloper loop.

## LaTeX Compilation Pipeline

<p align="center">
  <img src="images/pipeline-latex.svg" alt="LaTeX Compilation Pipeline" width="700"/>
</p>

## Direction Planning Fallback

After `IdeationAgent` runs, `MetaOrchestrator._handle_direction_gate()` checks `brief.directions`. If the list is empty (ideation returned 0 directions, the planner failed, or a dependency was skipped), **human intervention is always required** regardless of `input_mode`:

**Exploration / reference mode** — `DivergentConvergentPlanner.diverge()` is called first to attempt to generate 5 directions. If the planner also fails or returns empty, `_handle_manual_direction()` is called.

**Prove / detailed mode** — The planner is skipped. `_handle_manual_direction()` is called directly, showing the user's conjecture as the default direction. The user presses Enter to accept it or types a new one.

`_handle_manual_direction()` behavior:

1. Prints up to 5 open problems found by the survey as context.
2. If `brief.conjecture` is set, shows it as a suggested default.
3. Asks the user to confirm or type a different direction (empty input accepts the conjecture default if available).
4. Constructs a `ResearchDirection` from the input and writes it to `ResearchBrief`.
5. If the user provides nothing and no conjecture default exists, or presses Ctrl+C, raises `RuntimeError` and the session exits cleanly.

This is implemented in `_handle_manual_direction()` in `meta_orchestrator.py`.

## Pause / Resume

The proof pipeline supports immediate pause at any point during execution.

**Triggering a pause:**
- `Ctrl+C` in the terminal running `eurekaclaw prove` or `eurekaclaw resume`
- `eurekaclaw pause <session-id>` from a separate terminal

**How it works:**

`cli.py` wraps every proof coroutine in `_run_with_pause_support(coro, cp)`:
- Registers a SIGINT handler via `loop.add_signal_handler` that calls `task.cancel()`
- Runs a background 1-second poller that watches for the `pause.flag` file (written by `eurekaclaw pause`) and cancels the task if found

When the task is cancelled, `inner_loop_yaml.run()` catches `asyncio.CancelledError` at the stage boundary, saves a checkpoint (`~/.eurekaclaw/sessions/<id>/checkpoint.json`) with all lemmas proved so far, and raises `ProofPausedException`.

**Checkpoint contents:** proven lemmas, open goals, current outer iteration, remaining stage spec, research brief.

**Resuming:** `eurekaclaw resume <session-id>` reloads the checkpoint and continues from the saved stage.

## Theory Review Gate

After the TheoryAgent completes and before the WriterAgent runs, the `MetaOrchestrator` executes the `theory_review_gate` orchestrator task. This gate is **independent of `gate_mode`** and always fires.

**Flow:**
1. `GateController.theory_review_prompt()` prints a numbered lemma list with `✓ verified` / `~ low confidence` tags for each proved lemma, plus any open goals.
2. The user is asked: **y** (proceed) or **n** (flag the most problematic step).
3. On rejection:
   - User enters the lemma number (`L3`) or ID, and a description of the logical gap.
   - `MetaOrchestrator._handle_theory_review_gate()` finds the theory task, injects the feedback as `[User feedback]: ...`, resets it to `PENDING`, and re-runs the full TheoryAgent.
   - After the revision, the updated sketch is shown again — the user can reject and re-run repeatedly.
4. The loop continues until the user approves or the retry count reaches `THEORY_REVIEW_MAX_RETRIES` (default 3), after which the pipeline proceeds to the WriterAgent with a warning.

## Post-Run Learning

<p align="center">
  <img src="images/pipeline-learning.svg" alt="Post-Run Learning" width="660"/>
</p>
