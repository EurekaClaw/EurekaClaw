# EurekaClaw Updates

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
