<p align="center">
  <img src="assets/logo-cropped.svg" width="700" alt="EurekaClaw  — The Research Claw">
</p>

<p align="center">
  <strong>The AI that catches your Eureka moments.</strong><br/>
  Crawls arXiv · Generates theorems · Proves lemmas · Writes LaTeX papers · Runs experiments<br/>
  All from your chat or terminal.
</p>

<p align="center">
  <a href="https://github.com/EurekaClaw/EurekaClaw/stargazers"><img src="https://img.shields.io/github/stars/EurekaClaw/EurekaClaw?style=flat-square&color=yellow" alt="Stars"/></a>
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square" alt="License: Apache 2.0">
  <img src="https://img.shields.io/badge/python-3.11%2B-007ACC?style=flat-square&color=yellow" alt="Python 3.11+"/>
  <img src="https://img.shields.io/badge/local--first-private%20by%20default-1F8AD2?style=flat-square" alt="Local-first"/>
</p>

<p align="center">
  <a href="https://www.eurekaclaw.ai/"><img src="https://img.shields.io/badge/🌐%20Website-eurekaclaw.ai-007ACC?style=flat-square" alt="Website"/></a>
  <a href="https://eurekaclaw.github.io/"><img src="https://img.shields.io/badge/📚%20Docs-eurekaclaw.github.io-007ACC?style=flat-square&color=green" alt="Docs"/></a>
  <a href="https://www.xiaohongshu.com/user/profile/69bf26c7000000003402ea57"><img src="https://img.shields.io/badge/📕%20RedNote-Follow%20Us-FF2442?style=flat-square" alt="RedNote"/></a>
  <a href="https://discord.gg/SprC5BgmcW"><img src="https://img.shields.io/badge/💬%20Discord-Join%20Us-5865F2?style=flat-square" alt="Discord"/></a>
</p>

```
$ eurekaclaw prove "Find recent papers on sparse attention + prove efficiency bound"

🦞 Crawling arXiv cs.LG (2024–2025)...
📄 Found 23 relevant papers. Summarizing...
💡 Hypothesis generated: O(n log n) via topological filtration
✨ Theorem 3.1 drafted. LaTeX ready. Proof complete.
🦞 Eureka! Paper draft saved to ./results/
```

---

**EurekaClaw** is a multi-agent AI research assistant that goes from a question to a publishable result — autonomously. It crawls the literature, generates and stress-tests hypotheses, runs experiments, and writes up findings, all from your terminal or browser UI.

> **Open Source · Local-First · Privacy by Design · Apache 2.0 License**

---

## What EurekaClaw Does

| | Feature | Description |
|---|---|---|
| 🔍 | **Literature Crawler** | Fetch, summarize, and cross-reference papers from arXiv and Semantic Scholar |
| 💡 | **Idea Generator** | Brainstorm novel hypotheses by synthesizing patterns across thousands of papers |
| 🔢 | **Theorem Prover** | Generate, verify, and formalize proofs via a 7-stage bottom-up pipeline |
| 📄 | **Paper Writer** | Draft camera-ready LaTeX papers with theorem environments and citations |
| 🖥️ | **Runs Locally** | Compatible with Every Major Model API — Privacy by Design |
| 🧠 | **Continual Learning** | Distills proof strategies into skills after every session, improving over time |
| 🧪 | **Experiment Runner** *(under development)* | Numerically validates theoretical bounds; flags low-confidence lemmas |
| 🌐 | **Browser UI** | React + TypeScript interface — live agent track, proof sketch, pause/resume, skills manager |

---

## Installation

**macOS / Linux**

```bash
curl -fsSL https://eurekaclaw.ai/install.sh | bash
```

**Windows** *(under development — not fully supported yet)*

```powershell
powershell -c "irm https://eurekaclaw.ai/install_win.ps1 | iex"
```

The macOS/Linux installer clones the repo, creates a virtual environment, installs EurekaClaw, and adds the `eurekaclaw` command to your PATH. Run `eurekaclaw onboard` afterwards to configure your API key and settings.

> **Windows users:** native Windows support is under active development. In the meantime, use [WSL 2](https://learn.microsoft.com/en-us/windows/wsl/install) (Ubuntu) and follow the macOS/Linux instructions inside the WSL terminal.

<details>
<summary>Manual install (all platforms)</summary>

**Requirements:** Python ≥ 3.11, Node.js ≥ 20, Git

```bash
git clone https://github.com/EurekaClaw/EurekaClaw
cd EurekaClaw
make install                  # pip install -e "." + npm install (frontend)
```
</details>

---

## Quick Start

```bash
eurekaclaw onboard            # interactive setup wizard (creates .env)
# — or — cp .env.example .env and add ANTHROPIC_API_KEY manually

eurekaclaw install-skills     # install built-in proof skills (do once)

# Browser UI — build frontend and open in browser
make open

# CLI — prove a conjecture
eurekaclaw prove "The sample complexity of transformers is O(L·d·log(d)/ε²)" \
    --domain "ML theory" --output ./results

# CLI — explore a domain
eurekaclaw explore "multi-armed bandit theory"

# CLI — start from arXiv papers
eurekaclaw from-papers 1706.03762 2005.14165 --domain "attention mechanisms"
```

> No API key? Use a Claude Pro/Max subscription via [OAuth](https://github.com/EurekaClaw/EurekaClaw/blob/main/docs/configuration.md#llm-backend).

---

## Pipeline

<p align="center">
  <img src="docs/images/pipeline-overview.svg" alt="EurekaClaw Pipeline" width="640"/>
</p>

---

## Input Modes

| Command | Level | When to use |
|---|---|---|
| `eurekaclaw prove "<conjecture>"` | 1 | You have a precise mathematical statement to prove |
| `eurekaclaw from-papers <ids>` | 2 | You want to extend or find gaps in specific papers |
| `eurekaclaw explore "<domain>"` | 3 | You have a broad research area but no conjecture yet |

---

## Documentation

See detailed documentation in https://eurekaclaw.github.io/ .

| | |
|---|---|
| 📖 [**User Guide**](https://eurekaclaw.github.io/user-guide/index.html) | Installation, walkthrough, gate modes, tuning, troubleshooting |
| ⚙️ [**Configuration**](https://eurekaclaw.github.io/reference/configuration.html) | All `.env` variables with defaults |
| 🏗️ [**Architecture**](https://eurekaclaw.github.io/reference/architecture.html) | Pipeline stages, data flow, component design |
| 🤖 [**Agents**](https://eurekaclaw.github.io/reference/agents.html) | Each agent's role, inputs, outputs, and tool usage |
| 🔧 [**Tools**](https://eurekaclaw.github.io/reference/tools.html) | arXiv, Semantic Scholar, Lean4, WolframAlpha, code execution |
| 💻 [**CLI Reference**](https://eurekaclaw.github.io/reference/cli.html) | All commands and options |
| 🐍 [**Python API**](https://eurekaclaw.github.io/reference/api.html) | `EurekaSession`, `KnowledgeBus`, data models |
| 🧠 [**Memory System**](https://eurekaclaw.github.io/reference/memory.html) | Episodic, persistent, and knowledge graph tiers |
| ✨ [**Skills**](https://eurekaclaw.github.io/reference/skills.html) | Skill registry, injection, distillation, writing custom skills |
| 🔌 [**Domain Plugins**](https://eurekaclaw.github.io/reference/domains.html) | Plugin architecture, MAB domain, adding new domains |
| 🌐 [**UI Design**](https://eurekaclaw.github.io/user-guide/browser-ui.html) | React/TS architecture, component tree, run commands |

---

## Configuration Essentials

```bash
cp .env.example .env
```

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | API key (or use OAuth, see [User Guide](https://github.com/EurekaClaw/EurekaClaw/blob/main/docs/user-guide.md#authentication)) |
| `EUREKACLAW_MODEL` | `claude-sonnet-4-6` | Main reasoning model |
| `GATE_MODE` | `auto` | `none` · `auto` · `human` |
| `THEORY_PIPELINE` | `default` | `default` or `memory_guided` |
| `OUTPUT_FORMAT` | `latex` | `latex` or `markdown` |
| `EXPERIMENT_MODE` | `auto` | `auto` · `true` · `false` |
| `THEORY_MAX_ITERATIONS` | `10` | Max proof loop iterations |

Full reference → [configuration.md](https://github.com/EurekaClaw/EurekaClaw/blob/main/docs/configuration.md)

---

## Evaluation

EurekaClaw includes a **Scientist-Bench** evaluator:

| Dimension | Weight |
|---|---|
| Formal correctness (Lean4 / LLM peer review) | 0.35 |
| Novelty (embedding distance from known results) | 0.25 |
| Experimental alignment | 0.15 |
| Proof depth (lemma count) | 0.15 |
| Citation coverage | 0.10 |

```bash
eurekaclaw eval-session <session_id>
```

---

## Contributing

```bash
# Unit tests (no API key needed)
pytest tests/unit/ -v

# Integration tests
ANTHROPIC_API_KEY=sk-... pytest tests/integration/ -v

# Frontend type-check
make typecheck

# Frontend development (hot-reload)
make dev
```

To add a **custom skill**, drop a `.md` file into `~/.eurekaclaw/skills/` — see [skills.md](https://github.com/EurekaClaw/EurekaClaw/blob/main/docs/skills.md).

To add a **new research domain**, subclass `DomainPlugin` — see [domains.md](https://github.com/EurekaClaw/EurekaClaw/blob/main/docs/domains.md).

To add a **new tool**, subclass `BaseTool` and register it — see [tools.md](https://github.com/EurekaClaw/EurekaClaw/blob/main/docs/tools.md).

---

## Acknowledgements

EurekaClaw builds on ideas and inspiration from the broader AI-for-science community. We thank the authors of the following projects:

- [MetaClaw](https://github.com/aiming-lab/MetaClaw) — multi-agent research orchestration
- [AutoResearchClaw](https://github.com/aiming-lab/AutoResearchClaw) — automated research orchestration
- [EvoScientist](https://github.com/EvoScientist/EvoScientist) — evolutionary hypothesis generation
- [AI-Researcher](https://github.com/hkuds/ai-researcher) — automated research pipeline
- [Awesome AI for Science](https://github.com/ai-boost/awesome-ai-for-science) — curated resource list
- [Dr. Claw](https://github.com/OpenLAIR/dr-claw) — open research agent framework
- [OpenClaw](https://github.com/openclaw/openclaw) — open-source research claw
- [ClawTeam](https://github.com/HKUDS/ClawTeam) — collaborative research agents
- [ScienceClaw](https://github.com/beita6969/ScienceClaw) — science-focused research agent
- [Tirith](https://github.com/sheeki03/tirith) — terminal security scanner for URL threats, homograph attacks, and command injection (integrated for pre-exec code scanning; also used by [Hermes Agent](https://github.com/NousResearch/hermes-agent))

---

## Citation

If you use EurekaClaw in your research, please cite:

```bibtex
@misc{eurekaclaw2026,
  title     = {EurekaClaw: An AI Agent for Capturing Eureka Moments},
  author    = {Li, Xuheng and Di, Qiwei and Zhang, Chenggong and Ji, Kaixuan and Zhao, Qingyue and Liu, Yifeng and Zhang, Shiyuan and Gu, Quanquan},
  year      = {2026},
  url       = {https://github.com/EurekaClaw/EurekaClaw}
}
```

---

## License

Apache 2.0 License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built for researchers who believe the next breakthrough is one Eureka moment away. 🦞
</p>
