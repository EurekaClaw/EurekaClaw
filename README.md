<p align="center">
  <img src="assets/logo-cropped.png" width="90%" alt="EurekaClaw  — The Research Claw">
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

<p align="center">
  <strong>English</strong> | <a href="README_zh.md">中文</a>
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

(See [Installation](https://eurekaclaw.github.io/getting-started/installation.html) for detailed instruction)

**macOS / Linux**

```bash
curl -fsSL https://eurekaclaw.ai/install.sh | bash
```

**Windows**

```powershell
powershell -c "irm https://eurekaclaw.ai/install_win.ps1 | iex"
```

The macOS/Linux installer clones the repo, creates a virtual environment, installs EurekaClaw, and adds the `eurekaclaw` command to your PATH. Run `eurekaclaw onboard` afterwards to configure your API key and settings.

<details>
<summary>Docker — one-line install (recommended for servers — no sudo required)</summary>

**Requirements:** Docker only (user must be in the `docker` group — no sudo, no Python, no Node.js needed on the host)

**Pre-built images on Docker Hub:**

| Image | Tag | Size | Description |
|---|---|---|---|
| `eurekaclaw/eurekaclaw` | `latest` | ~10 GB | CPU — Python 3.11, Node.js 18, all dependencies pre-installed |
| `eurekaclaw/eurekaclaw` | `gpu` | ~13 GB | GPU — NVIDIA CUDA 12.4 + everything above |

```bash
# Pull the image (one-time, ~10 GB)
docker pull eurekaclaw/eurekaclaw
```

**One-line install — launch the browser UI:**
```bash
docker run --rm -it -p 8080:8080 -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw/eurekaclaw
# Open http://localhost:8080 in your browser
```

**GPU support (NVIDIA):**
```bash
docker run --rm -it -p 8080:8080 --gpus all \
  -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw/eurekaclaw:gpu
```

**With `.env` config file + persistent data:**
```bash
# Copy and edit .env first: cp .env.example .env
docker run --rm -it -p 8080:8080 --env-file .env \
  -v ~/.eurekaclaw:/root/.eurekaclaw eurekaclaw/eurekaclaw
```

**CLI mode (prove / explore / from-papers):**
```bash
docker run --rm -it -e ANTHROPIC_API_KEY=sk-ant-... \
  eurekaclaw/eurekaclaw prove "The sample complexity of transformers is O(L·d·log(d)/ε²)"

docker run --rm -it -e ANTHROPIC_API_KEY=sk-ant-... \
  eurekaclaw/eurekaclaw explore "multi-armed bandit theory"
```

**Interactive shell (full environment inside container):**
```bash
docker run --rm -it -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw/eurekaclaw bash
# Inside: eurekaclaw, python3, node, npm, uv are all available
```

**Remote server access (SSH):**

Use `--network host` so the container shares the server's network directly — no `-p` port mapping needed, and OAuth callbacks just work:

```bash
# Step 1: SSH into server with port forwarding
ssh -L 8080:localhost:8080 user@server-ip

# Step 2: On the server, run the container with host networking
docker run --rm -it --network host \
  -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw/eurekaclaw

# Step 3: Open http://localhost:8080 in your laptop's browser
```

> **Note:** No root/sudo required on the server — just Docker access. The container runs as root internally, so there are no permission issues for installing packages or writing files inside the container.

**Authentication: API Key vs OAuth (Claude Pro/Max)**

*Option A — API Key (simplest):*
```bash
docker run --rm -it --network host \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  eurekaclaw/eurekaclaw
```

*Option B — OAuth for Claude Pro/Max (no API key needed):*

```bash
# Step 1: SSH into server (forward UI port + OAuth callback port)
ssh -L 8080:localhost:8080 -L 54545:localhost:54545 user@server-ip

# Step 2: Start container with host networking + persistent credentials
docker run --rm -it --network host \
  -v ~/.config/ccproxy:/root/.config/ccproxy \
  -v ~/.eurekaclaw:/root/.eurekaclaw \
  eurekaclaw/eurekaclaw bash

# Step 3: Inside the container, run OAuth login (one-time)
ccproxy auth login claude_api
# Copy the URL → paste into your laptop's browser → authorize

# Step 4: Start EurekaClaw
ANTHROPIC_AUTH_MODE=oauth eurekaclaw ui --host 0.0.0.0 --port 8080

# Subsequent runs — credentials are saved, no re-login needed:
docker run --rm -it --network host \
  -e ANTHROPIC_AUTH_MODE=oauth \
  -v ~/.config/ccproxy:/root/.config/ccproxy \
  -v ~/.eurekaclaw:/root/.eurekaclaw \
  eurekaclaw/eurekaclaw
```

**Build locally (optional):**
```bash
git clone https://github.com/EurekaClaw/EurekaClaw && cd EurekaClaw
make docker            # CPU image
make docker-gpu        # GPU image (NVIDIA CUDA 12.4)
make docker-run        # run UI at http://localhost:8080
```

**Docker Compose:**
```bash
cp .env.example .env   # edit with your API key
docker compose up                    # CPU — UI at http://localhost:8080
docker compose --profile gpu up      # GPU (NVIDIA)
docker compose --profile dev up      # Development (hot-reload on :5173 + :7860)
```

See [docker-compose.yml](docker-compose.yml) for full configuration.
</details>

<details>
<summary>Manual install with uv (recommended — Linux / macOS)</summary>

**Requirements:** Python ≥ 3.11, Node.js ≥ 18, Git, [uv](https://docs.astral.sh/uv/)

```bash
# 1. Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. Clone the repository
git clone https://github.com/EurekaClaw/EurekaClaw
cd EurekaClaw

# 3. Create a virtual environment with Python 3.11 and activate it
uv venv --python 3.11 .venv
source .venv/bin/activate

# 4. Install Python dependencies + frontend
uv pip install -e "."
cd frontend && npm install && cd ..

# 5. Post-install setup
eurekaclaw install-skills     # install built-in proof skills
eurekaclaw onboard            # configure API key and settings
```
</details>

<details>
<summary>Manual install with pip (Linux / macOS)</summary>

**Requirements:** Python ≥ 3.11, Node.js ≥ 18, Git

```bash
git clone https://github.com/EurekaClaw/EurekaClaw
cd EurekaClaw
python3 -m venv .venv
source .venv/bin/activate
make install                  # pip install -e "." + npm install (frontend)
```
</details>

<details>
<summary>Manual install (Windows)</summary>

**Requirements:** Python ≥ 3.11, Node.js ≥ 18, Git

```bash
git clone https://github.com/EurekaClaw/EurekaClaw
cd EurekaClaw
powershell -ExecutionPolicy Bypass -File install_win.ps1
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

# Browser UI - recommended
eurekaclaw ui --open-browser
```

> No API key? Use a Claude Pro/Max subscription via [OAuth](https://eurekaclaw.github.io/getting-started/authentication.html#option-b-claude-pro-max-via-oauth).

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
| `ANTHROPIC_API_KEY` | — | API key (or use OAuth, see [User Guide](https://eurekaclaw.github.io/getting-started/authentication.html)) |
| `EUREKACLAW_MODEL` | `claude-sonnet-4-6` | Main reasoning model |
| `GATE_MODE` | `auto` | `none` · `auto` · `human` |
| `THEORY_PIPELINE` | `default` | `default` or `memory_guided` |
| `OUTPUT_FORMAT` | `latex` | `latex` or `markdown` |
| `EXPERIMENT_MODE` | `auto` | `auto` · `true` · `false` |
| `THEORY_MAX_ITERATIONS` | `10` | Max proof loop iterations |

Full reference → [configuration.md](https://eurekaclaw.github.io/reference/configuration.html)

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

To add a **custom skill**, drop a `.md` file into `~/.eurekaclaw/skills/` — see [Skills and Continual Learning](https://eurekaclaw.github.io/user-guide/skills-learning.html).

To add a **new research domain**, subclass `DomainPlugin` — see [Domain Plugin System](https://eurekaclaw.github.io/reference/domains.html).

To add a **new tool**, subclass `BaseTool` and register it — see [Research Tools](https://eurekaclaw.github.io/reference/tools.html).

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

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=EurekaClaw/EurekaClaw&type=Date)](https://www.star-history.com/#EurekaClaw/EurekaClaw&Date)


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
