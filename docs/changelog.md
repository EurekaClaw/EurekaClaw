# Changelog

Summary of all updates from `UPDATES.md`.

---

## 2026-03-20 (continued — PRs #23, #28, #29, #30, #31, #33)

### 8. Principled Prover Confidence Scoring

The `Prover` now replaces purely format-based heuristics with a structured LLM self-assessment block appended to every proof response.

**Prompt change:** the system prompt instructs the LLM to append a `\`\`\`json` block after the proof body:

```json
{
  "confidence": 0.0-1.0,
  "completeness": "complete|partial|sketch",
  "gaps": ["...uncertain step descriptions..."],
  "weakest_step": "...",
  "techniques_used": ["..."]
}
```

Calibration guide embedded in the prompt:

| Range | Meaning |
|---|---|
| ≥ 0.95 | Every step elementary or from a named theorem; no hand-waving |
| 0.80–0.94 | All key steps present; at most one routine calculation left implicit |
| 0.60–0.79 | Sketch correct but one non-trivial step not fully worked out |
| 0.40–0.59 | Main idea right but genuine gap flagged with `[GAP: ...]` |
| < 0.40 | Incomplete proof or possibly wrong approach |

**`_parse_proof_attempt()` pipeline (6 steps):**
1. Extract inline `[GAP: ...]` tags
2. Parse the structured JSON self-assessment block
3. Heuristic fallback if no valid block (presence of "QED", "□", "this completes")
4. Citation-integrity check: penalty −0.15 per uncited lemma ID (cap −0.30)
5. Weasel-word penalty: −0.05 per "clearly"/"obviously"/etc. (cap −0.15)
6. Strip JSON block from stored `proof_text`; extract optional Lean4 sketch

### 9. Verifier Bug Fix: Format Code Error

`Verifier._peer_review()` was raising `Unknown format code 'f' for object of type 'str'` because `settings.verifier_pass_confidence` returned a `str` via Pydantic's env-var parsing. Fixed by explicit `float()` cast before `:.2f` formatting.

### 10. pdfTeX Font Expansion Fix

`! pdfTeX error (font expansion): auto expansion is only possible with scalable fonts` caused by `microtype`'s automatic font expansion being incompatible with `lmss` (Latin Modern Sans) on TeX Live 2022. Fixed by passing `expansion=false` to `\RequirePackage[expansion=false]{microtype}` in `eureka.cls`.

### 11. Token Limit UI Sliders (Extended)

Five additional token-limit controls added to the Settings tab:

| Setting | UI label | Default |
|---|---|---|
| `MAX_TOKENS_ASSEMBLER` | Assembler | 4096 |
| `MAX_TOKENS_CRYSTALLIZER` | Crystallizer | 2500 |
| `MAX_TOKENS_ARCHITECT` | Proof architect | 3000 |
| `MAX_TOKENS_ANALYST` | Analysis stages | 1600 |
| `MAX_TOKENS_SKETCH` | Proof sketch | 600 |

`server.py`'s `_CONFIG_FIELDS` mapping updated to expose all 12 token-limit knobs to the UI.

All hardcoded `max_tokens=...` literals across theory and learning agent files replaced with `settings.max_tokens_*` references.

### 12. Human Intervention for Empty Survey

When the survey stage completes with zero papers found, the pipeline pauses and prompts the user:

```
⚠ Survey stage completed but found 0 papers.
Please provide a comma-separated list of paper IDs/titles to retry,
or press Enter to proceed without papers:
```

If the user provides titles, the survey task is re-injected with the paper list and re-executed once. Implemented in `MetaOrchestrator._handle_empty_survey_fallback()`.

### 13. ProofCheckpoint Bug Fixes (Issue #27)

| Bug | Fix |
|---|---|
| `cp.checkpoint_path` AttributeError — public property was missing | Added `@property checkpoint_path → self._checkpoint` |
| `cli.py resume` used wrong meta key `"research_brief"` (dict) | Fixed to `json.loads(meta.get("research_brief_json", "{}") or "{}")` |
| `cli.py resume` used wrong attribute `exc.paused_before_stage` | Fixed to `exc.stage_name` |

### 14. Minimax LLM Backend (PR #23)

New backend shortcut `LLM_BACKEND=minimax`:

| Variable | Description |
|---|---|
| `MINIMAX_API_KEY` | Minimax API key |
| `MINIMAX_MODEL` | Minimax model name (e.g. `abab7-chat`) |

**`active_model` / `active_fast_model` properties** added to `Config` — resolve the correct model string for any backend (Anthropic, Minimax, OpenAI-compat). All agents and theory stages updated to use `settings.active_model` / `settings.active_fast_model` instead of hardcoded model names.

### 15. PDF Extraction via Docling (PR #23)

`PaperReader._extract_from_paper_pdf()` fetches the full arXiv PDF via Docling, filters to theorem/lemma sections with a regex pass, then runs the LLM extractor over the rich excerpt instead of the abstract only.

Enable with the `[pdf]` optional extra:

```bash
pip install eurekaclaw[pdf]
```

### 16. Memory Relevance-Based Retrieval (PR #30)

Tier 4 domain memories are now ranked by **cosine similarity** to the current task query instead of most-recently-written ordering.

- `_index.json` now stores a `"embedding"` field per memory file (computed at write time using `embedding_utils.get_embedding()`)
- `MemoryManager.load_for_injection(domain, k, query)` accepts a `query` argument; if provided, ranks candidates by cosine similarity and returns the top-k most relevant files
- New helper module: `eurekaclaw/memory/embedding_utils.py` (`get_embedding()`, `cosine_similarity()`)

### 17. smile.sty Math Macro Package (PR #28)

A comprehensive SMiLe-group math macro package (`smile.sty`) is now bundled with the template:

- Blackboard bold shortcuts: `\RR`, `\EE`, `\PP`, `\NN`, `\ZZ`, `\QQ`, `\CC`, …
- Calligraphic shortcuts: `\cA` … `\cZ`
- Bold vectors (mathbf family): `\xb`, `\Wb`, … and (bm family): `\bx`, `\bW`, …
- Bold Greek: `\balpha`, `\bbeta`, `\bGamma`, …
- Norm/bracket macros: `\norm{x}`, `\nbr{x}`, `\bignorm{x}`, `\opnorm{x}{p}`

The writer agent system prompt is updated to list all available macros and instruct the LLM to use them instead of redefining equivalents.

### 18. OpenClaw Hub Integration (PR #31)

Skills can now be installed directly from the [ClawHub](https://clawhub.ai/) registry:

```bash
eurekaclaw install-skills <skillname>
# e.g. eurekaclaw install-skills steipete/github
```

`install-skills` with no argument continues to install all bundled seed skills. The `clawhub` CLI must be installed separately. The implementation lives in `eurekaclaw/skills/from_hub.py`.

### 19. Bug Fix: pause AttributeError (PR #33)

`cli.py` referenced `exc.paused_before_stage` but `ProofPausedException` stores the field as `stage_name`. Fixed both call sites so pausing a run no longer crashes with `AttributeError`.

### 20. Direction Planning Fallback (PR #33)

When `DivergentConvergentPlanner.diverge()` returns an empty list or throws an exception, the orchestrator now halts and prompts the user to enter a research direction manually instead of silently continuing with no direction. The survey's open problems are shown as context. Empty input or Ctrl+C raises `RuntimeError` and exits cleanly.

---

## 2026-03-20

### 1. Theory Review Gate

A new `theory_review_gate` orchestrator task is inserted between the TheoryAgent and WriterAgent in `default_pipeline.yaml`. It is always shown, regardless of `--gate` mode.

- Displays a numbered lemma chain (L1, L2, …) with `✓ verified` / `~ low confidence` tags.
- **y / Enter** → proceed to writer.
- **n** → user specifies the most problematic step (by number or ID) and describes the issue. The TheoryAgent re-runs once with the feedback injected into its task description, then shows the updated sketch once more.

### 2. Pause / Resume

Two new CLI commands and a graceful `SIGINT` handler:

| Command | Description |
|---|---|
| `eurekaclaw pause <session_id>` | Write `pause.flag`; theory agent stops at next stage boundary and saves `checkpoint.json` |
| `eurekaclaw resume <session_id>` | Load checkpoint and continue from the saved stage |
| **Ctrl+C** during `prove` | Same as `pause` — writes flag instead of raising `KeyboardInterrupt` |

Checkpoint file: `~/.eurekaclaw/sessions/<session_id>/checkpoint.json`

### 3. ProofArchitect Improvements

- **`source=None` crash fixed:** `item.get("source") or ""` instead of `item.get("source", "")` so a JSON `null` value never passes through as `None`.
- **3-layer fallback:** full plan (4–10 lemmas) → 3-lemma simplified plan → single `main_result`. Single-goal is now truly a last resort.

### 4. Citation Quality Improvements

- **Assembler** prompt requires explicit `[lemma_id]` citations in the assembled proof (e.g., `By [arm_pull_count_bound], …`).
- **ConsistencyChecker** receives the list of proved lemma IDs and verifies all appear in the proof; returns `uncited_lemmas`.
- **Retry routing:** when ConsistencyChecker failure is citation-related ("uncited" / "missing citation"), the retry loop re-runs the Assembler as well as the Crystallizer — not just the Crystallizer.

### 5. TheoremCrystallizer Fixes

- `max_tokens` raised from 1500 → 2500 to prevent mid-expression truncation of LaTeX formulas.
- Added explicit no-truncation constraint for math environments.

### 6. Knowledge Graph Write Timing

Tier 3 KG writes now trigger whenever `proven_count > 0` (i.e., after any lemma is proved), not only when the full consistency check passes. Lemma nodes and dependency edges are preserved even when crystallization fails.

### 7. Bug Fixes

| File | Bug | Fix |
|---|---|---|
| `agents/theory/inner_loop_yaml.py` | `cp.delete()` AttributeError at checkpoint clear | `cp.delete()` → `cp.clear()` |
| `agents/theory/inner_loop_yaml.py` | `ProofPausedException` swallowed by bare `except Exception` | Added `isinstance(e, ProofPausedException): raise` before handler |
| `agents/theory/agent.py` | `ProofPausedException` swallowed in agent execute | Added explicit re-raise |
| `orchestrator/meta_orchestrator.py` | `_init_brief` created a new session UUID, mismatching `pause.flag` path | `session_id` reuses `bus.session_id` |

---

## 2026-03-19

### 1. Robust Lemma Decomposer Parsing

`_parse_lemmas` in `agents/theory/decomposer.py` now uses a 4-pass extraction strategy instead of 2, preventing the "Empty lemma list from decomposer" fallback in most cases:

| Pass | Strategy |
|---|---|
| 1 | JSON inside ` ```json ``` ` or plain ` ``` ``` ` code fence |
| 2 | First JSON object `{...}` — checks 7 key names: `lemmas`, `steps`, `subgoals`, `proof_steps`, `lemma_list`, `components`, `parts` |
| 3 | First JSON array `[...]` — accepted directly as lemma list |
| 4 | Plain-text numbered/bulleted list heuristic |

`_normalize_list` accepts flexible field names per item (`id`/`lemma_id`/`name`/`title`, `statement`/`formal_statement`/`hypothesis`/`content`, etc.) so variant LLM output schemas are handled without falling back to single-theorem mode.

The same 4-pass strategy was also applied to `ProofArchitect._parse_lemmas`.

### 2. UI Polling Log Suppression

`GET /api/runs/<id> 200` status-poll requests are now logged at `DEBUG` level instead of `INFO`, removing repetitive log noise during long runs.

### 3. Bug Fixes

| File | Bug | Fix |
|---|---|---|
| `agents/survey/agent.py` | `ValueError: substring not found` on unclosed ` ```json ` block | Wrapped `text.index` in try/except |
| `agents/base.py` | `run_agent_loop` ignoring `SURVEY_MAX_TURNS` setting | Uses dynamic `AsyncRetrying` now |
| `main.py` | `NameError: name 'Path' is not defined` in `save_artifacts` | Added `from pathlib import Path` |
| `ui/server.py` | `GET /api/runs/...` spamming the log | Demoted to `DEBUG` for 200 polling responses |

### 4. Always-On Stage Summary Cards

`orchestrator/gate.py` now prints a Rich summary card after every completed pipeline stage regardless of `GATE_MODE`:

| Stage | Card shows |
|---|---|
| `survey` | Papers found, open problems, key mathematical objects |
| `theory` | Proof status, per-lemma breakdown with confidence tags |
| `experiment` | Alignment score, per-lemma numerical check results |
| `writer` | Full session summary before final output |

### 5. Human Gate Improvements

- **Text feedback input:** after approving a gate, users can type a correction or hint injected into the next agent's task via `get_user_feedback()`
- **Auto-escalation:** if ≥1 lemma has `verified=False` after theory stage, gate auto-escalates from `auto` to `human` with full lemma confidence breakdown
- **Default changed:** `GATE_MODE` default changed from `none` to `auto`

### 6. Proof Readability Enforcement (WriterAgent)

`ENFORCE_PROOF_STYLE=true` (default) injects `_PROOF_STYLE_RULES` into writer prompts:
- No skip words ("clearly", "trivially", "by standard arguments") without immediate justification
- Every inequality must name the lemma or theorem it uses
- Each lemma proof opens with 1–2 sentences of informal explanation
- Low-confidence lemmas tagged `\textcolor{orange}{\textbf{[Unverified step]}}` in PDF
- Limitations section explains all unverified steps
- Added `\usepackage{xcolor}` to `LATEX_PREAMBLE`

### 7. Targeted Numerical Testing (ExperimentAgent)

ExperimentAgent now separates proven lemmas into `verified` and `low_confidence` groups:
- For each low-confidence lemma: runs dedicated numerical test, computes `violation_rate`
- Lemmas with `violation_rate > 1%` flagged as `numerically_suspect`
- Experiment stage summary card shows per-lemma check results with color coding
- WriterAgent adds stronger warnings for `numerically_suspect` lemmas

### 8. CLI Default Output Directory

All three CLI commands (`prove`, `explore`, `from-papers`) now default to `./results` if `--output` is not specified.

### 9. Bibliography & Citation Fix

Removed `\cite{}` → `?` bug in output PDFs:
- `_fix_missing_citations()` surgically removes `\cite{}` keys that have no matching entry in `references.bib`
- `LATEX_END` split into `LATEX_END_WITH_BIB` / `LATEX_END_NO_BIB` — `\bibliography{references}` only added when `.bib` is non-empty
- WriterAgent prompt instructs LLM to use exact cite keys (same as `_generate_bibtex`)

### 10. LaTeX Extraction Improvements

Extended `_extract_latex` in WriterAgent with:
- Markdown heading → LaTeX section conversion
- `tikzpicture` environment removal
- Environment name normalization additions: `rem`→`remark`, `rema`→`remark`, `prop`→`proposition`, `defin`→`definition`, `corolary`→`corollary`, `Cor`→`corollary`, `Thm`→`theorem`, `Lem`→`lemma`
- `\endproof` → `\end{proof}` substitution
- QED box removal (`\begin{flushright}$\square$\end{flushright}`)
- Two-pass `_close_open_environments`: (1) remove orphaned `\end{X}`, (2) append missing `\end{X}`

---

## 2026-03-18

### 1. Context Compression

Optimization summary:

| Stage | Before | After | Saving |
|---|---|---|---|
| Formalizer model | `opus` | `haiku` | ~90% cost per call |
| Formalizer re-run | Every iteration | Only on change | Saves N-1 calls |
| Proven lemma context | 200-char proof text | Statement only (120) | ~40% input tokens |
| Verifier (high-conf) | Always LLM call | Auto-accept ≥ 0.85 | ~30% fewer calls |
| Verifier proof text | Raw (up to 3000 chars) | Head+tail (1000 chars) | ~67% input tokens |
| Agent loop history | Accumulates forever | Compressed every 6 turns | ~60% input tokens |
| Stagnation | Wastes 3+ iterations | Forced refinement | Saves full iterations |

**Run performance:** typical run now ~20 LLM calls (down from ~35); worst case ~55 (down from ~100).

**Agent `max_turns` reductions:**

| Agent | Before | After |
|---|---|---|
| SurveyAgent | 15 | 8 |
| IdeationAgent | 5 | 3 |
| ExperimentAgent | 10 | 5 |
| WriterAgent | 5 | 3 |

**New config knobs:** `CONTEXT_COMPRESS_AFTER_TURNS`, `AUTO_VERIFY_CONFIDENCE`, `STAGNATION_WINDOW`

### 2. Configurable Token Limits Per Call Type

7 new `.env` variables:

| Variable | Default | Applies to |
|---|---|---|
| `MAX_TOKENS_AGENT` | `8192` | All agent reasoning loops |
| `MAX_TOKENS_PROVER` | `4096` | Proof generation |
| `MAX_TOKENS_PLANNER` | `4096` | Research direction planning |
| `MAX_TOKENS_DECOMPOSER` | `2048` | Lemma decomposition |
| `MAX_TOKENS_FORMALIZER` | `2048` | Formalization, refiner, counterexample |
| `MAX_TOKENS_VERIFIER` | `1024` | Proof verification |
| `MAX_TOKENS_COMPRESS` | `512` | Context compression |

UI sliders added in the Settings tab for all 7 values.

### 3. Multi-Backend LLM Support

Three named backends in `config.py` and `llm/factory.py`:

| Backend | `LLM_BACKEND=` | Notes |
|---|---|---|
| Anthropic native | `anthropic` | Default |
| OpenRouter | `openrouter` | Set `OPENAI_COMPAT_API_KEY=sk-or-...` |
| Local (vLLM/Ollama) | `local` | Defaults to `http://localhost:8000/v1` |

**ccproxy / OAuth fallback:** if `ANTHROPIC_API_KEY` is empty, automatically reads `~/.claude/.credentials.json` and routes through ccproxy (allows Claude Pro/Max users to run without a separate API key).

### 4. Additional Tuning Knobs

| Variable | Default | Effect |
|---|---|---|
| `SURVEY_MAX_TURNS` | `8` | Tool-use turns in SurveyAgent |
| `THEORY_STAGE_MAX_TURNS` | `6` | Turns per theory stage |
| `WRITER_MAX_TURNS` | `4` | Turns for paper generation |
| `ARXIV_MAX_RESULTS` | `10` | Hard cap on arXiv results |
| `LLM_RETRY_ATTEMPTS` | `5` | Retry attempts on 5xx / rate-limit errors |
| `LLM_RETRY_WAIT_MIN` / `MAX` | `4` / `90` | Exponential backoff bounds |

### 5. Domain Plugin Architecture

New three-tier plugin system:

```
EurekaClaw (general pipeline)
    └── DomainPlugin (e.g. MAB)
            └── Workflow (per-domain prompt guidance)
```

**New files:**
- `domains/base.py` — `DomainPlugin` ABC with 4 methods
- `domains/__init__.py` — `@register_domain` decorator + `resolve_domain()`
- `domains/mab/` — MAB domain plugin (GaussianBandit, BernoulliBandit, 4 tools, 4 skills, 3-level benchmark)

**Core changes:**
- `SkillRegistry.add_skills_dir()` — load skills from domain directories
- `build_default_registry()` — now domain-agnostic; domain tools registered via plugin
- `MetaOrchestrator` — accepts `domain_plugin` parameter
- `EurekaSession.run()` — auto-detects domain plugin from `InputSpec.domain`

### 6. LaTeX Compilation Robustness

- Added 7 `\newtheorem` declarations to `LATEX_PREAMBLE`: `assumption`, `maintheorem`, `conjecture`, `claim`, `example`, `fact`, `observation`
- Environment name normalization in `_extract_latex` (step 6): mis-cased names corrected
- `_close_open_environments()` — new static method, stack-based, prevents `\begin{tabular}` truncation from causing fatal errors
- Removed `_rescue_compile` and `paper_rescue.tex` fallback entirely
- Full bibtex-aware compile sequence: `pdflatex → bibtex → pdflatex → pdflatex`

### 7. Bibliography & Reference Resolution

- **Write order fixed:** `references.bib` saved **before** `_compile_pdf()` is called
- **bibtex added to compile sequence:** previously only `pdflatex` ran twice
- **Cite key consistency:** `_compute_cite_keys()` in WriterAgent uses identical algorithm to `_generate_bibtex` in `main.py`
- **Duplicate key handling:** `_generate_bibtex` deduplicates with `a`, `b`, … suffixes
- `ResearchOutput.bibliography_json` field added

### 8. Experiment Mode Control

New `EXPERIMENT_MODE` env var:
- `auto` — skip experiment if formal statement has no quantitative signals
- `true` — always run experiment stage
- `false` — always skip experiment stage
