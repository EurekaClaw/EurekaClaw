# Skills System

Skills are reusable, domain-specific pieces of knowledge injected into agent prompts before each task. They encode successful proof strategies, domain conventions, and common pitfalls learned from previous runs.

```
eurekaclaw/skills/
├── registry.py      SkillRegistry (load + store skills)
├── injector.py      SkillInjector (retrieve + format for prompts)
└── seed_skills/     Bundled starter skills (Markdown files)
```

---

## Skill File Format

Each skill is a Markdown file with YAML frontmatter:

```markdown
---
name: ucb_regret_analysis
version: "1.0"
tags: [bandit, regret, ucb, concentration]
agent_roles: [theory, survey]
pipeline_stages: [theory]
description: How to decompose and bound UCB1 regret using concentration inequalities
source: seed           # seed | distilled | manual
created_at: 2026-01-01T00:00:00
usage_count: 0
success_rate: null     # float 0-1, or null if unknown
---

# UCB Regret Analysis

When bounding UCB1 regret, decompose into:
1. Suboptimal arm pulls where confidence bound held (good event)
2. Pulls where the bound failed (bad event, controlled by concentration)

Use Hoeffding for sub-Gaussian rewards, Bernstein when variance is known...
```

Skills are stored in `~/.eurekaclaw/skills/` and loaded at startup.

---

## SkillRegistry

**File:** `eurekaclaw/skills/registry.py`

```python
class SkillRegistry:
    def __init__(skills_dir: Path | None = None) -> None
```

### Loading

```python
def load_all() -> list[SkillRecord]
```
Load all skills from registered directories. Load order (later overrides earlier):
1. Seed skills in `eurekaclaw/skills/seed_skills/`
2. Domain plugin skills (extra directories from `get_skills_dirs()`)
3. User skills in `~/.eurekaclaw/skills/` (highest priority)

```python
def add_skills_dir(path: Path) -> None
```
Register an extra directory to load skills from (used by domain plugins).

```python
def reload() -> None
```
Reload all skills from disk (e.g., after distillation writes new files).

### Retrieval

```python
def get(name: str) -> SkillRecord | None
```
Retrieve a skill by exact name.

```python
def get_by_tags(tags: list[str]) -> list[SkillRecord]
```
Return all skills that have at least one of the given tags.

```python
def get_by_role(role: str) -> list[SkillRecord]
```
Return all skills whose `agent_roles` includes `role`.

```python
def get_by_pipeline_stage(stage: str) -> list[SkillRecord]
```
Return all skills for a given pipeline stage.

### Storage

```python
def upsert(skill: SkillRecord) -> None
```
Write skill to disk and register in memory. Creates or overwrites the `.md` file in `~/.eurekaclaw/skills/`.

---

## SkillInjector

**File:** `eurekaclaw/skills/injector.py`

Retrieves the most relevant skills for a task and formats them for injection into agent system prompts.

```python
class SkillInjector:
    def __init__(registry: SkillRegistry) -> None
```

### Retrieval

```python
def top_k(
    task: Task,
    role: str,
    k: int = 5,
    strategy: Literal["tag", "semantic", "hybrid"] = "tag"
) -> list[SkillRecord]
```

**Retrieval strategies:**

| Strategy | Description |
|---|---|
| `tag` | Filter by matching `agent_roles` and `pipeline_stages`, sort by `usage_count` |
| `semantic` | Embedding-based similarity using `sentence-transformers` (if installed) |
| `hybrid` | Tag filter first, then text similarity ranking |

### Formatting

```python
def render_for_prompt(skills: list[SkillRecord]) -> str
```

Returns an XML block injected into the agent system prompt:

```xml
<skills>
<skill name="ucb_regret_analysis">
# UCB Regret Analysis
...
</skill>
<skill name="concentration_inequalities">
...
</skill>
</skills>
```

---

## Data Models

**File:** `eurekaclaw/types/skills.py`

```python
class SkillMeta(BaseModel):
    name: str
    version: str = "1.0"
    tags: list[str] = []
    agent_roles: list[str] = []       # e.g., ["theory", "survey"]
    pipeline_stages: list[str] = []   # e.g., ["theory", "experiment"]
    description: str = ""
    source: Literal["seed", "distilled", "manual"] = "seed"
    created_at: datetime
    usage_count: int = 0
    success_rate: float | None = None

class SkillRecord(BaseModel):
    meta: SkillMeta
    content: str        # Markdown body after frontmatter
    file_path: str = "" # absolute path to the .md file
    embedding: list[float] | None = None  # populated on first semantic retrieval

    @property
    def full_markdown(self) -> str: ...  # frontmatter + content
```

---

## Skill Distillation (Post-Run Learning)

After each successful session, `ContinualLearningLoop.post_run()` distills new skills from the session:

```
ContinualLearningLoop.post_run()
    ├── extract failures (FailedAttempt[]) from TheoryState
    ├── deduplicate — only unique failure patterns (skip low-novelty)
    ├── compress successes — proof text trimmed to 300 chars
    ├── SkillEvolver.distill_from_session()
    │       → new SkillRecord .md files in ~/.eurekaclaw/skills/
    └── (rl/madmax modes) ProcessRewardModel scoring
```

**`SkillEvolver.distill_from_session()`** uses the main LLM to:
1. Identify generalizable patterns from successful proofs
2. Write a new skill Markdown file with appropriate tags and roles
3. Set `source: distilled` in frontmatter

New skills are immediately available in the next session via `SkillRegistry.reload()`.

---

## Seed Skills (MAB Domain)

The MAB domain plugin ships four seed skills:

| Skill | Tags | Description |
|---|---|---|
| `ucb_regret_analysis` | bandit, regret, ucb | UCB1 regret decomposition via concentration |
| `thompson_sampling_analysis` | bandit, thompson, bayesian | Thompson Sampling regret analysis |
| `lower_bound_construction` | bandit, lower-bound, information | Lai-Robbins and Fano-based lower bounds |
| `bandit_simulation` | bandit, simulation, experiment | How to run and interpret bandit simulations |

---

## Installing Seed Skills

```bash
eurekaclaw install-skills          # install to ~/.eurekaclaw/skills/
eurekaclaw install-skills --force  # overwrite existing skills
```
