# User Guide

A practical walkthrough for using EurekaClaw — from installation to reading your first generated paper.

---

## Table of Contents

1. [Installation](#installation)
2. [Authentication](#authentication)
3. [First Run](#first-run)
4. [Choosing an Input Mode](#choosing-an-input-mode)
5. [Running from the CLI](#running-from-the-cli)
6. [Using the Browser UI](#using-the-browser-ui)
7. [Using the Python API](#using-the-python-api)
8. [Understanding the Output](#understanding-the-output)
9. [Gate Mode and Human Review](#gate-mode-and-human-review)
10. [Tuning for Cost vs. Thoroughness](#tuning-for-cost-vs-thoroughness)
11. [Skills and Learning](#skills-and-learning)
12. [Troubleshooting](#troubleshooting)

---

## Installation

**Supported platforms:** macOS, Linux
*(Windows support is under development — use [WSL 2](https://learn.microsoft.com/en-us/windows/wsl/install) in the meantime)*

### Installer script (recommended)

**macOS / Linux**

```bash
curl -fsSL https://eurekaclaw.ai/install.sh | bash
```

**Windows** *(under development — not fully supported yet)*

```powershell
powershell -c "irm https://eurekaclaw.ai/install_win.ps1 | iex"
```

The macOS/Linux installer clones the repo, creates a virtual environment, installs EurekaClaw, and adds the `eurekaclaw` command to your PATH. Run `eurekaclaw onboard` afterwards to configure your API key and settings.

### Manual install

**Requirements:** Python ≥ 3.11, Node.js ≥ 20, Git

```bash
git clone https://github.com/EurekaClaw/EurekaClaw
cd EurekaClaw
make install                  # pip install -e "." + npm install (frontend)
```

### With all optional extras

```bash
pip install -e ".[openai,oauth]"
# openai  — enables OpenRouter and local vLLM/Ollama backends
# oauth   — enables Claude Pro/Max login (no API key needed)
```

### Optional system tools

| Tool | Purpose | Install |
|---|---|---|
| **pdflatex** + bibtex | Compile `paper.tex` → `paper.pdf` | TeX Live / MacTeX |
| **Lean4** | Formal proof verification | [leanprover.github.io](https://leanprover.github.io) |

EurekaClaw works without any of these — it just skips the associated step (PDF compilation, Lean verification).

> **Docker / sandboxed code execution** is **future work** — the experiment runner and `execute_python` tool are not yet safely sandboxed for general use. Keep `EXPERIMENT_MODE=false` until a future release adds proper sandbox support.

---

## Authentication

### Option A — Anthropic API key (most common)

```bash
cp .env.example .env
```

Edit `.env`:

```env
ANTHROPIC_API_KEY=sk-ant-...
```

### Option B — Claude Pro/Max via OAuth (no API key)

```bash
pip install "eurekaclaw[oauth]"
ccproxy auth login claude_api   # opens browser for one-time login
```

```env
ANTHROPIC_AUTH_MODE=oauth
```

EurekaClaw will automatically start/stop ccproxy alongside your session.

### Option C — OpenRouter or local model

```env
LLM_BACKEND=openrouter
OPENAI_COMPAT_BASE_URL=https://openrouter.ai/api/v1
OPENAI_COMPAT_API_KEY=sk-or-...
OPENAI_COMPAT_MODEL=anthropic/claude-sonnet-4-6
```

For local Ollama/vLLM:

```env
LLM_BACKEND=local
OPENAI_COMPAT_BASE_URL=http://localhost:11434/v1
OPENAI_COMPAT_MODEL=llama3
```

---

## First Run

```bash
# Install built-in proof skills (required — do this once)
eurekaclaw install-skills

# Prove a conjecture — output goes to ./results/
eurekaclaw prove "The sample complexity of transformers is O(L·d·log(d)/ε²)" \
    --domain "ML theory"
```

The pipeline takes several minutes. You will see live Rich cards after each stage:

```
━━━━━━━━━━━━━━━ Survey Complete ━━━━━━━━━━━━━━━
 Papers found       12
 Open problems       4
 Key objects         transformer, VC dimension, Rademacher complexity
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━ Theory Complete ━━━━━━━━━━━━━━━
 Status             proved
 Lemmas             6 (3 known · 1 adapted · 2 new)
 Confidence         ✓ high on 5 · ⚠ low on 1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

When the run finishes, artifacts are in `./results/<session_id>/`.

---

## Choosing an Input Mode

EurekaClaw has three input modes. Pick the one that matches how well-defined your goal is.

### Level 1 — Prove a specific conjecture (`prove`)

Use this when you have a concrete mathematical statement you want to prove.

The system uses your statement **exactly as given** — the direction-selection step is bypassed.

```bash
eurekaclaw prove "Any PAC-learnable class has finite VC dimension" \
    --domain "ML theory"

eurekaclaw prove "The VC dimension of depth-d width-w ReLU networks is O(wd·log(wd))" \
    --domain "deep learning theory"

eurekaclaw prove "For all n ≥ 1: Σᵢ₌₁ⁿ i = n(n+1)/2" \
    --domain "combinatorics"
```

**Tips for writing good conjectures:**
- State the result precisely, including asymptotic notation (`O(...)`, `Ω(...)`) when relevant
- Include the key parameters (e.g., `L` layers, `d` dimension, `ε` precision)
- Avoid vague language like "is efficient" — prefer "runs in polynomial time"

### Level 2 — Start from papers (`from-papers`)

Use this when you have specific papers you want to extend or find gaps in.

```bash
# Attention mechanism papers — find open problems and prove something new
eurekaclaw from-papers 1706.03762 2005.14165 \
    --domain "attention mechanisms"

# Bandit theory papers
eurekaclaw from-papers 1602.01783 2106.01336 \
    --domain "multi-armed bandits"
```

The SurveyAgent fetches and analyses the papers, then the IdeationAgent identifies research gaps and generates 5 candidate directions. The best-scoring direction is selected automatically (or by you with `--gate human`).

### Level 3 — Open exploration (`explore`)

Use this when you have a broad research area in mind but no specific conjecture.

```bash
# Broad domain exploration
eurekaclaw explore "spectral graph theory"

# Domain + guiding question
eurekaclaw explore "multi-armed bandit theory" \
    --query "What are the tightest known bounds for heavy-tailed rewards?"

# Pure math
eurekaclaw explore "algebraic topology" \
    --query "What are open problems in persistent homology?"
```

The system autonomously surveys the frontier, identifies open problems, proposes 5 directions, and selects the most promising one.

---

## Running from the CLI

### Basic usage

```bash
eurekaclaw prove "<conjecture>" [OPTIONS]
eurekaclaw explore "<domain>"   [OPTIONS]
eurekaclaw from-papers <id> [<id> ...] --domain "<domain>" [OPTIONS]
```

### Common options

| Option | Default | Description |
|---|---|---|
| `--domain`, `-d` | `""` | Research domain. Enables domain-specific tools and skills. |
| `--output`, `-o` | `./results` | Where to save artifacts |
| `--gate` | `none` | `none` — fully automatic; `auto` — cards + auto-escalate on low confidence; `human` — pause and ask you at each stage |
| `--mode` | `skills_only` | Post-run learning: `skills_only`, `rl`, `madmax` |
| `--skills` | *(all)* | Pin specific skill names so they are always injected first. Repeatable. (`prove` and `from-papers` only) |

### Verbose logging

```bash
eurekaclaw --verbose prove "..."   # shows DEBUG-level logs
```

### Useful commands

```bash
eurekaclaw onboard                               # interactive setup wizard
eurekaclaw skills                                # list all available skills
eurekaclaw install-skills                        # install seed skills
eurekaclaw install-skills --force                # overwrite existing skills
eurekaclaw eval-session <session_id>             # evaluate a past session
eurekaclaw replay-theory-tail <session_id>       # rerun assembler/crystallizer/checker
eurekaclaw test-paper-reader <session_id> <ref>  # test paper extraction on one paper
eurekaclaw ui --open-browser                     # launch browser UI
```

---

## Using the Browser UI

Launch the local web interface for a visual experience:

```bash
eurekaclaw ui --open-browser
```

Or with a custom port:

```bash
eurekaclaw ui --host 0.0.0.0 --port 8080 --open-browser
```

The UI provides:
- **Run panel** — enter conjecture/domain, configure options, start a session
- **Live progress** — real-time stage cards and log stream
- **Results viewer** — browse the generated paper, theory state, and experiment results
- **Settings tab** — edit all `.env` variables including token limit sliders
- **Skills tab** — browse and manage the skill bank

---

## Using the Python API

```python
import asyncio
from eurekaclaw.main import EurekaSession, save_artifacts

session = EurekaSession()

# Level 1 — prove a specific conjecture
result = asyncio.run(session.run_detailed(
    conjecture="The sample complexity of transformers is O(L·d·log(d)/ε²)",
    domain="ML theory",
))

# Level 2 — start from papers
result = asyncio.run(session.run_from_papers(
    paper_ids=["1706.03762", "2005.14165"],
    domain="attention mechanisms",
))

# Level 3 — open exploration
result = asyncio.run(session.run_exploration(
    domain="spectral graph theory",
    query="What are open problems in persistent homology?",
))

# Save artifacts and compile PDF
out_path = save_artifacts(result, "./results")
print(f"Paper at: {out_path}/paper.pdf")
```

### Accessing results programmatically

```python
import json

# Check if proof succeeded
state = json.loads(result.theory_state_json)
print("Status:", state["status"])          # "proved" / "refuted" / "abandoned"
print("Lemmas:", len(state["proof_plan"])) # total lemma count

# Check the selected direction
brief = json.loads(result.research_brief_json)
direction = brief["selected_direction"]
print("Direction:", direction["title"])
print("Novelty score:", direction["novelty_score"])

# Get the LaTeX paper
print(result.latex_paper[:500])
```

---

## Understanding the Output

After a run, `./results/<session_id>/` contains:

| File | Description |
|---|---|
| `paper.pdf` | Compiled PDF (requires pdflatex + bibtex) |
| `paper.tex` | Full LaTeX source — edit and recompile if needed |
| `references.bib` | BibTeX bibliography |
| `theory_state.json` | Full proof state — lemmas, proofs, confidence scores |
| `research_brief.json` | Planning state — directions scored and selected |
| `experiment_result.json` | Numerical validation results (if experiment ran) |

### Reading `theory_state.json`

Key fields to check:

```json
{
  "status": "proved",
  "proof_plan": [
    {
      "lemma_id": "concentration_bound",
      "provenance": "known",
      "statement": "For sub-Gaussian ..."
    },
    {
      "lemma_id": "main_result",
      "provenance": "new",
      "statement": "The sample complexity ..."
    }
  ],
  "proven_lemmas": {
    "main_result": {
      "verified": true,
      "confidence_score": 0.91,
      "verification_method": "llm_check",
      "proof_text": "..."
    }
  },
  "failed_attempts": [...],
  "counterexamples": [...]
}
```

**Proof status meanings:**

| Status | Meaning |
|---|---|
| `proved` | All lemmas verified, assembled proof complete |
| `refuted` | A counterexample was found; the conjecture is false (or needs refinement) |
| `abandoned` | Hit `THEORY_MAX_ITERATIONS` without completing; partial proof saved |
| `in_progress` | (Intermediate state — not seen in final output) |

**Lemma provenance:**

| Provenance | Meaning |
|---|---|
| `known` | Directly citable — no new proof needed, just a citation |
| `adapted` | A known result modified to fit this context |
| `new` | Genuinely novel — fully proved from scratch |

### Low-confidence warnings in the PDF

If a lemma has `verified=false`, the PDF will contain:

```
[Unverified step]   ← orange text
```

and a **Limitations** section at the end of the paper. This means the proof step was not formally confirmed and should be manually reviewed before submission.

---

## Gate Mode and Human Review

EurekaClaw includes interactive gates that pause the pipeline and ask for your input at key decision points. Gates work in both the browser UI and the CLI.

### Browser UI gates

When running `eurekaclaw ui`, gates appear as overlay dialogs on top of the workspace — no matter which tab you are on. There are three gates:

**Survey gate** — triggers when the literature survey finds 0 papers.

The overlay asks you to provide paper IDs or arXiv IDs to retry the survey, or to continue without papers.

**Direction gate** — triggers when ideation returns no candidate research directions (detailed/prove mode).

The overlay shows the original conjecture as a default and lets you type a custom direction, or accept the conjecture as-is.

**Theory review gate** — triggers after the theorem-prover completes.

The overlay shows the assembled proof and lets you either approve it (pipeline continues to experiments and writing) or flag a specific lemma with a reason. Flagging causes the theory agent to re-run with your feedback injected. After a configurable number of retries (`THEORY_REVIEW_MAX_RETRIES`, default 3) the proof is auto-approved.

### CLI gates

When running from the terminal, the same gates appear as interactive prompts:

### `--gate none` (default)

Fully automatic. The pipeline runs end-to-end with no interaction. Summary cards are still printed but no pauses.

```bash
eurekaclaw prove "..." --gate none
```

### `--gate auto`

Summary cards are printed after each stage. The system pauses for human review only when a low-confidence lemma is detected (i.e., when `verified=false` after the theory stage). Good for runs where you want to catch problems without constant interruption.

```bash
eurekaclaw prove "..." --gate auto
```

### `--gate human`

Pauses at every stage gate and asks for approval. After approving, you can optionally type a correction or hint:

```
Approve theory stage? [y/n] y
Any feedback for the next stage? (Enter to skip): Use Bernstein instead of Hoeffding for lemma 3
```

Your feedback is injected directly into the next agent's prompt.

```bash
eurekaclaw prove "..." --gate human
```

**Auto-escalation:** Even with `--gate auto`, if any lemma has `verified=false`, the gate automatically escalates to human review for that stage.

---

## Tuning for Cost vs. Thoroughness

### Quick and cheap (good for exploration)

```env
CONTEXT_COMPRESS_AFTER_TURNS=4
AUTO_VERIFY_CONFIDENCE=0.80
STAGNATION_WINDOW=2
MAX_TOKENS_PROVER=2048
MAX_TOKENS_AGENT=4096
```

### Balanced (default settings)

```env
CONTEXT_COMPRESS_AFTER_TURNS=6
AUTO_VERIFY_CONFIDENCE=0.95
STAGNATION_WINDOW=3
```

### Maximum thoroughness (for final results)

```env
CONTEXT_COMPRESS_AFTER_TURNS=0   # no compression
AUTO_VERIFY_CONFIDENCE=0.99      # almost always do full peer review
STAGNATION_WINDOW=5
MAX_TOKENS_PROVER=4096
MAX_TOKENS_AGENT=8192
```

### Key settings explained

**`CONTEXT_COMPRESS_AFTER_TURNS`** — Every N tool-use turns, the agent's conversation history is compressed to a bullet summary using the fast model. Lower = cheaper but agents "forget" more context. Set to `0` to disable compression entirely.

**`AUTO_VERIFY_CONFIDENCE`** — If the prover's self-reported confidence ≥ this value and no `[GAP:]` flags are present, the proof is accepted without a separate verifier call. Lower = fewer verifier calls (cheaper). Default 0.95 means the prover must be very confident before skipping the LLM Verifier.

**`STAGNATION_WINDOW`** — If the same lemma fails N consecutive times with a similar error, the loop forces a conjecture refinement instead of retrying. Prevents wasted calls on an unresolvable proof path.

**`EXPERIMENT_MODE`** *(future work)* — Numerical experiment execution is not yet safely sandboxed. Keep this set to `false`. See [Experiment Runner](#experiment-runner-future-work) below.

**`THEORY_MAX_ITERATIONS`** — Maximum proof loop iterations. Increase for very hard theorems; decrease for faster (but potentially incomplete) results.

---

## Skills and Learning

### What are skills?

Skills are Markdown files that encode successful proof strategies, domain conventions, and common techniques. They are injected into agent prompts before each task, improving results without retraining the model.

Skills are stored in `~/.eurekaclaw/skills/`.

### Viewing your skills

```bash
eurekaclaw skills
```

### Installing the built-in seed skills

```bash
eurekaclaw install-skills
eurekaclaw install-skills --force   # overwrite existing
```

### How EurekaClaw learns

After each session, the `ContinualLearningLoop` runs automatically (in `skills_only` mode by default). It:
1. Extracts unique failure patterns from the session
2. Distills successful proof strategies using the LLM
3. Writes new `.md` skill files to `~/.eurekaclaw/skills/`

These new skills are automatically used in future sessions.

### Learning modes

Set `EUREKACLAW_MODE` in `.env`:

| Mode | What runs after each session |
|---|---|
| `skills_only` (default) | Distill failures into new skill files |
| `rl` | Skill distillation + Process Reward Model scoring of proof trajectories |
| `madmax` | Skill distillation + PRM scoring + cloud LoRA fine-tuning (GRPO) |

### Pinning specific skills for a run

If you know which skills are most relevant for a particular conjecture, you can pin them with `--skills`:

```bash
eurekaclaw prove "UCB1 achieves O(sqrt(KT log T)) regret" \
    --domain "multi-armed bandits" \
    --skills ucb_regret_analysis \
    --skills concentration_inequalities
```

Pinned skills are always placed at the front of the top-k injection, before any automatically-selected optional skills. This is useful when:
- A distilled skill is highly relevant but has low `usage_count` and would otherwise be ranked lower
- You want to force injection of a manually-written custom skill for a specific proof

Use `eurekaclaw skills` to see the names of available skills.

### Writing skills manually

Create a `.md` file in `~/.eurekaclaw/skills/`:

```markdown
---
name: my_technique
version: "1.0"
tags: [probability, concentration]
agent_roles: [theory]
pipeline_stages: [theory]
description: When to use Azuma-Hoeffding vs Bernstein
source: manual
created_at: 2026-03-19T00:00:00
---

# Azuma vs Bernstein

Use Azuma-Hoeffding when:
- Bounded differences condition holds
- Variance is unknown

Use Bernstein when:
- You have a bound on the variance
- Gives tighter constant factors for small variance
...
```

---

## Troubleshooting

### `paper.pdf` not generated

**Cause:** `pdflatex` not installed or not in `PATH`.

**Fix:**
- Install TeX Live: `sudo apt install texlive-full` (Linux) or MacTeX (Mac)
- Set `LATEX_BIN` to the full path: `LATEX_BIN=/usr/local/bin/pdflatex`

The `.tex` and `.bib` files are always saved — you can compile manually or upload to Overleaf.

---

### Citations show as `?` in the PDF

**Cause:** Usually a bibtex issue. Run the compile sequence manually:

```bash
cd results/<session_id>
pdflatex paper.tex
bibtex paper
pdflatex paper.tex
pdflatex paper.tex
```

If `references.bib` exists but cite keys still don't resolve, the `.bib` file may have different keys than what `paper.tex` uses. Check that `references.bib` is non-empty.

---

### `Parsed zero lemmas from architect response`

**Cause:** The LLM returned an unrecognized format for the proof plan.

**Fix:** This is handled automatically via a 4-pass parser with a plain-text fallback. If it still happens, set `EUREKACLAW_MODEL` to a more capable model and retry.

---

### Proof status is `abandoned`

**Cause:** Hit `THEORY_MAX_ITERATIONS` without completing all lemmas.

**Fix options:**
1. Increase `THEORY_MAX_ITERATIONS=20`
2. Simplify the conjecture — split it into smaller parts
3. Use `--gate human` to provide hints during the run

The partial proof is still saved in `theory_state.json`.

---

### The proof was `refuted`

**Cause:** A counterexample was found — the conjecture as stated is false or needs refinement.

**What to do:**
1. Check `theory_state.json` → `counterexamples[]` for the specific falsifying example
2. Refine your conjecture (tighten conditions, change the bound)
3. Re-run with the updated conjecture

---

### Rate limit / API errors

**Cause:** Anthropic API rate limit hit during a long run.

**Fix:** EurekaClaw retries automatically with exponential backoff (5 attempts, 4–90 second waits). If errors persist:
- Reduce `MAX_TOKENS_AGENT` and `MAX_TOKENS_PROVER`
- Set `CONTEXT_COMPRESS_AFTER_TURNS=4` to reduce input tokens
- Set `EXPERIMENT_MODE=false` to skip the experiment stage *(recommended — see below)*

---

### Lean4 verification not running

**Cause:** `lean` binary not found in `PATH`.

**Fix:** Install Lean4 and set `LEAN4_BIN=/path/to/lean`. Without Lean4, the verifier falls back to LLM peer review, which still works but is less rigorous.

---

### The output paper has `[Unverified step]` warnings

**Cause:** One or more lemmas have `verified=false` — the prover couldn't confirm them.

**What to do:**
1. Check which lemmas are flagged in `theory_state.json` → `proven_lemmas`
2. Re-run with `--gate human` and provide hints at the theory gate
3. Increase `THEORY_MAX_ITERATIONS` to give the prover more attempts
4. Simplify the conjecture or break it into smaller lemmas

---

## Experiment Runner *(Future Work)* {#experiment-runner-future-work}

The **ExperimentAgent** and the `execute_python` tool — which numerically validate theorem bounds by running LLM-generated Python — are **not yet safely sandboxed** for general use.

**Current behavior without Docker:** LLM-generated code is executed directly in a host subprocess with a 30-second timeout. There is no filesystem or network isolation.

**Current behavior with Docker (`USE_DOCKER_SANDBOX=true`):** Code runs inside `python:3.11-slim` with 512 MB RAM and network disabled. However, Docker must be installed and the daemon running; if Docker is unavailable the tool silently falls back to the host subprocess.

Until proper sandboxing lands in a future release:

- Keep `EXPERIMENT_MODE=false` in your `.env`
- Do **not** rely on `USE_DOCKER_SANDBOX=true` as a security boundary
- The `experiment_result.json` output file will not be produced

---

## Example Workflows

### Prove a known result (sanity check)

```bash
eurekaclaw prove "The sum of the first n natural numbers equals n(n+1)/2" \
    --domain "combinatorics" --output ./results
```

Expected: `proved` with 1–2 simple lemmas in < 5 minutes.

### Explore an open research area

```bash
eurekaclaw explore "graph neural networks" \
    --query "What complexity-theoretic barriers exist for GNN expressiveness?" \
    --gate auto --output ./results
```

### Reproduce + extend a known paper result

```bash
# Start from the Attention Is All You Need paper
eurekaclaw from-papers 1706.03762 \
    --domain "transformer theory" --gate human --output ./results
```

### Domain-specific MAB research

```bash
eurekaclaw prove "UCB1 achieves O(sqrt(KT log K)) regret for K-armed Gaussian bandits" \
    --domain "multi-armed bandits" --output ./results
```

The MAB domain plugin automatically activates, providing specialized tools (regret decomposition, concentration bounds, bandit simulation) and seed skills.
