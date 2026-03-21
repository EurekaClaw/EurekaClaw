# CLI Reference

Install the package (or run `python -m eurekaclaw`) to get the `eurekaclaw` command.

## Global Options

| Flag | Description |
|---|---|
| `--verbose`, `-v` | Enable DEBUG logging |

---

## Commands

### `prove` — Prove a conjecture

```bash
eurekaclaw prove "<conjecture>" [OPTIONS]
```

**Arguments:**
- `conjecture` — The mathematical conjecture or claim to prove (string)

**Options:**

| Option | Default | Description |
|---|---|---|
| `--domain`, `-d` | `""` | Research domain. Auto-inferred from conjecture if omitted |
| `--mode` | `skills_only` | Post-run learning mode: `skills_only`, `rl`, `madmax` |
| `--gate` | `none` | Gate control: `human`, `auto`, `none` |
| `--output`, `-o` | `./results` | Output directory for artifacts |

**Example:**
```bash
eurekaclaw prove "UCB1 achieves O(sqrt(KT log T)) expected cumulative regret in the stochastic multi-armed bandit setting" \
  --domain "multi-armed bandit theory" \
  --gate human \
  --output ./results
```

---

### `explore` — Explore a research domain

```bash
eurekaclaw explore "<domain>" [OPTIONS]
```

**Arguments:**
- `domain` — The research domain to explore (string)

**Options:**

| Option | Default | Description |
|---|---|---|
| `--query`, `-q` | `""` | Specific research question within the domain |
| `--mode` | `skills_only` | Post-run learning mode: `skills_only`, `rl`, `madmax` |
| `--gate` | `none` | Gate control: `human`, `auto`, `none` |
| `--output`, `-o` | `./results` | Output directory for artifacts |

**Example:**
```bash
eurekaclaw explore "multi-armed bandit theory" \
  --query "tight regret bounds for heavy-tailed rewards" --output ./results
```

---

### `from-papers` — Generate hypotheses from reference papers

```bash
eurekaclaw from-papers <paper_id> [<paper_id> ...] [OPTIONS]
```

**Arguments:**
- `paper_ids` — One or more arXiv IDs or Semantic Scholar IDs (variadic)

**Options:**

| Option | Default | Description |
|---|---|---|
| `--domain`, `-d` | *(required)* | Research domain |
| `--mode` | `skills_only` | Post-run learning mode |
| `--gate` | `none` | Gate control |
| `--output`, `-o` | `./results` | Output directory |

**Example:**
```bash
eurekaclaw from-papers 1602.01783 2301.00774 \
  --domain "bandit algorithms" --output ./results
```

---

### `pause` — Pause a running session

```bash
eurekaclaw pause <session_id>
```

**Arguments:**
- `session_id` — Session ID of the running proof to pause (found in the console header at startup)

Writes a `pause.flag` file to `~/.eurekaclaw/sessions/<session_id>/`. The theory agent detects this flag at the next stage boundary, saves a checkpoint, and exits cleanly with a `ProofPausedException`. The partial proof state is preserved in `~/.eurekaclaw/sessions/<session_id>/checkpoint.json`.

You can also pause by pressing **Ctrl+C** during a run. EurekaClaw intercepts `SIGINT` and writes the pause flag instead of raising `KeyboardInterrupt`, giving the agent time to reach a clean checkpoint boundary.

**Example:**
```bash
# In a separate terminal while a proof is running:
eurekaclaw pause abc12345
```

---

### `resume` — Resume a paused session

```bash
eurekaclaw resume <session_id>
```

**Arguments:**
- `session_id` — Session ID of the paused proof to continue

Loads the checkpoint from `~/.eurekaclaw/sessions/<session_id>/checkpoint.json` and re-runs the theory agent starting from the saved stage, with all previously proved lemmas already in `TheoryState`. Passes the same domain and query as the original session.

**Example:**
```bash
eurekaclaw resume abc12345
```

---

### `skills` — List available skills

```bash
eurekaclaw skills
```

Prints a Rich panel listing all skills in the skill bank with:
- Skill name
- Tags
- Description
- Source (`seed`, `distilled`, or `manual`)

---

### `eval-session` — Evaluate a completed session

```bash
eurekaclaw eval-session <session_id>
```

**Arguments:**
- `session_id` — Session ID from a previous run (found in run directory name)

Prints an evaluation report with proof quality metrics.

---

### `install-skills` — Install seed skills

```bash
eurekaclaw install-skills [--force]
```

**Options:**

| Option | Description |
|---|---|
| `--force`, `-f` | Overwrite existing skills in `~/.eurekaclaw/skills/` |

Copies bundled seed skills from the package to `~/.eurekaclaw/skills/`.

---

### `ui` — Launch the browser UI

```bash
eurekaclaw ui [OPTIONS]
```

**Options:**

| Option | Default | Description |
|---|---|---|
| `--host` | `127.0.0.1` | Interface to bind to |
| `--port` | `8080` | Port to listen on |
| `--open-browser` / `--no-open-browser` | False | Auto-open browser on start |

**Example:**
```bash
eurekaclaw ui --open-browser
```

---

## Output Artifacts

All three research commands (`prove`, `explore`, `from-papers`) write artifacts to `<output>/<session_id>/`:

```
<output>/<session_id>/
├── paper.tex              LaTeX source
├── paper.pdf              Compiled PDF (requires pdflatex + bibtex)
├── references.bib         Bibliography in BibTeX format
├── theory_state.json      Full proof state (lemmas, proofs, status)
├── research_brief.json    Planning state (directions, selected direction)
└── experiment_result.json Numerical validation results (if run)
```

Paused sessions also write a checkpoint to `~/.eurekaclaw/sessions/<session_id>/checkpoint.json`.

## Theory Review Gate

After the Theory Agent finishes and before the Writer runs, EurekaClaw displays a numbered proof sketch and asks for approval:

```
──────────────── Proof Sketch Review ────────────────
  L1  [✓] arm_pull_count_bound  verified
       For arm a with mean gap Δ_a ...
  L2  [~] regret_decomposition  low confidence
       Total regret decomposes as ...
  L3  [✓] main_theorem          verified
       UCB1 achieves O(√(KT log T)) regret ...
──────────────────────────────────────────────────────

Does this proof sketch look correct?
  y  — Proceed to writing
  n  — Flag the most logically problematic step
→
```

- **y / Enter** — proceed to the WriterAgent
- **n** — you are asked which step has the most critical logical gap (e.g. `L2` or the full lemma ID) and to describe the issue. The TheoryAgent re-runs once with your feedback injected into its task, then shows the updated sketch one more time.

The theory review gate is **always shown** regardless of `--gate` mode.

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success — paper generated |
| `1` | Runtime error (see console output) |
