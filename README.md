# EurekaClaw

**EurekaClaw** is a multi-agent system for automated theoretical research. It synthesizes
proof-heavy, formalism-rich, mathematically dense work in domains such as ML theory,
computational complexity, probability theory, and pure mathematics. The system is
architected around a unique **Theory Agent inner loop** that iteratively formalizes,
decomposes, proves, verifies, and refines mathematical conjectures.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
   - [System Layers](#system-layers)
   - [Theory Agent Inner Loop](#theory-agent-inner-loop)
   - [Shared Knowledge Bus](#shared-knowledge-bus)
   - [Skills Bank](#skills-bank)
   - [Continual Learning](#continual-learning)
3. [Installation](#installation)
4. [Configuration](#configuration)
   - [LLM Backend](#llm-backend)
   - [OAuth via ccproxy](#oauth-via-ccproxy-claude-promax-no-api-key)
   - [Output Format](#output-format)
   - [Token Efficiency Knobs](#token-efficiency-knobs)
5. [Usage](#usage)
   - [CLI Reference](#cli-reference)
   - [Python API](#python-api)
6. [Input Modes](#input-modes)
7. [Learning Modes](#learning-modes)
8. [Evaluation](#evaluation)
9. [Project Structure](#project-structure)
10. [Contributing](#contributing)

---

## Overview

EurekaClaw is inspired by the [OpenClaw](https://github.com/openclaw/openclaw) framework
and extends it into the theoretical research domain. Whereas general-purpose research
agents focus on empirical work, EurekaClaw's core innovation is the **6-stage proof loop**:

```
Informal Conjecture
       │
       ▼
[1] Formalizer  →  LaTeX theorem statement
       │
       ▼
[2] LemmaDecomposer  →  Directed Acyclic Graph of sub-goals
       │
       ▼
[3] Prover  →  Chain-of-thought proof attempt
       │
       ▼
[4] Verifier  →  Lean4 / LLM peer review
    ├─ pass ──► record ProofRecord, pop open_goals
    └─ fail ──► counterexample search
                    │
                    ▼
               [5] CounterexampleSearcher
                    ├─ no cx ──► accept with low confidence
                    └─ cx found ──► Refiner
                                         │
                                         ▼
                                   [6] Refiner  →  updated conjecture
                                         │
                                         └──────────────► restart loop
```

The loop runs until all lemmas are proven, a maximum iteration limit is reached, or the
conjecture is irrefutably refuted.

---

## Architecture

### System Layers

```
┌─────────────────────────────────────────────────────────┐
│                      CLI / Python API                    │
├─────────────────────────────────────────────────────────┤
│                    MetaOrchestrator                      │
│  ┌──────────────────────────────────────────────────┐   │
│  │       DivergentConvergentPlanner                 │   │
│  └──────────────────────────────────────────────────┘   │
├────────────┬─────────────┬────────────┬─────────────────┤
│ SurveyAgent│IdeationAgent│ TheoryAgent│ExperimentAgent  │
│            │             │ (+ inner   │                  │
│            │             │  loop)     │  WriterAgent     │
├─────────────────────────────────────────────────────────┤
│                     KnowledgeBus                         │
│  research_brief · theory_state · bibliography · results  │
├──────────────────────┬──────────────────────────────────┤
│      Memory          │              Skills               │
│  Episodic · Persist  │  Registry · Injector · Evolver   │
│  KnowledgeGraph      │  seed_skills / ~/.metaclaw/       │
├──────────────────────┴──────────────────────────────────┤
│                    Tool Layer                             │
│  arxiv · SemanticScholar · WebSearch · CodeExec          │
│  Lean4 · WolframAlpha · CitationManager                  │
└─────────────────────────────────────────────────────────┘
```

**Pipeline stages** (fully automated — no human gates):

| Stage | Agent | Description |
|---|---|---|
| `survey` | SurveyAgent | Literature search via arXiv, Semantic Scholar, web |
| `ideation` | IdeationAgent | Generate research directions |
| `direction_selection_gate` | orchestrator | Auto-select best research direction |
| `theory` | TheoryAgent | 6-stage proof loop |
| `experiment` | ExperimentAgent | Empirical validation of numerical bounds (optional — see [EXPERIMENT_MODE](#token-efficiency-knobs)) |
| `writer` | WriterAgent | Full paper assembly (LaTeX or Markdown) |

> **Note on experiment stage:** The experiment stage is *optional*. For purely structural
> or algebraic theorems (existence proofs, graph identities, NP-hardness results) it is
> automatically skipped. The writer runs regardless of whether the experiment stage
> succeeds or is skipped — it depends on `theory`, not `experiment`.

> **Note on input modes:** When using `eurekaclaw prove` (Level 1), the direction
> selection step is bypassed entirely — the user's conjecture is used directly as
> the theorem to prove, without any creative re-interpretation by the planner.

### Theory Agent Inner Loop

The `TheoryInnerLoop` class in `eurekaclaw/agents/theory/inner_loop.py` orchestrates
the six sub-agents:

- **Formalizer** — converts the informal hypothesis into a rigorous
  `\begin{theorem}...\end{theorem}` block. Skips re-formalization when the informal
  statement is unchanged across iterations (formalization cache).
- **LemmaDecomposer** — parses an LLM JSON response into a DAG of lemmas, then
  topologically sorts them to find a tractable proof order. Skips re-decomposition
  when the formal statement is unchanged (decomposition cache).
- **Prover** — generates chain-of-thought proof attempts.
- **Verifier** — tries Lean4 first (if binary is available); falls back to LLM peer
  review using the fast model. High-confidence proofs (≥ `AUTO_VERIFY_CONFIDENCE`)
  with no explicit gaps are auto-accepted without LLM peer review, saving one API
  call per lemma. Very low confidence proofs (< 0.3) skip the verifier entirely.
- **CounterexampleSearcher** — adversarial sub-agent that searches for falsifying
  examples using the fast model. If `cx.falsifies_conjecture` is set, the loop routes
  to the Refiner.
- **Refiner** — rewrites `state.informal_statement` and `state.formal_statement`,
  clears the lemma DAG and proven lemmas, then forces re-decomposition of the
  refined conjecture.

**Token-efficiency features in the inner loop:**
- *Stagnation detection* — if the same lemma fails `STAGNATION_WINDOW` consecutive
  times with a similar error pattern, the loop forces a conjecture refinement rather
  than wasting further calls on an irrecoverably stuck lemma.
- *Context compression* — every `CONTEXT_COMPRESS_AFTER_TURNS` tool-use turns, the
  fast model summarises the accumulated conversation history into a concise bullet
  list, dramatically reducing input tokens for long-running agents.

A parallel `ResourceAnalyst` task runs alongside the loop to produce a bidirectional
math↔code mapping and skeleton validation code, consumed later by ExperimentAgent.

### Shared Knowledge Bus

All agents communicate through the `KnowledgeBus` — a central in-memory artifact
store keyed by artifact type. Direct inter-agent messaging is prohibited; agents
only publish/consume typed artifacts.

| Artifact | Type | Description |
|---|---|---|
| `research_brief` | `ResearchBrief` | Domain, query, open problems, selected direction |
| `theory_state` | `TheoryState` | Lemma DAG, open goals, proven lemmas, counterexamples |
| `bibliography` | `Bibliography` | BibTeX-ready paper records |
| `experiment_result` | `ExperimentResult` | Numerical bounds with alignment scores |
| `pipeline` | `TaskPipeline` | Task dependency graph and statuses |
| `resource_analysis` | `dict` | math↔code mapping from ResourceAnalyst |

The bus is persisted to disk at session end via `bus.persist(session_dir)`.

### Skills Bank

Skills are Markdown files with YAML frontmatter, stored in `~/.metaclaw/skills/`.
They are loaded by `SkillRegistry`, ranked by `SkillInjector` (tag match + semantic
similarity via sentence-transformers), and injected into agent system prompts as a
`<skills>...</skills>` XML block.

**Built-in seed skills:**

| Skill | Roles | Tags |
|---|---|---|
| `induction_strategy` | theory | proof, induction |
| `contradiction_proof` | theory | proof, contradiction |
| `compactness_argument` | theory | proof, compactness, topology |
| `complexity_template` | theory | complexity, PAC, Rademacher |
| `literature_decomp` | survey | survey, literature |
| `hypothesis_gen` | ideation | hypothesis, novelty |
| `paper_structure` | writer | LaTeX, paper structure |
| `empirical_validation` | experiment | empirical, bounds |

Install seed skills to your user directory:

```bash
eurekaclaw install-skills
# Use --force to overwrite already-installed skills
eurekaclaw install-skills --force
```

### Continual Learning

After every session the `ContinualLearningLoop` runs in three configurable modes:

| Mode | What runs |
|---|---|
| `skills_only` | `SkillEvolver` — distills failures into new `.md` skill files |
| `rl` | Skills distillation + PRM scoring of proof trajectories |
| `madmax` | Skills distillation + PRM scoring + cloud LoRA fine-tuning (GRPO) |

---

## Installation

### Requirements

- Python ≥ 3.11
- An [Anthropic API key](https://console.anthropic.com/) **or** a Claude Pro/Max
  subscription (see [OAuth via ccproxy](#oauth-via-ccproxy-claude-promax-no-api-key))
- Optional: Lean4 (`lean` binary in `PATH`) for formal verification
- Optional: TeX Live / MacTeX for PDF generation
- Optional: Docker for sandboxed code execution

### Install from source

```bash
git clone https://github.com/your-org/EurekaClaw
cd EurekaClaw
pip install -e "."          # core install
pip install -e ".[dev]"     # + test extras
cp .env.example .env
# edit .env — set ANTHROPIC_API_KEY or configure OAuth
```

### Install seed skills

```bash
eurekaclaw install-skills
```

---

## Configuration

All settings are read from `.env` (or environment variables). Copy `.env.example`:

```bash
cp .env.example .env
```

### Core settings

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Anthropic API key (not needed when using OAuth) |
| `EUREKACLAW_MODEL` | `claude-opus-4-6` | Primary model for deep reasoning |
| `EUREKACLAW_FAST_MODEL` | `claude-haiku-4-5-20251001` | Fast model for lightweight tasks (verification, compression, skill distillation). Falls back to `EUREKACLAW_MODEL` if left empty. |
| `EUREKACLAW_MODE` | `skills_only` | Learning mode: `skills_only`, `rl`, `madmax` |
| `GATE_MODE` | `none` | Gate mode: `none`, `auto`, `human` |
| `THEORY_MAX_ITERATIONS` | `10` | Max proof loop iterations |
| `METACLAW_DIR` | `~/.metaclaw` | Root directory for skills, memory, run artifacts |
| `BRAVE_SEARCH_API_KEY` | — | Optional. Enables web search via Brave |
| `SERPAPI_KEY` | — | Optional. Fallback web search via SerpAPI |
| `WOLFRAM_APP_ID` | — | Optional. Enables WolframAlpha computations |
| `S2_API_KEY` | — | Optional. Authenticated Semantic Scholar access |
| `LEAN4_BIN` | `lean` | Path to Lean4 binary |
| `LATEX_BIN` | `pdflatex` | LaTeX compiler for PDF generation |
| `USE_DOCKER_SANDBOX` | `false` | Run generated code inside Docker |
| `OUTPUT_FORMAT` | `latex` | Output format: `latex` or `markdown` |

### LLM Backend

EurekaClaw supports two LLM backends, selected via `LLM_BACKEND`:

#### Anthropic native (default)

```env
LLM_BACKEND=anthropic
ANTHROPIC_API_KEY=sk-ant-...
EUREKACLAW_MODEL=claude-opus-4-6
```

#### OpenAI-compatible endpoint (OpenRouter, vLLM, SGLang, LM Studio)

```env
LLM_BACKEND=openai_compat
OPENAI_COMPAT_BASE_URL=https://openrouter.ai/api/v1
OPENAI_COMPAT_API_KEY=sk-or-v1-...
OPENAI_COMPAT_MODEL=anthropic/claude-opus-4-6
```

Install the optional OpenAI dependency:

```bash
pip install "eurekaclaw[openai]"
```

### OAuth via ccproxy (Claude Pro/Max, no API key)

If you have a **Claude Pro or Max subscription**, you can run EurekaClaw without an
API key by routing calls through [ccproxy](https://github.com/catdevnull/ccproxy),
which reuses Claude Code's OAuth tokens.

**Setup:**

```bash
# 1. Install ccproxy support
pip install "eurekaclaw[oauth]"

# 2. Authenticate (opens Claude Code OAuth flow)
ccproxy auth login claude_api

# 3. Configure .env
```

```env
ANTHROPIC_AUTH_MODE=oauth
# Leave ANTHROPIC_API_KEY blank
# CCPROXY_PORT=8000   # optional, default is 8000
```

EurekaClaw will automatically start ccproxy when a session begins and shut it down
on exit. If a ccproxy instance is already running on the configured port it will be
reused.

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_AUTH_MODE` | `api_key` | `api_key` (direct) or `oauth` (via ccproxy) |
| `CCPROXY_PORT` | `8000` | Port ccproxy listens on |

### Output Format

Control the format of the generated paper with `OUTPUT_FORMAT`:

| Value | Output file | Description |
|---|---|---|
| `latex` (default) | `paper.tex` + `paper.pdf` | Full LaTeX with theorem environments; PDF compiled automatically |
| `markdown` | `paper.md` | Markdown with YAML front-matter and `$...$` / `$$...$$` math |

```env
OUTPUT_FORMAT=latex   # or: markdown
```

PDF compilation runs `pdflatex` twice (to resolve cross-references) and writes
`paper.pdf` alongside `paper.tex` in the `--output` directory. If `pdflatex` is
not found, a warning is printed and `paper.tex` is still saved.
To use a different compiler (e.g. `xelatex`), set `LATEX_BIN=xelatex`.

### Token Efficiency Knobs

The inner theory loop can run many LLM calls across many lemmas. These settings
control the trade-off between proof thoroughness and API cost:

| Variable | Default | Description |
|---|---|---|
| `CONTEXT_COMPRESS_AFTER_TURNS` | `6` | Compress conversation history into a bullet summary every N tool-use turns. `0` disables compression. Reduces input tokens for long-running agents. |
| `AUTO_VERIFY_CONFIDENCE` | `0.85` | Auto-accept a proof without LLM peer review when the prover's confidence meets or exceeds this threshold and no `[GAP:...]` flags are present. Saves one API call per high-confidence lemma. |
| `STAGNATION_WINDOW` | `3` | If the same lemma fails this many consecutive times with a similar error pattern, force a conjecture refinement instead of continuing to retry. Prevents wasting calls on an irrecoverably stuck proof path. |
| `EXPERIMENT_MODE` | `auto` | Whether to run the experiment stage: `auto` (run only when the theorem has measurable numerical bounds), `true` (always run), `false` (always skip). |

**Example — aggressive token saving:**

```env
CONTEXT_COMPRESS_AFTER_TURNS=4
AUTO_VERIFY_CONFIDENCE=0.80
STAGNATION_WINDOW=2
EXPERIMENT_MODE=false
```

**Example — maximum thoroughness (higher cost):**

```env
CONTEXT_COMPRESS_AFTER_TURNS=0   # no compression
AUTO_VERIFY_CONFIDENCE=0.99      # almost always do full peer review
STAGNATION_WINDOW=5
EXPERIMENT_MODE=true             # always run experiments
```

#### Experiment mode details

The experiment stage is only meaningful for theorems with *measurable numerical
quantities* — bounds, rates, sample complexities, approximation ratios. For purely
structural theorems (existence proofs, NP-hardness, graph identities) there is nothing
to validate numerically, so the stage is automatically skipped when
`EXPERIMENT_MODE=auto`.

| `EXPERIMENT_MODE` | Behaviour |
|---|---|
| `auto` | Run a scored heuristic on the formal statement. Quantitative signals (+2 each): `\Omega(`, `\leq`, `\epsilon`, "regret", "with probability", decimal numbers, etc. Structural signals (−3 each): `\exists`, "bijection", "NP-complete", "undecidable", etc. Score > 0 → run. |
| `true` | Always run, regardless of theorem type. |
| `false` | Always skip. Useful for pure-math work where experiments add no value. |

The writer stage always runs regardless of experiment outcome — it depends on `theory`,
not `experiment`.

---

## Usage

### CLI Reference

#### `eurekaclaw prove` — Level 1: Prove a specific conjecture

```bash
eurekaclaw prove "The sample complexity of transformers is O(L*d*log(d)/eps^2)" \
    --domain "ML theory" \
    --mode skills_only \
    --output ./results
```

The conjecture is used verbatim as the theorem to prove — the system does not
reinterpret or replace it with a different direction.

Artifacts written to `--output`:
- `paper.tex` — full LaTeX source
- `paper.pdf` — compiled PDF (requires `pdflatex`)
- `theory_state.json` — lemma DAG, proof records, counterexamples

**Options:**
- `--domain, -d` — Research domain (auto-inferred if omitted).
- `--mode` — Learning mode (`skills_only` | `rl` | `madmax`).
- `--gate` — Gate mode (`none` | `auto` | `human`). Default: `none`.
- `--output, -o` — Output directory.

---

#### `eurekaclaw explore` — Level 3: Open domain exploration

```bash
eurekaclaw explore "sample complexity of transformers" \
    --query "What are the tightest known bounds?" \
    --mode rl
```

**Arguments:**
- `DOMAIN` — The research domain to explore.

**Options:**
- `--query, -q` — A more specific research question (optional).
- `--mode`, `--gate`, `--output` — same as `prove`.

---

#### `eurekaclaw from-papers` — Level 2: Generate hypotheses from papers

```bash
eurekaclaw from-papers 2301.12345 2302.67890 \
    --domain "ML theory"
```

**Arguments:**
- `PAPER_IDS` — One or more arXiv paper IDs.

**Options:**
- `--domain, -d` — **Required.** Research domain.
- `--mode`, `--gate` — same as above.

---

#### `eurekaclaw skills` — List available skills

```bash
eurekaclaw skills
```

#### `eurekaclaw install-skills` — Copy seed skills to `~/.metaclaw/skills/`

```bash
eurekaclaw install-skills           # skip already-installed
eurekaclaw install-skills --force   # overwrite all
```

#### `eurekaclaw eval-session` — Evaluate a completed session

```bash
eurekaclaw eval-session <session_id>
```

Runs the Scientist-Bench evaluator and prints a JSON report to the console.

---

### Python API

#### Quick start

```python
import asyncio
from eurekaclaw import EurekaSession

session = EurekaSession()
result = asyncio.run(
    session.run_detailed(
        conjecture="For all n ≥ 1: Σᵢ₌₁ⁿ i = n(n+1)/2",
        domain="combinatorics",
    )
)
print(result.latex_paper[:500])
print(result.theory_state_json[:500])
```

#### All input modes

```python
import asyncio
from eurekaclaw import EurekaSession

session = EurekaSession()

# Level 1 — prove a specific conjecture
result = asyncio.run(session.run_detailed(
    conjecture="Any PAC-learnable class has finite VC dimension",
    domain="machine learning theory",
))

# Level 2 — explore gaps around known papers
result = asyncio.run(session.run_from_papers(
    paper_ids=["2301.12345", "2209.11755"],
    domain="transformer generalization",
))

# Level 3 — open exploration
result = asyncio.run(session.run_exploration(
    domain="algebraic topology",
    query="What are open problems in persistent homology?",
))
```

#### `ResearchOutput` fields

| Field | Type | Description |
|---|---|---|
| `session_id` | `str` | UUID of this session |
| `latex_paper` | `str` | Full paper source (LaTeX or Markdown depending on `OUTPUT_FORMAT`) |
| `theory_state_json` | `str` | JSON dump of `TheoryState` |
| `experiment_result_json` | `str` | JSON dump of `ExperimentResult` |
| `research_brief_json` | `str` | JSON dump of `ResearchBrief` (incl. selected direction) |

#### Low-level API

```python
import asyncio
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
from eurekaclaw.types.tasks import InputSpec

bus = KnowledgeBus(session_id="my-session")
orchestrator = MetaOrchestrator(bus=bus)

spec = InputSpec(
    mode="detailed",
    conjecture="Rademacher complexity of depth-L ReLU networks is O(sqrt(L)/sqrt(m))",
    domain="deep learning theory",
    query="Prove Rademacher bound for deep ReLU networks",
)

result = asyncio.run(orchestrator.run(spec))
```

---

## Input Modes

EurekaClaw supports three input modes that reflect how much structure the user provides:

### Level 1 — Detailed (specific conjecture)

The user provides a precise mathematical statement. The system immediately formalizes
it, decomposes it into lemmas, and attempts a proof. The planner's direction-generation
step is bypassed — the conjecture is used exactly as given.

```bash
eurekaclaw prove "The VC dimension of depth-d width-w ReLU networks is O(wd log(wd))"
```

### Level 2 — Reference (seed papers)

The user provides arXiv paper IDs. The SurveyAgent fetches and analyses them, then
the IdeationAgent identifies gaps and generates novel hypotheses. The best hypothesis
is forwarded to the Theory Agent.

```bash
eurekaclaw from-papers 1706.03762 2005.14165 --domain "attention mechanisms"
```

### Level 3 — Exploration (open domain)

The user specifies only a research domain. The system autonomously surveys the frontier,
identifies open problems, and proposes directions before choosing one to pursue.

```bash
eurekaclaw explore "spectral graph theory"
```

---

## Learning Modes

Control post-session learning with `--mode` (CLI) or `EUREKACLAW_MODE` (env):

### `skills_only` (default)

After each session, `SkillEvolver` analyses `FailedAttempt` records and distills new
proof strategies into `~/.metaclaw/skills/distilled_<name>.md`. No model weights are
modified.

### `rl`

In addition to skill distillation, `ProcessRewardModel` scores the full proof trajectory:
- Proved lemma: `+1.0`
- Counterexample found: `−0.5`
- LLM-judged partial progress: `0.0–0.8`

### `madmax`

All of `rl`, plus cloud-based LoRA fine-tuning (GRPO) of the primary model using the
PRM-scored proof trajectories. Requires cloud training infrastructure configuration.

---

## Evaluation

EurekaClaw includes a **Scientist-Bench** evaluator that scores a completed session
across five dimensions:

| Dimension | Weight | Description |
|---|---|---|
| `formal_correctness` | 0.35 | Proof validity (Lean4 check or LLM peer review) |
| `novelty` | 0.25 | Distance from known results (embedding-based) |
| `depth` | 0.15 | Lemma count and proof complexity |
| `citation_coverage` | 0.10 | Bibliography completeness |
| `experimental_alignment` | 0.15 | Consistency between theory and experiment |

```bash
eurekaclaw eval-session <session_id>
```

```json
{
  "session_id": "abc123",
  "composite_score": 0.74,
  "dimensions": {
    "formal_correctness": 0.80,
    "novelty": 0.65,
    "depth": 0.70,
    "citation_coverage": 0.60,
    "experimental_alignment": 0.75
  }
}
```

Session artifacts are stored in `~/.metaclaw/runs/<session_id>/`.

---

## Project Structure

```
EurekaClaw/
├── pyproject.toml                   # Package metadata and dependencies
├── .env.example                     # All configuration variables with defaults
│
└── eurekaclaw/
    ├── __init__.py                  # Lazy re-exports: EurekaSession, run_research
    ├── config.py                    # Pydantic Settings singleton (settings)
    ├── main.py                      # EurekaSession, run_research entry points
    ├── cli.py                       # Click CLI: prove, explore, from-papers, …
    ├── ccproxy_manager.py           # ccproxy lifecycle (OAuth via Claude Code)
    │
    ├── llm/                         # LLM backend abstraction
    │   ├── __init__.py              # Re-exports LLMClient, create_client
    │   ├── base.py                  # LLMClient ABC with .messages.create() interface
    │   ├── types.py                 # NormalizedMessage, NormalizedTextBlock, …
    │   ├── anthropic_adapter.py     # Wraps anthropic.AsyncAnthropic
    │   ├── openai_compat.py         # Translates Anthropic format ↔ OpenAI format
    │   └── factory.py               # create_client() — selects backend from settings
    │
    ├── types/                       # Shared Pydantic models
    │   ├── artifacts.py             # ResearchBrief, TheoryState, LemmaNode, …
    │   ├── tasks.py                 # Task, TaskPipeline, InputSpec, ResearchOutput
    │   ├── agents.py                # AgentRole, AgentResult
    │   ├── memory.py                # EpisodicEntry, CrossRunRecord, KnowledgeNode
    │   └── skills.py                # SkillMeta, SkillRecord
    │
    ├── knowledge_bus/
    │   └── bus.py                   # KnowledgeBus: typed artifact store + subscriptions
    │
    ├── agents/
    │   ├── session.py               # AgentSession: rolling conversation history
    │   ├── base.py                  # BaseAgent: tool-use loop, skill injection, retry
    │   ├── survey/agent.py          # SurveyAgent: arXiv + S2 + web + citations
    │   ├── ideation/agent.py        # IdeationAgent: divergent hypothesis generation
    │   ├── theory/
    │   │   ├── agent.py             # TheoryAgent: initializes state, runs inner loop
    │   │   ├── inner_loop.py        # TheoryInnerLoop: 6-stage proof loop
    │   │   ├── formalizer.py        # Informal → LaTeX theorem
    │   │   ├── decomposer.py        # Theorem → lemma DAG
    │   │   ├── prover.py            # Chain-of-thought proof attempts
    │   │   ├── verifier.py          # Lean4 / LLM verification
    │   │   ├── counterexample.py    # Adversarial counterexample search
    │   │   ├── refiner.py           # Conjecture refinement + DAG reset
    │   │   └── resource_analyst.py  # Math↔code bidirectional mapping
    │   ├── experiment/agent.py      # ExperimentAgent: numerical validation
    │   └── writer/agent.py          # WriterAgent: LaTeX or Markdown paper assembly
    │
    ├── orchestrator/
    │   ├── meta_orchestrator.py     # Central pipeline driver
    │   ├── planner.py               # DivergentConvergentPlanner (directions → best)
    │   ├── gate.py                  # GateController (human/auto/none) with status display
    │   ├── pipeline.py              # PipelineManager: builds 6-stage automated pipeline
    │   └── router.py                # TaskRouter: AgentRole → BaseAgent
    │
    ├── memory/
    │   ├── episodic.py              # Ring buffer of recent events (within session)
    │   ├── persistent.py            # Cross-run JSON store (~/.metaclaw/memory/)
    │   ├── knowledge_graph.py       # networkx theorem linkage graph
    │   └── manager.py               # MemoryManager: unified 3-tier interface
    │
    ├── skills/
    │   ├── registry.py              # SkillRegistry: load/upsert .md files
    │   ├── injector.py              # SkillInjector: top-k ranking + prompt rendering
    │   ├── evolver.py               # SkillEvolver: LLM-distilled failure → skill
    │   └── seed_skills/             # Built-in skills (installed via install-skills)
    │
    ├── tools/
    │   ├── base.py                  # BaseTool ABC
    │   ├── registry.py              # ToolRegistry + build_default_registry()
    │   ├── arxiv.py                 # ArxivSearchTool
    │   ├── semantic_scholar.py      # SemanticScholarTool
    │   ├── web_search.py            # WebSearchTool (Brave / SerpAPI)
    │   ├── code_exec.py             # CodeExecutionTool (subprocess / Docker)
    │   ├── lean4.py                 # Lean4Tool (formal verification)
    │   ├── wolfram.py               # WolframAlphaTool
    │   └── citation.py              # CitationManagerTool (BibTeX generation)
    │
    ├── learning/
    │   ├── failure_capture.py       # FailureCapturer: record task/proof failures
    │   ├── prm_scorer.py            # ProcessRewardModel: score proof trajectories
    │   └── loop.py                  # ContinualLearningLoop.post_run()
    │
    └── evaluation/
        └── evaluator.py             # ScientistBenchEvaluator: 5-dimension scoring

tests/
├── conftest.py                      # Shared fixtures (bus, research_brief, theory_state)
├── unit/
│   ├── test_knowledge_bus.py
│   ├── test_types.py
│   ├── test_theory_inner_loop.py
│   ├── test_skills_registry.py
│   ├── test_tools.py
│   └── test_planner.py
└── integration/
    └── test_theory_agent.py         # Requires ANTHROPIC_API_KEY
```

---

## Contributing

### Running tests

```bash
# Unit tests (no API key needed)
pytest tests/unit/ -v

# Integration tests (requires ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=sk-... pytest tests/integration/ -v

# Full suite with async support
pip install pytest-asyncio
pytest --asyncio-mode=auto
```

### Writing custom skills

Create a `.md` file with YAML frontmatter and drop it in `~/.metaclaw/skills/`:

```markdown
---
name: my_proof_technique
version: "1.0"
tags: [proof, analysis, compactness]
agent_roles: [theory]
pipeline_stages: [proof_attempt]
description: Apply Arzelà-Ascoli in functional analysis proofs
source: manual
---

# Arzelà-Ascoli Technique

When proving existence of a convergent subsequence in a space of continuous functions:

1. Show pointwise boundedness
2. Show equicontinuity via Lipschitz or modulus of continuity argument
3. Apply Arzelà-Ascoli to extract a uniformly convergent subsequence
4. Verify the limit is in the target function class
```

### Adding a new tool

Subclass `BaseTool` in `eurekaclaw/tools/`:

```python
from eurekaclaw.tools.base import BaseTool

class MyTool(BaseTool):
    name = "my_tool"
    description = "Does something useful"

    def input_schema(self) -> dict:
        return {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
        }

    async def call(self, query: str) -> str:
        return f"Result for: {query}"
```

Then register it in `eurekaclaw/tools/registry.py` inside `build_default_registry()`.

---

## License

MIT License. See `LICENSE` for details.
