# 🦞 EurekaClaw — The Research Claw

<p align="center">
  <strong>The AI that catches your Eureka moments.</strong><br/>
  Crawls arXiv · Generates theorems · Proves lemmas · Writes LaTeX papers · Runs experiments<br/>
  All from your chat or terminal.
</p>

<p align="center">
  <a href="https://github.com/EurekaClaw/EurekaClaw_dev_zero/stargazers"><img src="https://img.shields.io/github/stars/EurekaClaw/EurekaClaw_dev_zero?style=flat-square&color=007ACC" alt="Stars"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-007ACC?style=flat-square" alt="MIT License"/></a>
  <img src="https://img.shields.io/badge/python-3.11%2B-007ACC?style=flat-square" alt="Python 3.11+"/>
  <img src="https://img.shields.io/badge/local--first-private%20by%20default-1F8AD2?style=flat-square" alt="Local-first"/>
</p>

```
$ eurekaclaw ask "Find recent papers on sparse attention + prove efficiency bound"

🦞 Crawling arXiv cs.LG (2024–2025)...
📄 Found 23 relevant papers. Summarizing...
💡 Hypothesis generated: O(n log n) via topological filtration
✨ Theorem 3.1 drafted. LaTeX ready. Proof complete.
🦞 Eureka! Paper draft saved to ./eureka_2025_sparse_attn.tex
```

---

**EurekaClaw** is a multi-agent AI research assistant that helps you go from a question to a publishable result — autonomously. It crawls the literature, generates and stress-tests hypotheses, runs experiments, and writes up findings, all from your terminal or chat app.

EurekaClaw ships with a suite of specialized agents ("claws"), each handling a different part of the research pipeline. One standout is the built-in **Theory Agent** — a dedicated agent for formal mathematical research that synthesizes proof-heavy, formalism-rich work across ML theory, computational complexity, probability, and pure mathematics through an iterative 6-stage proof loop.

Inspired by [OpenClaw](https://github.com/openclaw/openclaw) — built for researchers.

> **Open Source · Local-First · Private by Default · MIT License**

---

## Eight Claws — What EurekaClaw Does

| | Feature | Description |
|---|---|---|
| 🔍 | **arXiv & Literature Crawler** | Fetch, summarize, and cross-reference papers from arXiv, Semantic Scholar, and Google Scholar. Build your literature review in minutes, not weeks. |
| 💡 | **Eureka Idea Generator** | Brainstorm research breakthroughs and novel hypotheses by synthesizing patterns across thousands of papers. Catch connections humans miss. |
| 🔢 | **Theorem & Lemma Prover** | Generate, verify, and formalize mathematical proofs. Interfaces with Lean 4, Coq, and Isabelle. From conjecture to QED in one command. |
| 📄 | **LaTeX Paper Writer** | Drafts full camera-ready papers with structured sections, theorem environments, auto-generated figures (matplotlib / tikz), and correctly formatted citations. |
| 🖥️ | **Runs Locally** | Your research stays private. Use Ollama, LM Studio, or llama.cpp with any local model. No data leaves your machine. Ever. |
| 💬 | **Works in Any Chat App** | Integrates with Slack, Telegram, WhatsApp, Discord, and any MCP-compatible client. Catch your Eureka right where your team collaborates. |
| 🧠 | **Persistent Research Memory** | Remembers your entire research history, past papers, experiments, and hypotheses. Manages citations and your personal knowledge graph automatically. |
| 🧪 | **Experiment Runner** | Writes, runs, and evaluates ML experiments. Integrates with Jupyter, Weights & Biases, and your existing codebase. Hypothesis → result in one loop. |

---

## Quick Start

**Requirements:** Python ≥ 3.11

```bash
# Install from source
git clone https://github.com/EurekaClaw/EurekaClaw_dev_zero
cd EurekaClaw_dev_zero
pip install -e "."
cp .env.example .env   # set ANTHROPIC_API_KEY or configure OAuth

# Install built-in proof skills
eurekaclaw install-skills

# Prove a conjecture
eurekaclaw prove "The sample complexity of transformers is O(L·d·log(d)/ε²)" \
    --domain "ML theory" --output ./results

# Open-ended exploration
eurekaclaw explore "spectral graph theory" \
    --query "What are open problems in persistent homology?"

# Start from papers
eurekaclaw from-papers 1706.03762 2005.14165 --domain "attention mechanisms"
```

> No API key? Use a Claude Pro/Max subscription via [OAuth](#oauth-via-ccproxy-claude-promax-no-api-key).

---

## Theory Agent — The 6-Stage Proof Loop

The **Theory Agent** is EurekaClaw's built-in agent for formal mathematical research. At its core is an iterative inner loop that takes an informal conjecture all the way to a verified proof (or a principled refutation):

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
                                         └──────────────► restart loop
```

The loop runs until all lemmas are proven, a maximum iteration limit is reached, or the conjecture is irrefutably refuted.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         CLI / Python API                         │
├──────────────────────────────────────────────────────────────────┤
│                         MetaOrchestrator                         │
│       ┌───────────────────────────────────────────────┐          │
│       │          DivergentConvergentPlanner           │          │
│       └───────────────────────────────────────────────┘          │
├─────────────┬──────────────┬─────────────┬────────────┬──────────┤
│ SurveyAgent │ IdeationAgent│ TheoryAgent │ Experiment │  Writer  │
│             │              │ (6-stage    │   Agent    │  Agent   │
│             │              │  proof loop)│            │          │
├─────────────┴──────────────┴─────────────┴────────────┴──────────┤
│                           KnowledgeBus                           │
│       research_brief · theory_state · bibliography · results     │
├─────────────────────────────┬────────────────────────────────────┤
│           Memory            │              Skills                │
│  Episodic · Persistent      │  Registry · Injector · Evolver     │
│  KnowledgeGraph             │  seed_skills / ~/.metaclaw/        │
├─────────────────────────────┴────────────────────────────────────┤
│                           Tool Layer                             │
│       arxiv · SemanticScholar · WebSearch · CodeExec             │
│       Lean4 · WolframAlpha · CitationManager                     │
└──────────────────────────────────────────────────────────────────┘
```

**Automated pipeline stages** (no human gates by default):

| Stage | Agent | Description |
|---|---|---|
| `survey` | SurveyAgent | Literature search via arXiv, Semantic Scholar, web |
| `ideation` | IdeationAgent | Generate and rank research directions |
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

```bash
eurekaclaw install-skills           # install to ~/.metaclaw/skills/
eurekaclaw install-skills --force   # overwrite existing
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

### From source

```bash
git clone https://github.com/EurekaClaw/EurekaClaw_dev_zero
cd EurekaClaw_dev_zero
pip install -e "."          # core install
pip install -e ".[dev]"     # + test extras
```

### Optional dependencies

```bash
pip install "eurekaclaw[openai]"   # OpenAI-compatible backends (OpenRouter, vLLM…)
pip install "eurekaclaw[oauth]"    # ccproxy OAuth (Claude Pro/Max, no API key)
```

### Optional system tools

- **Lean4** — formal verification (`lean` binary in `PATH`)
- **TeX Live / MacTeX** — PDF generation
- **Docker** — sandboxed code execution (`USE_DOCKER_SANDBOX=true`)

---

## Configuration

Copy `.env.example` and fill in your settings:

```bash
cp .env.example .env
```

### Key settings

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Anthropic API key (not needed when using OAuth) |
| `EUREKACLAW_MODEL` | `claude-opus-4-6` | Primary model for deep reasoning |
| `EUREKACLAW_FAST_MODEL` | `claude-haiku-4-5-20251001` | Fast model for lightweight tasks (verification, compression, skill distillation). Falls back to `EUREKACLAW_MODEL` if left empty. |
| `EUREKACLAW_MODE` | `skills_only` | Learning mode: `skills_only` \| `rl` \| `madmax` |
| `OUTPUT_FORMAT` | `latex` | Paper format: `latex` or `markdown` |
| `GATE_MODE` | `none` | Gate mode: `none` \| `auto` \| `human` |
| `THEORY_MAX_ITERATIONS` | `10` | Max proof loop iterations |
| `METACLAW_DIR` | `~/.metaclaw` | Skills, memory, and run artifacts |
| `BRAVE_SEARCH_API_KEY` | — | Optional. Web search via Brave |
| `WOLFRAM_APP_ID` | — | Optional. WolframAlpha computations |
| `LEAN4_BIN` | `lean` | Path to Lean4 binary |
| `USE_DOCKER_SANDBOX` | `false` | Sandbox code execution in Docker |

### LLM backends

**Anthropic (default):**
```env
LLM_BACKEND=anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

**OpenAI-compatible (OpenRouter, vLLM, LM Studio, Ollama):**
```env
LLM_BACKEND=openai_compat
OPENAI_COMPAT_BASE_URL=https://openrouter.ai/api/v1
OPENAI_COMPAT_API_KEY=sk-or-v1-...
OPENAI_COMPAT_MODEL=anthropic/claude-opus-4-6
```

### OAuth via ccproxy (Claude Pro/Max, no API key)

```bash
pip install "eurekaclaw[oauth]"
ccproxy auth login claude_api
```

```env
ANTHROPIC_AUTH_MODE=oauth
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

PDF compilation runs the full bibliography-aware sequence:
`pdflatex → bibtex → pdflatex → pdflatex`. A `references.bib` file is generated
from the session bibliography and written next to `paper.tex` before compilation,
so all `\cite{}` keys are resolved. If `pdflatex` is not found, a warning is
printed and `paper.tex`/`references.bib` are still saved.
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

#### Token limits per call type

Each LLM call type has an independently configurable output token budget, adjustable
in `.env` or via the UI sliders in the Settings tab:

| Variable | Default | Call type |
|---|---|---|
| `MAX_TOKENS_AGENT` | `8192` | Main agent reasoning loop (all agents) |
| `MAX_TOKENS_PROVER` | `4096` | Proof generation |
| `MAX_TOKENS_PLANNER` | `4096` | Research direction planning (diverge phase) |
| `MAX_TOKENS_DECOMPOSER` | `2048` | Lemma decomposition |
| `MAX_TOKENS_FORMALIZER` | `2048` | Theorem formalization, refiner, counterexample, resource analyst |
| `MAX_TOKENS_VERIFIER` | `1024` | Proof verification |
| `MAX_TOKENS_COMPRESS` | `512` | Context compression summaries (fast model) |

Reduce these to lower API cost; increase `MAX_TOKENS_PROVER` and `MAX_TOKENS_AGENT`
for more complex theorems that need longer outputs.

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

## CLI Reference

### `eurekaclaw prove` — Prove a specific conjecture

```bash
eurekaclaw prove "Any PAC-learnable class has finite VC dimension" \
    --domain "ML theory" --mode skills_only --output ./results
```

Artifacts written to `--output`:
- `paper.tex` — full LaTeX source
- `references.bib` — BibTeX bibliography (generated from session literature search)
- `paper.pdf` — compiled PDF (requires `pdflatex` + `bibtex`)
- `theory_state.json` — lemma DAG, proof records, counterexamples
- `research_brief.json` — selected research direction and domain metadata
- `experiment_result.json` — numerical validation results (when experiment ran)

**Options:** `--domain / -d`, `--mode` (`skills_only` | `rl` | `madmax`), `--gate` (`none` | `auto` | `human`), `--output / -o`

### `eurekaclaw explore` — Open domain exploration

```bash
eurekaclaw explore "sample complexity of transformers" \
    --query "What are the tightest known bounds?"
```

### `eurekaclaw from-papers` — Hypotheses from arXiv papers

```bash
eurekaclaw from-papers 2301.12345 2302.67890 --domain "ML theory"
```

### Other commands

```bash
eurekaclaw skills                        # list available skills
eurekaclaw install-skills [--force]      # install seed skills to ~/.metaclaw/skills/
eurekaclaw eval-session <session_id>     # evaluate a completed session
```

---

## Python API

```python
import asyncio
from eurekaclaw import EurekaSession

session = EurekaSession()

# Level 1 — prove a specific conjecture
result = asyncio.run(session.run_detailed(
    conjecture="For all n ≥ 1: Σᵢ₌₁ⁿ i = n(n+1)/2",
    domain="combinatorics",
))
print(result.latex_paper[:500])

# Level 2 — explore gaps around known papers
result = asyncio.run(session.run_from_papers(
    paper_ids=["1706.03762", "2005.14165"],
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
| `bibliography_json` | `str` | JSON dump of `Bibliography` (papers + BibTeX) — used to generate `references.bib` |

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

EurekaClaw supports three input modes:

### Level 1 — Detailed (specific conjecture)

The user provides a precise mathematical statement. The planner's direction-generation
step is bypassed — the conjecture is used exactly as given.

```bash
eurekaclaw prove "The VC dimension of depth-d width-w ReLU networks is O(wd log(wd))"
```

### Level 2 — Reference (seed papers)

The user provides arXiv paper IDs. The SurveyAgent fetches and analyses them, then
the IdeationAgent identifies gaps and generates novel hypotheses.

```bash
eurekaclaw from-papers 1706.03762 2005.14165 --domain "attention mechanisms"
```

### Level 3 — Exploration (open domain)

The user specifies only a research domain. The system autonomously surveys the
frontier, identifies open problems, and proposes directions before choosing one.

```bash
eurekaclaw explore "spectral graph theory"
```

---

## Learning Modes

| Mode | What happens after each session |
|---|---|
| `skills_only` (default) | `SkillEvolver` distills failures into new proof strategy `.md` files in `~/.metaclaw/skills/` |
| `rl` | Skills distillation + PRM scoring of proof trajectories |
| `madmax` | Skills distillation + PRM scoring + cloud LoRA fine-tuning (GRPO) |

---

## Evaluation

EurekaClaw includes a **Scientist-Bench** evaluator across five dimensions:

| Dimension | Weight | Description |
|---|---|---|
| `formal_correctness` | 0.35 | Proof validity (Lean4 or LLM peer review) |
| `novelty` | 0.25 | Distance from known results (embedding-based) |
| `depth` | 0.15 | Lemma count and proof complexity |
| `citation_coverage` | 0.10 | Bibliography completeness |
| `experimental_alignment` | 0.15 | Consistency between theory and experiment |

```bash
eurekaclaw eval-session <session_id>
```

---

## Works With Everything

EurekaClaw plugs into your existing research stack. No rewiring needed.

📚 arXiv · 🎓 Google Scholar · 📐 LaTeX / Overleaf · 🪐 Jupyter · 💻 VS Code
🤖 Claude · 🧠 GPT-4o · ♊ Gemini · 🦙 Ollama · 🔮 Obsidian · 📖 Zotero
∎ Lean 4 · 📊 W&B · 🐳 Docker · 💬 Slack · 🎮 Discord · ✈️ Telegram · 📱 WhatsApp

---

## Project Structure

```
EurekaClaw_dev_zero/
├── pyproject.toml
├── .env.example
└── eurekaclaw/
    ├── cli.py                   # prove, explore, from-papers, …
    ├── main.py                  # EurekaSession entry point
    ├── config.py                # Pydantic Settings singleton
    ├── llm/                     # LLM backend abstraction (Anthropic, OpenAI-compat)
    ├── types/                   # Shared Pydantic models
    ├── knowledge_bus/           # Typed artifact store (shared agent communication)
    ├── agents/
    │   ├── survey/              # arXiv + S2 + web + citations
    │   ├── ideation/            # Divergent hypothesis generation
    │   ├── theory/              # 6-stage proof loop (formalizer → refiner)
    │   ├── experiment/          # Numerical validation
    │   └── writer/              # LaTeX / Markdown paper assembly
    ├── orchestrator/            # MetaOrchestrator, planner, pipeline, gate
    ├── memory/                  # Episodic, persistent, knowledge graph
    ├── skills/                  # Registry, injector, evolver, seed skills
    ├── tools/                   # arxiv, S2, web search, Lean4, WolframAlpha, …
    ├── learning/                # Failure capture, PRM scorer, continual learning
    └── evaluation/              # Scientist-Bench 5-dimension evaluator

tests/
├── unit/                        # No API key needed
└── integration/                 # Requires ANTHROPIC_API_KEY
```

---

## Contributing

```bash
# Unit tests (no API key needed)
pytest tests/unit/ -v

# Integration tests
ANTHROPIC_API_KEY=sk-... pytest tests/integration/ -v

# Full suite
pip install pytest-asyncio
pytest --asyncio-mode=auto
```

### Writing custom proof skills

Drop a `.md` file with YAML frontmatter into `~/.metaclaw/skills/`:

```markdown
---
name: my_proof_technique
version: "1.0"
tags: [proof, analysis]
agent_roles: [theory]
pipeline_stages: [proof_attempt]
description: Apply Arzelà-Ascoli in functional analysis proofs
source: manual
---

# Arzelà-Ascoli Technique
...
```

### Adding a new tool

Subclass `BaseTool` in `eurekaclaw/tools/`, then register it in `build_default_registry()`.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built for researchers who believe the next breakthrough is one Eureka moment away. 🦞
</p>
