# EurekaClaw Updates

# 2026-03-21 (xuheng branch)

## 1. `eurekaclaw onboard` — Interactive Setup Wizard

A new `onboard` CLI command walks users through configuring all `.env` options interactively, then writes (or updates) the file.

```bash
eurekaclaw onboard
eurekaclaw onboard --env-file ~/.eurekaclaw/.env   # custom path
eurekaclaw onboard --non-interactive               # use defaults, no prompts
eurekaclaw onboard --reset                         # overwrite existing .env
```

The wizard is split into 5 sections:

| Section | Settings covered |
|---------|-----------------|
| 1 — LLM Backend | `LLM_BACKEND` (anthropic / oauth / openrouter / openai_compat / local / minimax) |
| 2 — API Credentials | API keys, `ANTHROPIC_AUTH_MODE`, `ANTHROPIC_BASE_URL`, `CCPROXY_PORT`, model selection |
| 3 — Search & Tool APIs | `BRAVE_SEARCH_API_KEY`, `SERPAPI_KEY`, `WOLFRAM_APP_ID`, `S2_API_KEY` |
| 4 — System Behaviour | `OUTPUT_FORMAT`, `GATE_MODE`, `EUREKACLAW_MODE`, `THEORY_PIPELINE`, `EXPERIMENT_MODE`, `EUREKACLAW_DIR` |
| Advanced (opt-in) | Proof quality, paper reader, all token limits, agent loop tuning |

After writing `.env`, the wizard offers to run `install-skills` automatically.

| File | Change |
|------|--------|
| `eurekaclaw/onboard.py` | New file — full wizard implementation |
| `eurekaclaw/cli.py` | Registered `onboard` command (thin stub calling `run_onboard`) |

## 2. Windows Installer (`install_win.ps1`)

A native PowerShell installer for Windows users, equivalent to `bash install.sh --install-method git`.

```powershell
# One-liner
powershell -c "irm https://eurekaclaw.ai/install_win.ps1 | iex"

# Local file
powershell -ExecutionPolicy Bypass -File install_win.ps1

# Options
powershell -ExecutionPolicy Bypass -File install_win.ps1 -GitDir C:\eurekaclaw -NoOnboard
```

The installer:
- Checks for Python ≥ 3.11 and Git (with `winget` install hints if missing)
- Clones or updates the repo to `~\eurekaclaw`
- Creates a `.venv` and pip-installs EurekaClaw with all extras
- Adds `~\eurekaclaw\.venv\Scripts\` to the user's PATH permanently
- Installs seed skills
- Suggests `eurekaclaw onboard` as the next step

## 3. Windows Line-Ending Fix (`.gitattributes`)

Added `.gitattributes` enforcing `eol=lf` for all `.sh`, `.py`, `.md`, `.toml`, `.yaml`, and other text files. Prevents `bash` from failing with `": invalid option nameet: pipefail"` on Windows clones where `core.autocrlf=true` converts LF → CRLF.

Also removed the erroneous `.gitattributes` entry from `.gitignore`.

---

# 2026-03-20 (xuheng branch)

## 1. Minimax Backend Support

Added `LLM_BACKEND=minimax` as a first-class shortcut alongside `openrouter` and `local`.

| File | Change |
|------|--------|
| `config.py` | Added `minimax_api_key` / `minimax_model` fields; added `active_model` and `active_fast_model` properties that resolve to the correct model string for the active backend |
| `llm/factory.py` | Registered `minimax` alias → `https://api.minimaxi.chat/v1`; picks up `MINIMAX_API_KEY` and `MINIMAX_MODEL` automatically |
| `.env.example` | Documented `LLM_BACKEND=minimax`, `MINIMAX_API_KEY`, `MINIMAX_MODEL` |

## 2. `active_model` / `active_fast_model` Rollout

All hardcoded `settings.eurekaclaw_model` and `settings.fast_model` calls have been replaced with `settings.active_model` and `settings.active_fast_model` respectively, making the full inference pipeline backend-agnostic.

Affected files: `agents/base.py`, `agents/theory/assembler.py`, `agents/theory/consistency_checker.py`, `agents/theory/counterexample.py`, `agents/theory/decomposer.py`, `agents/theory/formalizer.py`, `agents/theory/gap_analyst.py`, `agents/theory/proof_architect.py`, `agents/theory/prover.py`, `agents/theory/refiner.py`, `agents/theory/resource_analyst.py`, `agents/theory/theorem_crystallizer.py`, `agents/theory/verifier.py`, `agents/survey/agent.py`, `orchestrator/planner.py`, `evaluation/evaluator.py`, `learning/prm_scorer.py`, `skills/evolver.py`.

## 3. PDF Extraction Pipeline for PaperReader

`agents/theory/paper_reader.py` gains a new `_extract_from_paper_pdf()` method backed by [Docling](https://github.com/docling-project/docling).

**Pipeline:**
1. Fetch the full paper PDF from `https://arxiv.org/pdf/{arxiv_id}` via Docling (handles HTTP + layout analysis).
2. `_extract_math_sections()` filters the resulting Markdown to theorem/lemma-bearing sections (≤ 8 000 chars) using regex patterns on heading names and bold theorem labels.
3. The existing LLM prompt runs over the filtered excerpt instead of just the abstract, yielding far more extracted `KnownResult` objects.

Docling is optional: install with `pip install 'eurekaclaw[pdf]'`. Falls back gracefully if not installed.

| File | Change |
|------|--------|
| `agents/theory/paper_reader.py` | Added `_extract_math_sections()`, `_RESULT_HEADING_RE`, `_RESULT_BODY_RE`, `_extract_from_paper_pdf()` |
| `pyproject.toml` | Added `[pdf]` optional extra: `docling>=2.0` |

## 4. Bug Fixes

| File | Fix |
|------|-----|
| `agents/survey/agent.py` | `_parse_survey_output`: moved `text.index("```", start)` inside the `try` block and catches `ValueError` in addition to `json.JSONDecodeError`, preventing `"substring not found"` crash when the LLM returns an unclosed ` ```json ` fence |
| `agents/theory/inner_loop_yaml.py` | `cp.delete()` → `cp.clear()` (correct method name on `ProofCheckpoint`) |

---

# 2026-03-19 (shiyuan branch)

## 1. Robust Lemma Decomposer Parsing

`_parse_lemmas` in `agents/theory/decomposer.py` now uses a 4-pass extraction strategy
instead of 2, preventing the "Empty lemma list from decomposer" fallback in most cases:

| Pass | Strategy |
|---|---|
| 1 | JSON inside ` ```json ``` ` or plain ` ``` ``` ` code fence (regex, not `str.index`) |
| 2 | First JSON object `{...}` in text — checks 7 key names: `lemmas`, `steps`, `subgoals`, `proof_steps`, `lemma_list`, `components`, `parts` |
| 3 | First JSON array `[...]` in text — accepted directly as lemma list |
| 4 | Plain-text numbered/bulleted list heuristic — extracts items as lemma statements |

`_normalize_list` accepts flexible field names per item (`id`/`lemma_id`/`name`/`title`,
`statement`/`formal_statement`/`hypothesis`/`content`, etc.) so variant LLM schemas
are handled without falling back to single-theorem mode.

---

## 2. UI Polling Log Suppression

`GET /api/runs/<id> 200` status-poll requests are now logged at `DEBUG` level instead of
`INFO`, removing the repetitive log noise during long runs. All other requests (POST,
errors, non-200 responses) continue to log at `INFO`.

---

## 3. Bug Fixes

| File | Bug | Fix |
|------|-----|-----|

## 4. Always-On Stage Summary Cards

`orchestrator/gate.py` now prints a rich summary card after every completed pipeline stage,
regardless of `GATE_MODE`. Previously cards only appeared at gate prompts.

| Stage | Card shows |
|-------|-----------|
| `survey` | Papers found, open problems, key mathematical objects |
| `theory` | Proof status, per-lemma breakdown with confidence tags |
| `experiment` | Alignment score, per-lemma numerical check results |
| `writer` | Full session summary before final output |

---

## 5. Human Gate Improvements

When `GATE_MODE=human` (or auto-escalation triggers):

- **Text feedback input**: after approving a gate, users can optionally type a correction
  or hint. This text is injected into the next agent's task description via
  `get_user_feedback()`, so e.g. "use Bernstein instead of Hoeffding for lemma 3" is
  actually passed to the prover.
- **Auto-escalation** (`GATE_MODE=auto`): if ≥1 lemma has `verified=False` after the theory
  stage, the gate automatically escalates from auto to human for the theory review, showing
  the full lemma confidence breakdown.
- **Default changed**: `GATE_MODE` default changed from `none` to `auto`.

---

## 6. Proof Readability Enforcement (Writer Agent)

Added `_PROOF_STYLE_RULES` injected into both LaTeX and Markdown writer prompts:

- **No skip words**: "clearly", "it is easy to see", "by standard arguments", "trivially"
  are forbidden unless the justification immediately follows.
- **Citation requirement**: every inequality must name the lemma or theorem it uses.
- **Informal intuition**: each lemma proof must open with 1–2 sentences of informal explanation
  before the formal argument.
- **Low-confidence tagging**: lemmas with `verified=False` are passed as `[LOW CONFIDENCE]`
  to the writer, which must add `\textcolor{orange}{[Unverified step]}` after the proof and
  include a Limitations paragraph explaining what was not formally verified.
- Added `\usepackage{xcolor}` to the LaTeX preamble.

---

## 7. Targeted Numerical Testing for Low-Confidence Lemmas (Experiment Agent)

Previously the experiment stage ran a single generic validation of the main theorem.
Now it separates proven lemmas into `verified` and `low_confidence` groups:

- For each **low-confidence lemma**, the agent generates a dedicated numerical test:
  sample random instances satisfying the lemma's hypothesis, check the conclusion holds,
  compute `violation_rate`.
- Lemmas with `violation_rate > 1%` are flagged as `numerically_suspect` and stored on
  the knowledge bus.
- The experiment summary card (gate) shows per-lemma check results with color coding:
  green (✓ passes), red (✗ suspect).
- The writer agent can then add stronger warnings for suspect lemmas in the paper.
| `agents/survey/agent.py` | `ValueError: substring not found` on unclosed ` ```json ` block | Wrapped `text.index` in try/except |
| `agents/base.py` | `run_agent_loop` ignoring `SURVEY_MAX_TURNS` setting | Uses dynamic `AsyncRetrying` now |
| `main.py` | `NameError: name 'Path' is not defined` in `save_artifacts` | Added `from pathlib import Path` |
| `ui/server.py` | `GET /api/runs/...` spamming the log | Demoted to `DEBUG` for 200 polling responses |

---

## 4. LaTeX Compilation Robustness

### Extended theorem environment support

Added 7 more `\newtheorem` declarations to `LATEX_PREAMBLE` in `writer/agent.py`:
`assumption`, `maintheorem`, `conjecture`, `claim`, `example`, `fact`, `observation`.
These cover the most common environments the LLM generates that previously caused
`! LaTeX Error: Environment X undefined.` fatal errors.

### Environment name normalization (`_extract_latex` step 6)

`_extract_latex` now normalises mis-cased or mis-spaced environment names before
writing `paper.tex`:

| LLM output | Corrected to |
|---|---|
| `\begin{Proof}` | `\begin{proof}` |
| `\begin{le mma}` | `\begin{lemma}` |
| `\begin{Theorem}`, `\begin{Lemma}`, … | lowercase equivalents |

### Unclosed environment auto-closing (`_extract_latex` step 7)

New `_close_open_environments()` static method scans `\begin{X}` / `\end{X}` tokens
in document order using a stack, detects any environments left open at the end of the
body (e.g. when the LLM hits `max_tokens` mid-table), drops incomplete trailing rows,
and appends the missing `\end{X}` tags. Prevents `\begin{tabular}` truncation from
causing a fatal LaTeX error.

### Removed rescue compile

`_rescue_compile` and the associated `paper_rescue.tex` fallback have been removed.
`_compile_pdf` now logs a warning if no PDF is produced, but never silently replaces
`paper.pdf` with a stripped plain-text version.

---

## 5. Bibliography & Reference Resolution

Previously all `\cite{}` keys appeared as `?` in the PDF because:
1. `references.bib` was written **after** `_compile_pdf` ran.
2. `bibtex` was never called — only `pdflatex` ran twice.
3. The LLM invented its own cite keys that didn't match what `_generate_bibtex` produced.

All three issues are now fixed:

| Fix | Detail |
|---|---|
| Write order | `references.bib` is saved **before** `_compile_pdf` is called in `save_artifacts` |
| Full compile sequence | `_compile_pdf` now runs `pdflatex → bibtex → pdflatex → pdflatex`; `bibtex` is skipped only when no `.bib` file exists |
| Cite key consistency | New `_compute_cite_keys()` in `writer/agent.py` uses the identical algorithm as `_generate_bibtex` in `main.py`; the writer prompt now includes `\cite{key}` for each reference so the LLM uses exact matching keys |
| `ResearchOutput` | Added `bibliography_json` field; `_collect_outputs` in meta-orchestrator populates it from `bus.get_bibliography()` |
| Duplicate key handling | `_generate_bibtex` deduplicates conflicting author-year keys with `a`, `b`, … suffixes |

---

## 6. Configurable Token Limits Per Call Type

All LLM output token budgets are now configurable via `.env` and UI sliders.

### New `.env` variables

| Variable | Default | Scope |
|---|---|---|
| `MAX_TOKENS_AGENT` | `8192` | Main agent reasoning loop (all agents) |
| `MAX_TOKENS_PROVER` | `4096` | Proof generation |
| `MAX_TOKENS_PLANNER` | `4096` | Research direction planning (diverge phase); converge uses half |
| `MAX_TOKENS_DECOMPOSER` | `2048` | Lemma decomposition |
| `MAX_TOKENS_FORMALIZER` | `2048` | Formalization, refiner, counterexample, resource analyst |
| `MAX_TOKENS_VERIFIER` | `1024` | Proof verification |
| `MAX_TOKENS_COMPRESS` | `512` | Context compression summaries (fast model) |

### Files updated

`config.py`, `agents/base.py`, `agents/theory/prover.py`, `agents/theory/decomposer.py`,
`agents/theory/formalizer.py`, `agents/theory/verifier.py`, `agents/theory/refiner.py`,
`agents/theory/counterexample.py`, `agents/theory/resource_analyst.py`,
`orchestrator/planner.py` — all now read from `settings.max_tokens_*`.

### UI sliders

A **"Token limits per call type"** section with 7 range sliders has been added to the
Settings tab. Each slider shows its live value and persists to `.env` via the existing
"Save config" button.

---

## 7. Multi-Backend LLM Support (shiyuan)

Added three named backends to `config.py` and `llm/factory.py`:

| Backend | `LLM_BACKEND=` | Notes |
|---------|---------------|-------|
| Anthropic native | `anthropic` | Default |
| OpenRouter | `openrouter` | Set `OPENAI_COMPAT_API_KEY=sk-or-...` |
| Local (vLLM / Ollama) | `local` | Defaults to `http://localhost:8000/v1` |

**ccproxy / OAuth fallback** (`llm/anthropic_adapter.py`): if `ANTHROPIC_API_KEY` is empty,
the adapter automatically reads `~/.claude/.credentials.json` and routes through ccproxy,
allowing Claude Pro/Max users to run EurekaClaw without a separate API key.

---

## 8. Additional Tuning Knobs (shiyuan)

| Variable | Default | Effect |
|----------|---------|--------|
| `SURVEY_MAX_TURNS` | `8` | Tool-use turns in survey |
| `THEORY_STAGE_MAX_TURNS` | `6` | Turns per theory stage |
| `WRITER_MAX_TURNS` | `4` | Turns for paper generation |
| `ARXIV_MAX_RESULTS` | `10` | Hard cap on arXiv results |
| `LLM_RETRY_ATTEMPTS` | `5` | Retry attempts on 5xx / rate-limit errors |
| `LLM_RETRY_WAIT_MIN` / `MAX` | `4` / `90` | Exponential backoff bounds |

Retry logic in `agents/base.py` uses dynamic `AsyncRetrying` so settings are read at call time.

---

## 9. Stage Summary Cards + Human Gate (shiyuan)

`orchestrator/gate.py` prints a rich summary card after every completed pipeline stage.
When `GATE_MODE=human` (or auto-escalation triggers on low-confidence lemmas), the gate
pauses and accepts optional text feedback injected into the next agent's task.

---

## 10. Proof Readability Enforcement (shiyuan)

`ENFORCE_PROOF_STYLE=true` (default) injects `_PROOF_STYLE_RULES` into writer prompts:
- No skipped steps; "clearly" / "it follows that" must be immediately justified
- Every inequality cites its lemma
- Low-confidence lemmas tagged `\textcolor{orange}{\textbf{[Unverified step]}}` in PDF

---

## 11. Targeted Numerical Verification (shiyuan)

`agents/experiment/agent.py` now separates low-confidence lemmas and runs dedicated
numerical tests for each. Lemmas with `violation_rate > 1%` are flagged as
`numerically_suspect` and the writer adds stronger warnings for those in the paper.

---

# 2026-03-18

## 1. Context compression

### Efficiency Gains & Savings

The following table summarizes the primary optimizations applied to the pipeline stages.

| Stage | Before | After | Saving |
| :--- | :--- | :--- | :--- |
| **Formalizer model** | `opus` | `haiku` | ~90% cost per call |
| **Formalizer re-run** | Every iteration | Only on change | Saves $N-1$ calls |
| **Proven lemma context** | 200 chars proof text | Statement only (120) | ~40% input tokens |
| **Verifier (high-conf)** | Always LLM call | Auto-accept $\ge 0.85$ | Saves ~30% of calls |
| **Verifier proof text** | Raw (up to 3000 chars) | Head + Tail (1000 chars) | ~67% input tokens |
| **Agent loop history** | Accumulates forever | Compressed every 6 turns | ~60% input tokens |
| **Stagnation** | Wastes 3+ iterations | Forced refinement | Saves full iterations |

---

### Agent Configuration Updates

Specific file-level changes to `max_turns` and model selection to streamline agent execution.

| File | Change |
| :--- | :--- |
| `survey/agent.py` | `max_turns` 15 $\rightarrow$ 8 |
| `ideation/agent.py` | `max_turns` 5 $\rightarrow$ 3 |
| `experiment/agent.py` | `max_turns` 10 $\rightarrow$ 5 |
| `writer/agent.py` | `max_turns` 5 $\rightarrow$ 3 |
| `theory/counterexample.py` | model `eurekaclaw_model` $\rightarrow$ `eurekaclaw_fast_model` |
| `theory/decomposer.py` | `max_tokens` 3000 $\rightarrow$ 2048 |

> **Run Performance Impact:** A typical run now utilizes **~20 LLM calls** (down from ~35), while worst-case scenarios have dropped from **~100 to ~55 calls**.

---

### Advanced Optimization Techniques

These techniques were integrated based on research into high-efficiency agentic workflows.

| File | Technique | Source Inspiration |
| :--- | :--- | :--- |
| **config.py** | Added knobs: `CONTEXT_COMPRESS_AFTER_TURNS`, `AUTO_VERIFY_CONFIDENCE`, `STAGNATION_WINDOW` | — |
| **agents/session.py** | `compress_to_summary()`: Replaces history with a single compressed message | OpenClaw `/compact` |
| **agents/base.py** | Periodic compression every 6 turns using fast model via `_compress_history()` | ScienceClaw smart compaction |
| **theory/formalizer.py** | Fast model + skip re-formalization when informal statement is unchanged | AI-Researcher caching |
| **theory/decomposer.py** | Skip re-decomposition when formal statement is unchanged; limit keys to last 8 | AI-Researcher caching |
| **theory/prover.py** | `_format_proven`: Statement-only (120 chars); dynamic top-5 + count | Paper2Poster (87% fewer tokens) |
| **theory/verifier.py** | Auto-accept at $\ge 0.85$ confidence; head+tail compression for long proofs | ClawTeam performance-based stopping |
| **theory/counterexample.py** | Proof text 2000 $\rightarrow$ 500 chars; require $\ge 2$ signal matches (was 1) | ScienceClaw selective preservation |
| **theory/inner_loop.py** | Stagnation detection (forced refinement); skip low-conf verifier; 20s timeout | ClawTeam "kill idle agents" |
| **orchestrator/planner.py** | Compact direction format in converge call (120+80 chars vs. full text) | AI-Researcher hierarchical distillation |
| **learning/loop.py** | Deduplicate failures; compress success proofs to 300 chars; skip low-novelty distillation | Session-to-skills |


### Experiment skip
in .env.example, user can set:

EXPERIMENT_MODE=auto # or "true"/"false"

for setting the involvement of experiment stage (auto judge / force requirement / force ignore)


## Domain Plugin Architecture

### Architecture Overview

EurekaClaw now uses a three-tier plugin architecture:

```
EurekaClaw (general pipeline)          ← domain-agnostic: survey / theory / experiment / writer
    └── DomainPlugin (e.g. MAB)        ← domain sub-interface: tools + skills + workflow + benchmark
            └── Workflow                ← per-domain research guidance injected into agent prompts
```

To add a new research domain (e.g. game theory, statistical learning), create
`eurekaclaw/domains/<name>/` and subclass `DomainPlugin`. No changes to core code needed.

---

### New: Domain Plugin System (`eurekaclaw/domains/`)

#### `domains/base.py` — `DomainPlugin` ABC
| Method | Purpose |
|--------|---------|
| `register_tools(registry)` | Injects domain-specific LLM tools into the shared ToolRegistry |
| `get_skills_dirs()` | Extra skill directories the SkillRegistry loads |
| `get_workflow_hint()` | Research guidance injected into agent context |
| `get_benchmark_problems(level)` | Returns benchmark problems for evaluation |

#### `domains/__init__.py` — Plugin Registry
- `@register_domain` decorator — registers a plugin class by its `name`
- `resolve_domain(domain_str)` — auto-detects the right plugin from a domain string or keywords

---

### New: MAB Domain Plugin (`eurekaclaw/domains/mab/`)

Self-contained package for stochastic multi-armed bandit theory research.

```
domains/mab/
  __init__.py          MABDomainPlugin  (keywords: bandit, UCB, thompson, regret, …)
  envs/
    stochastic.py      GaussianBandit, BernoulliBandit
    runner.py          run_experiment(), sweep_T()  (UCB1 & Thompson Sampling)
  tools/
    concentration.py   Hoeffding, Bernstein, sub-Gaussian, UCB radius
    regret.py          Regret decomposition, Lai-Robbins lower bound
    information.py     KL(Bernoulli), KL(Gaussian), Fano's inequality
    bandit_tool.py     BanditExperimentTool (LLM-callable, runs simulations)
  skills/
    ucb_regret_analysis.md
    thompson_sampling_analysis.md
    lower_bound_construction.md
    bandit_simulation.md
  benchmark/
    level1.json        Reproduce known bounds (UCB1, Lai-Robbins)
    level2.json        Refine existing results (Bernstein-UCB, MOSS, KL-UCB)
    level3.json        Open problems (heavy tails, infinite-arm, batched bandits)
  workflow.py          Domain-specific research guidance for agents
```

The MABDomainPlugin is auto-detected when the domain string contains keywords like
`bandit`, `UCB`, `thompson`, `regret`, etc.

---

### Changed: Core Infrastructure

| File | Change |
|------|--------|
| `llm/anthropic_adapter.py` | Added `_read_claude_oauth_token()` — reads `~/.claude/.credentials.json` as auth fallback |
| `llm/factory.py` | Added `openrouter` and `local` as named backend shortcuts |
| `skills/registry.py` | `add_skills_dir(path)` — load skills from domain plugin directories |
| `tools/registry.py` | `build_default_registry()` now domain-agnostic; domain tools registered via plugin |
| `orchestrator/meta_orchestrator.py` | Accepts `domain_plugin`; applies tools, skills, workflow hint |
| `main.py` | `EurekaSession.run()` auto-detects domain plugin from `InputSpec.domain` |
| `.env.example` | Documented `openrouter`/`local` backends and OAuth auto-fallback |

---

### How to Add a New Domain

1. Create `eurekaclaw/domains/my_domain/__init__.py`:
   ```python
   from eurekaclaw.domains.base import DomainPlugin
   from eurekaclaw.domains import register_domain

   @register_domain
   class MyDomainPlugin(DomainPlugin):
       name = "my_domain"
       keywords = ["keyword1", "keyword2"]
       display_name = "My Research Domain"

       def register_tools(self, registry): ...
       def get_workflow_hint(self): return "..."
   ```
2. Add the import to `domains/__init__.py`'s `_DOMAIN_PACKAGES` list.
3. That's it — `resolve_domain("keyword1 problem")` will auto-select your plugin.
