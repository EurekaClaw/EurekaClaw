# EurekaClaw Updates

# 2026-03-18 (shiyuan branch)

## 1. Multi-Backend LLM Support

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

## 2. Configurable Tuning Knobs

All previously hardcoded parameters are now env-var controlled via `config.py`:

| Variable | Default | Effect |
|----------|---------|--------|
| `EUREKACLAW_MODEL` | `claude-sonnet-4-6` | Changed from opus to sonnet (cheaper, less rate-limited) |
| `AGENT_MAX_TOKENS` | `4096` | Max tokens per LLM response |
| `SURVEY_MAX_TURNS` | `8` | Tool-use turns in survey (was hardcoded 15) |
| `THEORY_STAGE_MAX_TURNS` | `6` | Turns per theory stage |
| `WRITER_MAX_TURNS` | `4` | Turns for paper generation |
| `ARXIV_MAX_RESULTS` | `10` | Hard cap on arXiv results regardless of LLM request |
| `LLM_RETRY_ATTEMPTS` | `5` | Retry attempts on 5xx / rate-limit errors |
| `LLM_RETRY_WAIT_MIN` | `4` | Min backoff seconds |
| `LLM_RETRY_WAIT_MAX` | `90` | Max backoff seconds |

Retry logic in `agents/base.py` was changed from a static `@retry` decorator to a dynamic
`AsyncRetrying` context manager so it reads live settings at call time.

---

## 3. Bug Fixes

| File | Bug | Fix |
|------|-----|-----|
| `agents/survey/agent.py` | `ValueError: substring not found` when LLM returns unclosed ` ```json ` block | Wrapped `text.index("```", start)` in try/except |
| `agents/base.py` | `run_agent_loop` default `max_turns` not reading from settings | Added `_max_turns = max_turns if max_turns is not None else settings.survey_max_turns` |

---

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
| **learning/loop.py** | Deduplicate failures; compress success proofs to 300 chars; skip low-novelty distillation | MetaClaw session-to-skills |


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
