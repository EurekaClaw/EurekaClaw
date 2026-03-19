# EurekaClaw Documentation

EurekaClaw is a multi-agent autonomous research system for generating and proving theoretical results in mathematics and machine learning. It runs a complete pipeline from literature survey through formal proof to paper writing.

## Documentation Index

| Document | Description |
|---|---|
| [user-guide.md](user-guide.md) | **Start here** — installation, usage walkthrough, troubleshooting |
| [architecture.md](architecture.md) | System overview, pipeline stages, data flow |
| [configuration.md](configuration.md) | All `.env` settings and their effects |
| [api.md](api.md) | Python API — `EurekaSession`, `KnowledgeBus`, data models |
| [agents.md](agents.md) | Each agent's role, inputs, outputs, and tool usage |
| [tools.md](tools.md) | All research tools: arXiv, Lean4, code execution, etc. |
| [cli.md](cli.md) | CLI commands and options |
| [memory.md](memory.md) | Three-tier memory system |
| [skills.md](skills.md) | Skill registry, injection, and distillation |
| [domains.md](domains.md) | Domain plugin system and how to add new domains |
| [changelog.md](changelog.md) | Summary of all updates from UPDATES.md |

## Quick Start

```bash
# Prove a specific conjecture (outputs to ./results/)
eurekaclaw prove "The sample complexity of transformers is O(L·d·log(d)/ε²)"

# Open domain exploration
eurekaclaw explore "multi-armed bandit theory"

# Launch browser UI
eurekaclaw ui --open-browser
```

## Architecture at a Glance

```
InputSpec
    │
    ▼
MetaOrchestrator
    ├── SurveyAgent       — literature search (arXiv, Semantic Scholar)
    ├── IdeationAgent     — hypothesis generation (5 directions → 1 selected)
    ├── [GateController]  — optional human review
    ├── TheoryAgent       — 7-stage bottom-up proof pipeline
    │     ├── PaperReader → GapAnalyst → ProofArchitect
    │     ├── LemmaDeveloper (Prover + Verifier + Refiner loop)
    │     ├── Assembler → TheoremCrystallizer → ConsistencyChecker
    ├── ExperimentAgent   — numerical validation (optional)
    └── WriterAgent       — LaTeX/Markdown paper generation
            │
            ▼
    ResearchOutput (paper.tex / paper.pdf / references.bib / theory_state.json)
```
