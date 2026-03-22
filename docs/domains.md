# Domain Plugin System

EurekaClaw uses a three-tier plugin architecture to support domain-specific research:

```
EurekaClaw (general pipeline)          ← domain-agnostic: survey / theory / experiment / writer
    └── DomainPlugin (e.g. MAB)        ← domain sub-interface: tools + skills + workflow + benchmark
            └── Workflow                ← per-domain research guidance injected into agent prompts
```

Plugins add domain-specific tools, skills, and prompt guidance without modifying core code.

---

## DomainPlugin Base Class

**File:** `eurekaclaw/domains/base.py`

```python
class DomainPlugin(ABC):
    name: str = ""            # machine identifier, e.g. "mab"
    display_name: str = ""    # human-readable, e.g. "Stochastic Multi-Armed Bandits"
    keywords: list[str] = []  # strings that trigger auto-detection
    description: str = ""
```

### Abstract Methods

```python
@abstractmethod
def register_tools(self, registry: ToolRegistry) -> None:
    """Inject domain-specific tools into the shared ToolRegistry."""
    ...

@abstractmethod
def get_workflow_hint(self) -> str:
    """Return domain-specific research guidance (injected into agent system prompts)."""
    ...
```

### Optional Methods

```python
def get_skills_dirs(self) -> list[Path]:
    """Return extra skill directories. Default: []."""
    return []

def get_benchmark_problems(self, level: str) -> list[dict]:
    """Return benchmark problems for 'level1', 'level2', or 'level3'. Default: []."""
    return []
```

---

## Plugin Registry

**File:** `eurekaclaw/domains/__init__.py`

### Registration

```python
@register_domain
class MyPlugin(DomainPlugin):
    name = "my_domain"
    ...
```

The `@register_domain` decorator registers a plugin class by its `name`.

### Resolution

```python
def resolve_domain(domain: str) -> DomainPlugin | None
```

Auto-detect the right plugin from a domain string or conjecture keywords. Matching order:
1. Exact key match against registered plugin names
2. Keyword scan — returns the first plugin whose `keywords` list contains any word from `domain`

Returns `None` if no plugin matches (runs in general mode).

---

## MAB Domain Plugin

**Package:** `eurekaclaw/domains/mab/`

The built-in example plugin for stochastic multi-armed bandit theory.

```python
@register_domain
class MABDomainPlugin(DomainPlugin):
    name = "mab"
    display_name = "Stochastic Multi-Armed Bandits"
    description = "Regret bounds, concentration, lower bounds for K-armed bandits"
    keywords = [
        "bandit", "multi-armed", "mab", "ucb", "thompson", "regret",
        "exploration", "exploitation", "stochastic bandit",
    ]
```

**Auto-detected when domain contains:** `bandit`, `UCB`, `thompson`, `regret`, `exploration`, `multi-armed`, etc.

### Package Structure

```
domains/mab/
├── __init__.py            MABDomainPlugin
├── workflow.py            WORKFLOW_HINT (research guidance text)
├── envs/
│   ├── stochastic.py      GaussianBandit, BernoulliBandit environments
│   └── runner.py          run_experiment(), sweep_T() — UCB1 & Thompson Sampling
├── tools/
│   ├── concentration.py   Hoeffding, Bernstein, sub-Gaussian, UCB radius formulas
│   ├── regret.py          Regret decomposition, Lai-Robbins lower bound
│   ├── information.py     KL(Bernoulli), KL(Gaussian), Fano's inequality
│   └── bandit_tool.py     BanditExperimentTool (LLM-callable tool)
├── skills/
│   ├── ucb_regret_analysis.md
│   ├── thompson_sampling_analysis.md
│   ├── lower_bound_construction.md
│   └── bandit_simulation.md
└── benchmark/
    ├── level1.json        Reproduce known bounds (UCB1, Lai-Robbins)
    ├── level2.json        Refine existing results (Bernstein-UCB, MOSS, KL-UCB)
    └── level3.json        Open problems (heavy tails, infinite-arm, batched bandits)
```

---

## How to Add a New Domain

1. **Create the plugin package:**

```python
# eurekaclaw/domains/my_domain/__init__.py
from eurekaclaw.domains.base import DomainPlugin
from eurekaclaw.domains import register_domain

@register_domain
class MyDomainPlugin(DomainPlugin):
    name = "my_domain"
    display_name = "My Research Domain"
    description = "Short description for display"
    keywords = ["keyword1", "keyword2", "related term"]

    def register_tools(self, registry: ToolRegistry) -> None:
        registry.register(MySpecialTool())

    def get_workflow_hint(self) -> str:
        return """
        When researching my_domain:
        - Always start by checking known results X and Y
        - Use technique Z for the main proof step
        ...
        """

    def get_skills_dirs(self) -> list[Path]:
        return [Path(__file__).parent / "skills"]

    def get_benchmark_problems(self, level: str) -> list[dict]:
        bm_file = Path(__file__).parent / "benchmark" / f"{level}.json"
        return json.loads(bm_file.read_text()) if bm_file.exists() else []
```

2. **Register the import** in `eurekaclaw/domains/__init__.py`:

```python
_DOMAIN_PACKAGES = [
    "eurekaclaw.domains.mab",
    "eurekaclaw.domains.my_domain",  # add this line
]
```

3. **That's it.** `resolve_domain("keyword1 problem")` will auto-select your plugin.

---

## Domain Plugin Integration

When `MetaOrchestrator` runs with a detected domain plugin, it:

1. Calls `plugin.register_tools(tool_registry)` — adds domain tools to the registry
2. Calls `plugin.get_skills_dirs()` — loads domain skills into `SkillRegistry`
3. Injects `plugin.get_workflow_hint()` into agent system prompts

No changes to any core agent or orchestrator code are needed.
