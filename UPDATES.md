# EurekaClaw Updates

## v0.2.0 — Domain Plugin Architecture (2026-03-18)

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
