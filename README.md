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
| `survey` | `SurveyAgent` | Literature search via arXiv, Semantic Scholar, web |
| `ideation` | `IdeationAgent` | Generate and rank research directions |
| `theory` | `TheoryAgent` | Formal math: 6-stage proof loop (see above) |
| `experiment` | `ExperimentAgent` | Empirical validation of theoretical bounds |
| `writer` | `WriterAgent` | Full paper assembly (LaTeX or Markdown) |

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
| `ANTHROPIC_API_KEY` | — | Anthropic API key |
| `EUREKACLAW_MODEL` | `claude-opus-4-6` | Primary reasoning model |
| `EUREKACLAW_FAST_MODEL` | `claude-haiku-4-5-20251001` | Fast model for lightweight tasks |
| `EUREKACLAW_MODE` | `skills_only` | Learning mode: `skills_only` \| `rl` \| `madmax` |
| `OUTPUT_FORMAT` | `latex` | Paper format: `latex` or `markdown` |
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

EurekaClaw will automatically start and stop ccproxy around each session.

---

## CLI Reference

### `eurekaclaw prove` — Prove a specific conjecture

```bash
eurekaclaw prove "Any PAC-learnable class has finite VC dimension" \
    --domain "ML theory" --mode skills_only --output ./results
```

Artifacts written to `--output`: `paper.tex`, `paper.pdf`, `theory_state.json`

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

**`ResearchOutput` fields:** `session_id`, `latex_paper`, `theory_state_json`, `experiment_result_json`, `research_brief_json`

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
