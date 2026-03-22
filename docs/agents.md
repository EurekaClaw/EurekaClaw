# Agents

EurekaClaw has five specialized agents coordinated by the `MetaOrchestrator`. Each agent runs a tool-use loop with periodic context compression.

## BaseAgent

All agents inherit from `eurekaclaw/agents/base.py`:

**Key Methods:**

| Method | Description |
|---|---|
| `execute(task: Task) -> AgentResult` | Abstract. Run the agent on a task |
| `get_tool_names() -> list[str]` | Abstract. Return allowed tool names for this agent |
| `build_system_prompt(task: Task) -> str` | Combine role prompt + injected skills |
| `run_agent_loop(task, initial_user_message, max_turns, max_tokens)` | Tool-use loop with context compression |
| `_compress_history() -> str` | Summarize conversation with fast model every N turns |
| `_call_model(system, messages, tools, max_tokens)` | LLM call with exponential-backoff retry |

**Context Compression:** Every `CONTEXT_COMPRESS_AFTER_TURNS` turns (default 6), history longer than 12 messages is compressed to a single summary using the fast model. This bounds input token growth across long runs.

---

## SurveyAgent

**Role:** `SURVEY`
**File:** `eurekaclaw/agents/survey/agent.py`
**Max Turns:** `SURVEY_MAX_TURNS` (default 8)

**Purpose:** Search the literature and populate the KnowledgeBus with papers, open problems, and key mathematical objects.

**Tools:**
- `arxiv_search` — Find relevant papers on arXiv
- `semantic_scholar_search` — Search Semantic Scholar for citation counts and metadata
- `web_search` — Supplement with general web search
- `citation_manager` — Format and store references

**Inputs (from KnowledgeBus):**
- `ResearchBrief.domain`
- `ResearchBrief.query`
- `ResearchBrief.conjecture`

**Outputs:**
- Appends papers to `Bibliography` on the bus
- Writes to `ResearchBrief`:
  - `open_problems` — list of identified open problems
  - `key_mathematical_objects` — core concepts and structures

**Output JSON keys:** `papers`, `open_problems`, `key_mathematical_objects`, `research_frontier`, `insights`

---

## IdeationAgent

**Role:** `IDEATION`
**File:** `eurekaclaw/agents/ideation/agent.py`
**Max Turns:** 3

**Purpose:** Generate 5 novel research hypotheses from survey findings. Each direction is scored on `novelty_score`, `feasibility_score`, and `impact_score` (mapped internally to the `ResearchDirection` fields `novelty_score`, `soundness_score`, `transformative_score`).

Direction *selection* does **not** happen inside IdeationAgent. After IdeationAgent writes `ResearchBrief.directions`, the orchestrator's `direction_selection_gate` task invokes `DivergentConvergentPlanner.converge()` to pick the highest-scoring direction and set `ResearchBrief.selected_direction`.

**Inputs (from KnowledgeBus):**
- Survey findings (`ResearchBrief`)
- `Bibliography`

**Outputs:**
- `ResearchBrief.directions` — 5 `ResearchDirection` objects with composite scores

---

## TheoryAgent

**Role:** `THEORY`
**File:** `eurekaclaw/agents/theory/agent.py`
**Max Iterations:** `THEORY_MAX_ITERATIONS` (default 10)
**Inner Stage Max Turns:** `THEORY_STAGE_MAX_TURNS` (default 6)

**Purpose:** Prove the selected research direction via a 7-stage bottom-up proof pipeline.

**Tools:**
- `arxiv_search` — Look up lemmas and techniques from papers
- `wolfram_alpha` — Symbolic computation and bound verification
- `lean4_verify` — Formal proof verification in Lean4
- `execute_python` — Numerical checks and sanity tests

**Inputs (from KnowledgeBus):**
- `ResearchBrief.selected_direction`

**Outputs:**
- `TheoryState` with `status` = `proved` / `refuted` / `abandoned`

**7-Stage Inner Loop** (`inner_loop_yaml.py`):

| Stage | Class | Input | Output |
|---|---|---|---|
| 1 | `PaperReader` | `Bibliography` | `known_results[]` |
| 2 | `GapAnalyst` | known_results + conjecture | `research_gap` |
| 3 | `ProofArchitect` | research_gap + known_results | `proof_plan[]` (provenance-annotated) |
| 4 | `LemmaDeveloper` | proof_plan, open_goals | `proven_lemmas{}` |
| 5 | `Assembler` | proven_lemmas | `assembled_proof` |
| 6 | `TheoremCrystallizer` | assembled_proof | `formal_statement` |
| 7 | `ConsistencyChecker` | full TheoryState | consistency report |

**LemmaDeveloper inner loop** (per lemma):
```
for each open_goal:
    Prover → Verifier → (if failed) Refiner → repeat
    CounterexampleSearcher runs in parallel
    Stagnation detection: if same error N times → force Refiner
```

**Provenance system:** Each lemma in the proof plan is annotated as `known` (directly citable), `adapted` (needs modification), or `new` (must be fully proved). Only `adapted` and `new` lemmas enter the proof loop.

**Auto-verify:** Proofs with confidence ≥ `AUTO_VERIFY_CONFIDENCE` (default 0.95) are accepted without an LLM verifier call. The LLM Verifier itself uses a separate pass threshold `VERIFIER_PASS_CONFIDENCE` (default 0.90).

**ProofArchitect retry policy:** If the full provenance-annotated plan fails (e.g. the LLM returns a field as `null`), the architect retries with a simplified 3-lemma prompt (foundational → central bound → main result). Only if both attempts fail does it fall back to a single `main_result` goal.

**Outer iteration loop:** After the Assembler runs, `TheoremCrystallizer` + `ConsistencyChecker` iterate up to `theory_max_iterations` times. The `ConsistencyChecker` classifies every failure into one of three severity levels, and the retry path is chosen accordingly:

| Severity | Meaning | Retry path |
|---|---|---|
| `uncited` | Proof logic is sound but proved lemmas are not cited in the assembled text | Re-run `TheoremCrystallizer` inline, then immediately mark proof as `proved` and exit the outer loop — **no second ConsistencyChecker pass** |
| `major` | A specific lemma is incorrect or the logical link between two lemmas is broken | Re-run `LemmaDeveloper → Assembler → TheoremCrystallizer → ConsistencyChecker` (one attempt). If this also fails, escalate to `all_wrong` |
| `all_wrong` | Fundamental proof breakdown — wrong approach or multiple incorrect lemmas | Re-run from `ProofArchitect` (new proof plan) through the full pipeline |

If the LLM does not return a severity field, it is inferred heuristically: failures with only `uncited_lemmas` and no `issues` are classified as `uncited`; all others as `major`.

**Citation convention:** The Assembler is instructed to cite every proved lemma by its identifier in square brackets, e.g. `By [arm_pull_count_bound], ...`. The ConsistencyChecker verifies that all proved lemma IDs appear in the assembled proof and flags any that are missing.

**Knowledge Graph writes:** Lemma nodes and dependency edges are written to the Tier 3 KG whenever lemmas are proved, regardless of whether the final consistency check passes. This preserves the lemma-level graph even when the theorem statement crystallization fails.

---

## ExperimentAgent

**Role:** `EXPERIMENT`
**File:** `eurekaclaw/agents/experiment/agent.py`
**Max Turns:** 5

**Purpose:** Empirically validate theoretical bounds via numerical experiments, particularly for low-confidence lemmas.

**Tools:**
- `execute_python` — Run numerical simulations
- `wolfram_alpha` — Symbolic bound checking
- Domain-specific tools (e.g., `run_bandit_experiment` for MAB domain)

**Auto-skip logic:** The agent checks `TheoryState.formal_statement` for quantitative signals before running:
- **Run experiments:** `O(`, `\Omega(`, inequality operators, `sample complexity`, `regret`, convergence/generalization terms
- **Skip:** `\exists`, existence quantifiers, pure algebraic/combinatorial structures

**Low-confidence lemma testing:**
- Separates `proven_lemmas` into `verified` and `low_confidence` groups
- For each low-confidence lemma: samples random instances, checks the conclusion holds, computes `violation_rate`
- Lemmas with `violation_rate > 1%` are flagged as `numerically_suspect`

**Inputs (from KnowledgeBus):**
- `TheoryState` (proven lemmas, formal statement)

**Outputs:**
- `ExperimentResult` on KnowledgeBus with `alignment_score` and per-lemma check results

---

## WriterAgent

**Role:** `WRITER`
**File:** `eurekaclaw/agents/writer/agent.py`
**Max Turns:** `WRITER_MAX_TURNS` (default 4)

**Purpose:** Produce a complete academic paper in LaTeX (or Markdown) from all pipeline artifacts.

**Tools:**
- `citation_manager` — Format bibliography entries and generate consistent cite keys

**Inputs (from KnowledgeBus):**
- `ResearchBrief` (domain, conjecture, selected direction)
- `TheoryState` (all proofs, lemmas, formal statement)
- `Bibliography` (papers with exact cite keys)
- `ExperimentResult` (if available)

**Outputs:**
- `latex_paper` string stored in `ResearchOutput`

**LaTeX features:**
- Full `LATEX_PREAMBLE` with 13 theorem environments: `theorem`, `lemma`, `corollary`, `definition`, `proposition`, `assumption`, `conjecture`, `claim`, `example`, `fact`, `observation`, `maintheorem`, `remark`
- Common math macros: `\R`, `\N`, `\Z`, `\E`, `\Prob`, `\softmax`, `\Att`, `\argmax`, `\argmin`, `\norm`, `\abs`, `\inner`

**`_extract_latex` normalization pipeline:**
1. Strip preamble / `\begin{document}` / `\end{document}` wrappers
2. Normalize environment names (`\begin{Proof}` → `\begin{proof}`, `rem` → `remark`, `prop` → `proposition`, etc.)
3. Convert Markdown headings to LaTeX section commands
4. Remove `tikzpicture` environments and empty `figure` environments
5. Fix syntax errors (`\begin lemma}` → `\begin{lemma}`, `\begin{flushright` → `\begin{flushright}`)
6. Replace `\endproof` with `\end{proof}`
7. Remove manual QED boxes (`\begin{flushright}$\square$\end{flushright}`)
8. Strip `\bibliographystyle` and `\bibliography` lines from the body
9. Close unclosed environments (two-pass: remove orphaned `\end{X}`, then append missing ones)

**Proof style enforcement** (`ENFORCE_PROOF_STYLE=true`):
- No skip words ("clearly", "trivially", "by standard arguments") without immediate justification
- Every inequality must name the lemma or theorem it uses
- Each lemma proof opens with informal intuition
- Low-confidence lemmas tagged with `\textcolor{orange}{[Unverified step]}`
- Limitations section explains all unverified steps

**Citation consistency:** The writer prompt includes `\cite{key}` for each reference using the same key generation algorithm as `_generate_bibtex` in `main.py`.
