# Changelog

Summary of all updates from `UPDATES.md`.

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
