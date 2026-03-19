# Research Tools

Tools are callable functions exposed to agents via the Anthropic tool-use API. Each tool has a name, description, input schema, and async `call()` method.

## Tool Architecture

```python
class BaseTool(ABC):
    name: ClassVar[str]
    description: ClassVar[str]

    def input_schema(self) -> dict: ...    # JSON Schema for inputs
    async def call(self, **kwargs) -> str: ...   # returns JSON string
    def to_anthropic_tool_def(self) -> dict: ... # format for API
```

Tools are stored in a `ToolRegistry`. The default registry (`build_default_registry()`) includes the 7 built-in tools. Domain plugins can add extra tools via `DomainPlugin.register_tools()`.

---

## Built-in Tools

### `arxiv_search`

**File:** `eurekaclaw/tools/arxiv.py`

**Purpose:** Search arXiv for academic papers.

**Inputs:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `query` | string | required | Search query |
| `max_results` | integer | 8 | Number of results (capped at `ARXIV_MAX_RESULTS`) |
| `sort_by` | string | `relevance` | Sort order: `relevance`, `lastUpdatedDate`, `submittedDate` |

**Output:** JSON array of:
```json
[{
  "arxiv_id": "2301.00774",
  "title": "...",
  "authors": ["Author A", "Author B"],
  "abstract": "...",
  "published": "2023-01-02",
  "pdf_url": "https://arxiv.org/pdf/2301.00774",
  "categories": ["cs.LG", "stat.ML"]
}]
```

**External dependency:** `arxiv` Python package

---

### `semantic_scholar_search`

**File:** `eurekaclaw/tools/semantic_scholar.py`

**Purpose:** Search Semantic Scholar for papers with citation counts and venue information.

**Inputs:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `query` | string | required | Search query |
| `limit` | integer | 10 | Number of results |
| `year_range` | string | `""` | Optional year filter (e.g., `"2020-2024"`) |

**Output:** JSON array of:
```json
[{
  "s2_id": "...",
  "title": "...",
  "authors": ["..."],
  "year": 2023,
  "abstract": "...",
  "citation_count": 42,
  "venue": "NeurIPS",
  "arxiv_id": "2301.00774",
  "url": "https://www.semanticscholar.org/paper/..."
}]
```

**External dependency:** Semantic Scholar Graph API v1. Set `S2_API_KEY` for higher rate limits.

---

### `web_search`

**File:** `eurekaclaw/tools/web_search.py`

**Purpose:** General web search for supplementary research context.

**Inputs:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `query` | string | required | Search query |
| `count` | integer | 5 | Number of results |

**Output:** JSON array of:
```json
[{"title": "...", "url": "...", "description": "..."}]
```

**Backends:** Brave Search (preferred, requires `BRAVE_SEARCH_API_KEY`) or SerpAPI (fallback, requires `SERPAPI_KEY`).

---

### `lean4_verify`

**File:** `eurekaclaw/tools/lean4.py`

**Purpose:** Formally verify a proof using the Lean4 theorem prover.

**Inputs:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `proof_code` | string | required | Lean4 proof code |
| `theorem_name` | string | `""` | Optional theorem name for reporting |

**Output:**
```json
{
  "verified": true,
  "theorem": "my_theorem",
  "message": "Proof checked successfully"
}
```
Or on failure:
```json
{
  "verified": false,
  "lean4_output": "error: ...",
  "message": "Verification failed"
}
```

**External dependency:** Lean4 binary at `LEAN4_BIN` (default: `lean`). Imports Mathlib and Aesop. Timeout: 120 seconds. Max heartbeats: 400,000.

---

### `execute_python`

**File:** `eurekaclaw/tools/code_exec.py`

**Purpose:** Execute Python code in a sandboxed subprocess for numerical experiments and sanity checks.

**Inputs:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `code` | string | required | Python code to execute |
| `requirements` | list[string] | `[]` | Extra packages to install before running |

**Output:**
```json
{"output": "stdout + stderr from execution"}
```
Or on error:
```json
{"error": "exception message"}
```

**Sandbox:** Subprocess with 30-second timeout. Set `USE_DOCKER_SANDBOX=true` to run in Docker instead. Package installation uses `uv pip` (falls back to `pip`).

---

### `wolfram_alpha`

**File:** `eurekaclaw/tools/wolfram.py`

**Purpose:** Symbolic computation, formula simplification, and bound verification.

**Inputs:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `query` | string | required | Natural language or symbolic query |

**Output:** JSON array of Wolfram Alpha pods:
```json
[{"title": "Result", "result": "..."}]
```

**External dependency:** Wolfram Alpha API v2. Requires `WOLFRAM_APP_ID`.

---

### `citation_manager`

**File:** `eurekaclaw/tools/citation.py`

**Purpose:** Generate BibTeX entries and format citation keys consistently.

**Actions:**

| Action | Description |
|---|---|
| `generate_bibtex` | Generate a BibTeX entry from paper metadata |
| `format_cite` | Return the `\cite{key}` command for a paper |
| `list_entries` | List all citation entries in the current session |

**Output:** JSON with `cite_key` and `bibtex` strings.

**Note:** Uses the same key-generation algorithm as `_generate_bibtex` in `main.py` to ensure consistency between the writer's `\cite{}` commands and the `.bib` file.

---

## ToolRegistry

**File:** `eurekaclaw/tools/registry.py`

```python
class ToolRegistry:
    def register(tool: BaseTool) -> None
    def get(name: str) -> BaseTool | None
    def all_definitions() -> list[dict]         # all tools as Anthropic defs
    def definitions_for(names: list[str]) -> list[dict]  # subset
    async def call(name: str, inputs: dict) -> str
    def __contains__(name: str) -> bool
    def __len__() -> int

def build_default_registry() -> ToolRegistry   # create with all 7 built-in tools
```

---

## Domain-Specific Tools

Domain plugins can register additional tools via `DomainPlugin.register_tools(registry)`.

### MAB Domain: `run_bandit_experiment`

**File:** `eurekaclaw/domains/mab/tools/bandit_tool.py`

**Purpose:** Run multi-armed bandit simulations to empirically validate regret bounds.

**Inputs:**

| Parameter | Type | Description |
|---|---|---|
| `algorithm` | string | `ucb1` or `thompson_sampling` |
| `n_arms` | integer | Number of arms K |
| `n_rounds` | integer | Time horizon T |
| `distribution` | string | `gaussian` or `bernoulli` |
| `n_trials` | integer | Monte Carlo trials for averaging |

**Output:** JSON with empirical regret, per-arm stats, and comparison against theoretical bound.

**Supporting modules:**
- `domains/mab/envs/stochastic.py` — `GaussianBandit`, `BernoulliBandit`
- `domains/mab/envs/runner.py` — `run_experiment()`, `sweep_T()`
- `domains/mab/tools/concentration.py` — Hoeffding, Bernstein, sub-Gaussian bounds
- `domains/mab/tools/regret.py` — Regret decomposition, Lai-Robbins lower bound
- `domains/mab/tools/information.py` — KL(Bernoulli), KL(Gaussian), Fano's inequality
