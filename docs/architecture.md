# Architecture

## Overview

EurekaClaw is organized as a **multi-agent pipeline** coordinated by a `MetaOrchestrator`. Each agent is specialized for one stage of the research lifecycle. Artifacts are shared between agents via a central `KnowledgeBus`.

## Pipeline Stages

```
InputSpec (conjecture / domain / paper_ids)
        │
        ▼
 ┌─────────────────────────────────────────────────────────────┐
 │                    MetaOrchestrator                         │
 │                                                             │
 │  1. SurveyAgent ──────────────────────────► Bibliography   │
 │                                             ResearchBrief   │
 │  2. IdeationAgent ────────────────────────► ResearchBrief   │
 │                                             (5 directions)  │
 │  3. DivergentConvergentPlanner ───────────► selected dir.   │
 │                                                             │
 │  4. [GateController] ─── human review ────► approved dir.  │
 │                                                             │
 │  5. TheoryAgent ──────────────────────────► TheoryState     │
 │       ├── PaperReader                       (proven lemmas) │
 │       ├── GapAnalyst                                        │
 │       ├── ProofArchitect                                    │
 │       ├── LemmaDeveloper loop (Prover/Verifier/Refiner)     │
 │       ├── Assembler                                         │
 │       ├── TheoremCrystallizer                               │
 │       └── ConsistencyChecker                                │
 │                                                             │
 │  6. [theory_review_gate] ─── human review ► approved proof │
 │       (always shown; y=proceed, n=re-run theory with fix)   │
 │                                                             │
 │  7. ExperimentAgent (optional) ───────────► ExperimentResult│
 │                                                             │
 │  8. WriterAgent ──────────────────────────► LaTeX paper     │
 │                                             + PDF           │
 │  9. ContinualLearningLoop ────────────────► new skills      │
 └─────────────────────────────────────────────────────────────┘
        │
        ▼
 ResearchOutput → results/<session_id>/
   ├── paper.tex / paper.pdf
   ├── references.bib
   ├── theory_state.json
   ├── research_brief.json
   └── experiment_result.json
```

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

The `TheoryAgent` runs a **bottom-up proof pipeline** implemented in `inner_loop_yaml.py`:

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
```
for each open_goal:
    Prover → Verifier → (if failed) Refiner → repeat
    CounterexampleSearcher runs in parallel
    Stagnation detection: if same error N times → force Refiner
```

## LaTeX Compilation Pipeline

```
WriterAgent.execute()
    │  generates paper body
    ▼
_extract_latex()          — strip preamble, normalize envs, fix syntax
    ├── markdown → section headings
    ├── \begin{Proof} → \begin{proof}  (case normalization)
    ├── \endproof → \end{proof}
    ├── tikzpicture removal
    ├── QED box deduplication
    ├── orphan \end{X} removal
    └── unclosed \begin{X} auto-closing
    │
    ▼
LATEX_PREAMBLE + body + LATEX_END  →  paper.tex
    │
    ▼
save_artifacts()
    ├── write references.bib   ← BEFORE compile
    ├── _fix_missing_citations() — remove \cite{} with no .bib entry
    └── _compile_pdf()
          ├── pdflatex (pass 1 — generate .aux)
          ├── bibtex  (if references.bib exists)
          ├── pdflatex (pass 2 — resolve citations)
          └── pdflatex (pass 3 — finalize)
```

## Direction Planning Fallback

After the `IdeationAgent` runs, `MetaOrchestrator._handle_direction_gate()` calls `DivergentConvergentPlanner.diverge()` to generate 5 research directions. If the planner fails or returns an empty list (e.g. LLM parse error, API timeout), instead of silently proceeding with no direction the orchestrator **halts and prompts the user**:

1. Prints up to 5 open problems found by the survey as context.
2. Asks the user to type a hypothesis/direction manually.
3. Constructs a `ResearchDirection` from the input and writes it to `ResearchBrief`.
4. If the user enters nothing or presses Ctrl+C, raises `RuntimeError` and the session exits cleanly.

This is implemented in `_handle_manual_direction()` in `meta_orchestrator.py`.

## Theory Review Gate

After the TheoryAgent completes and before the WriterAgent runs, the `MetaOrchestrator` executes the `theory_review_gate` orchestrator task. This gate is **independent of `gate_mode`** and always fires.

**Flow:**
1. `GateController.theory_review_prompt()` prints a numbered lemma list with `✓ verified` / `~ low confidence` tags for each proved lemma, plus any open goals.
2. The user is asked: **y** (proceed) or **n** (flag the most problematic step).
3. On rejection:
   - User enters the lemma number (`L3`) or ID, and a description of the logical gap.
   - `MetaOrchestrator._handle_theory_review_gate()` finds the theory task, injects the feedback as `[User feedback]: ...`, resets it to `PENDING`, and re-runs the TheoryAgent once.
   - After the revision, the updated sketch is shown again for a final look (no further retry).
4. On second rejection, the pipeline proceeds to the WriterAgent anyway with a warning.

## Pause / Resume

The TheoryAgent supports graceful pausing at stage boundaries via `ProofCheckpoint` (`agents/theory/checkpoint.py`).

**Pause flow:**
- `eurekaclaw pause <session_id>` or **Ctrl+C** writes `~/.eurekaclaw/sessions/<session_id>/pause.flag`.
- At each stage boundary in `inner_loop_yaml._run_once()`, `ProofCheckpoint.is_pause_requested()` is checked.
- When detected: clears the flag, saves `checkpoint.json` (current stage + full `TheoryState`), raises `ProofPausedException`.
- `ProofPausedException` propagates through both `_run_once` and `agent.py` (explicit re-raise in both `except Exception` handlers).

**Resume flow:**
- `eurekaclaw resume <session_id>` loads `checkpoint.json`, reconstructs `TheoryState`, and re-runs the TheoryAgent starting at the saved stage.

**Checkpoint file:** `~/.eurekaclaw/sessions/<session_id>/checkpoint.json`

## Post-Run Learning

```
ContinualLearningLoop.post_run()
    ├── extract failures (FailedAttempt[]) from TheoryState
    ├── deduplicate — only unique failure patterns
    ├── compress successes — proof text trimmed to 300 chars
    ├── SkillEvolver.distill_from_session()
    │       → new SkillRecord .md files in ~/.eurekaclaw/skills/
    └── (rl/madmax modes) ProcessRewardModel scoring
```
