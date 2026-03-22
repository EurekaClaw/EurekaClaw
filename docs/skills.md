# Skills System

Skills are reusable, domain-specific pieces of knowledge injected into agent prompts before each task. They encode successful proof strategies, domain conventions, and common pitfalls learned from previous runs.

```
eurekaclaw/skills/
├── registry.py      SkillRegistry (load + store skills)
├── injector.py      SkillInjector (retrieve + format for prompts)
├── install.py       SkillInstaller (install seed skills or skills from ClawHub)
└── evolver.py       SkillEvolver (distill skills from proceeded session)
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

Skills are stored in one of three locations depending on their origin (see [Skill Lifecycle](#skill-lifecycle) below).

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
    def __init__(
        registry: SkillRegistry,
        selected_skills: list[str] | None = None,
    ) -> None
```

`selected_skills` — optional list of skill names to **pin**. Pinned skills are always included at the front of the top-k result, before any usage-sorted optional skills. If a pinned skill name is not found in the registry, a warning is logged and it is silently skipped.

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
| `tag` | Filter by matching `agent_roles` and `pipeline_stages`; pinned skills first, then optional sorted by `usage_count` |
| `semantic` | Embedding-based similarity using `sentence-transformers` (if installed) |
| `hybrid` | Tag filter (3×k candidates), then text similarity ranking |

**Pinned-skill priority:** When `selected_skills` is non-empty, the `tag` (and by extension `hybrid`) retrieval splits candidates into:
1. **Must-have** — skills in both `selected_skills` and the role/stage set → always placed first
2. **Optional** — remaining candidates → sorted by `usage_count` descending

The combined list is then truncated to `k`.

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
eurekaclaw install-skills                      # copy seeds to ~/.eurekaclaw/skills/
eurekaclaw install-skills --force              # overwrite existing copies
eurekaclaw install-skills <skillname>          # install a skill from ClawHub
```

The `<skillname>` form fetches a skill from the [ClawHub](https://clawhub.ai/) registry using the `clawhub` CLI (must be installed separately). Example:

```bash
eurekaclaw install-skills steipete/github
```

This command is a convenience for inspection and manual editing only. Agents do **not** require it — seed skills are always available directly from the package.

---

## Skill Lifecycle

Understanding where skills physically live prevents confusion about why `~/.eurekaclaw/skills/` may not contain every skill an agent can see.

### Three storage locations

| Location | Who writes there | When |
|---|---|---|
| `eurekaclaw/skills/seed_skills/` | Package developers (you) | Committed to the repo; bundled with `pip install` |
| `eurekaclaw/domains/<domain>/skills/` | Domain plugin authors | Registered via `add_skills_dir()` at plugin load time |
| `~/.eurekaclaw/skills/` | `install-skills` CLI + `SkillEvolver` + ClawHub | On demand; user-editable |

### Load order at runtime

Every time `SkillRegistry._load()` runs, it reads all three sources in this order. A skill with the same `name` in a later source **overrides** the earlier one:

```
1. eurekaclaw/skills/seed_skills/**/*.md        (lowest priority)
2. domain plugin skill dirs (extra_dirs)        (medium priority)
3. ~/.eurekaclaw/skills/**/*.md                 (highest priority — overrides seeds)
```

**Consequence:** adding a file to `seed_skills/` makes it immediately visible to agents on the next run, without copying anything to `~/.eurekaclaw/skills/`. The absence of a seed skill from `~/.eurekaclaw/skills/` does not reduce agent capability.

### How new skills are generated

Skills enter the system through three paths:

#### 1. Seed skills (developer-authored)

Create a `.md` file in `eurekaclaw/skills/seed_skills/<category>/`:

```bash
# e.g. for a new theory skill
touch eurekaclaw/skills/seed_skills/theory/my_new_skill.md
```

Set `source: seed` in frontmatter. The skill is available to all agents immediately after the file is saved — no CLI step required.

#### 2. LLM distillation (automatic, post-run)

After each successful session, `SkillEvolver.distill_from_session()` is called with up to 5 `FailedAttempt` records and 5 `ProofRecord` successes from the session. It calls the fast model with a distillation prompt and parses the response into a new `SkillRecord`.

The new skill is written to `~/.eurekaclaw/skills/<name>.md` via `SkillRegistry.upsert()` with:
- `source: distilled`
- `name: distilled_<session_id[:8]>_<random_hex>`
- Tags, roles, and stages extracted from the LLM response

It is immediately available to subsequent sessions without any restart.

```
Session completes
    └── SkillEvolver.distill_from_session(failures, successes)
            └── LLM call (fast model, max_tokens=1024)
                    └── _parse_skill_response()
                            └── SkillRegistry.upsert()  →  ~/.eurekaclaw/skills/<name>.md
```

#### 3. ClawHub skills

```bash
eurekaclaw install-skills <author>/<skillname>
```

Downloads the skill from the [ClawHub](https://clawhub.ai/) registry via the `clawhub` CLI and places it in `~/.eurekaclaw/skills/`. Requires `clawhub` to be installed (`pip install clawhub` or equivalent).

#### 4. Manual user skills

Place any `.md` file with valid YAML frontmatter directly in `~/.eurekaclaw/skills/`. It will be loaded on the next session. Use `source: manual` in the frontmatter to distinguish from distilled skills.

### Skill stats update

After each session, `SkillRegistry.update_stats(name, success)` rewrites the skill file with updated `usage_count` and `success_rate` (exponential moving average, α=0.3). This only affects skills that already exist in `~/.eurekaclaw/skills/` — seed skills in the package are never modified on disk by running sessions.

### Why `~/.eurekaclaw/skills/` may look empty

A fresh installation with no sessions run yet will have an empty `~/.eurekaclaw/skills/` directory. This is normal. The agents are not "missing" any skills — they read seed skills and domain plugin skills directly at runtime. `~/.eurekaclaw/skills/` fills up over time through:

- `eurekaclaw install-skills` (one-time copy for inspection/editing)
- Completed sessions (automatic distillation)
- Manual placement of custom `.md` files
