# Python API

## EurekaSession

**File:** `eurekaclaw/main.py`

The main entry point for running research programmatically.

```python
from eurekaclaw.main import EurekaSession, run_research, save_artifacts

session = EurekaSession()
```

### Constructor

```python
class EurekaSession:
    def __init__(self, session_id: str | None = None) -> None
```

- `session_id` — Optional. Auto-generated UUID if not provided.
- Creates a `KnowledgeBus` and lazily initializes `MetaOrchestrator`.

### Methods

```python
async def run(self, input_spec: InputSpec) -> ResearchOutput
```
Run a full research session from an `InputSpec`. This is the lowest-level async entry point used internally.

```python
async def run_detailed(self, conjecture: str, domain: str = "") -> ResearchOutput
```
**Level 1:** Prove a specific conjecture.

```python
async def run_from_papers(self, paper_ids: list[str], domain: str) -> ResearchOutput
```
**Level 2:** Find gaps and generate hypotheses from reference papers.

```python
async def run_exploration(self, domain: str, query: str = "") -> ResearchOutput
```
**Level 3:** Open exploration of a research domain.

### Properties

```python
@property
def orchestrator(self) -> MetaOrchestrator
```
Lazy-initialized orchestrator. Auto-detects domain plugin from `InputSpec.domain`.

---

## Convenience Functions

```python
def run_research(conjecture: str, domain: str = "") -> ResearchOutput
```
Synchronous entry point (wraps `asyncio.run()`). Runs Level 1 prove pipeline.

```python
def save_artifacts(result: ResearchOutput, out_dir: str | Path) -> Path
```
Write all pipeline artifacts to disk and compile the PDF.

**Writes:**
- `paper.tex` — LaTeX source
- `references.bib` — BibTeX bibliography
- `theory_state.json` — Full proof state
- `research_brief.json` — Planning state
- `experiment_result.json` — Numerical results (if available)

**LaTeX compile sequence:**
1. `pdflatex paper.tex` (pass 1 — generate `.aux`)
2. `bibtex paper` (only if `references.bib` exists and is non-empty)
3. `pdflatex paper.tex` (pass 2 — resolve citations)
4. `pdflatex paper.tex` (pass 3 — finalize)

**Citation validation:** Before compiling, `_fix_missing_citations()` removes any `\cite{}` keys that have no matching entry in `references.bib`, preventing `?` symbols in the output PDF.

**Returns:** `Path` to the output directory.

---

## KnowledgeBus

**File:** `eurekaclaw/knowledge_bus/bus.py`

Central in-memory artifact store shared by all agents in a session. All data flows through the bus — no agent holds private state between turns.

```python
class KnowledgeBus:
    def __init__(self, session_id: str) -> None
```

### Typed Artifact Access

```python
def put_research_brief(brief: ResearchBrief) -> None
def get_research_brief() -> ResearchBrief | None

def put_theory_state(state: TheoryState) -> None
def get_theory_state() -> TheoryState | None

def put_experiment_result(result: ExperimentResult) -> None
def get_experiment_result() -> ExperimentResult | None

def put_bibliography(bib: Bibliography) -> None
def get_bibliography() -> Bibliography | None
def append_citations(papers: list[Paper]) -> None

def put_pipeline(pipeline: TaskPipeline) -> None
def get_pipeline() -> TaskPipeline | None
```

### Generic Key-Value Store

```python
def put(key: str, value: Any) -> None
def get(key: str, default: Any = None) -> Any
```

For arbitrary data shared between agents (e.g., `numerically_suspect` lemma IDs).

### Reactive Subscriptions

```python
def subscribe(artifact_type: str, callback: Callable) -> None
```
Register a callback triggered whenever an artifact of `artifact_type` is updated on the bus.

### Persistence

```python
def persist(session_dir: Path) -> None
```
Serialize all artifacts to JSON files in `session_dir`.

```python
@classmethod
def load(session_id: str, session_dir: Path) -> KnowledgeBus
```
Reconstruct a bus from a previously persisted session directory.

---

## InputSpec

**File:** `eurekaclaw/types/tasks.py`

Specifies what to research.

```python
class InputSpec(BaseModel):
    mode: Literal["detailed", "reference", "exploration"]
    conjecture: str | None = None     # Level 1: specific conjecture
    paper_ids: list[str] = []         # Level 2: reference paper IDs
    paper_texts: list[str] = []       # Level 2: raw paper texts (alternative)
    domain: str = ""                  # research domain string
    query: str = ""                   # Level 3: research question
    additional_context: str = ""      # extra context for agents
    selected_skills: list[str] = []   # manually select skill names to inject
```

---

## ResearchOutput

**File:** `eurekaclaw/types/tasks.py`

The result of a full research session.

```python
class ResearchOutput(BaseModel):
    session_id: str
    latex_paper: str = ""           # full LaTeX source
    pdf_path: str | None = None     # path to compiled PDF (if successful)
    theory_state_json: str = ""     # TheoryState serialized as JSON
    experiment_result_json: str = "" # ExperimentResult serialized as JSON
    research_brief_json: str = ""   # ResearchBrief serialized as JSON
    bibliography_json: str = ""     # Bibliography serialized as JSON
    eval_report_json: str = ""      # evaluation report (if run)
    skills_distilled: list[str] = [] # names of new skills written this session
    completed_at: datetime
```

---

## Data Models Quick Reference

All models are Pydantic `BaseModel` instances. See [architecture.md](architecture.md) for field-level diagrams.

| Model | File | Description |
|---|---|---|
| `InputSpec` | `types/tasks.py` | Research input specification |
| `ResearchOutput` | `types/tasks.py` | Full session result |
| `Task` | `types/tasks.py` | Single pipeline task |
| `TaskPipeline` | `types/tasks.py` | Ordered task sequence |
| `ResearchBrief` | `types/artifacts.py` | Survey findings + selected direction |
| `ResearchDirection` | `types/artifacts.py` | Scored research hypothesis |
| `TheoryState` | `types/artifacts.py` | Proof state machine |
| `LemmaNode` | `types/artifacts.py` | Node in the lemma dependency DAG |
| `ProofRecord` | `types/artifacts.py` | Completed proof for one lemma |
| `ProofPlan` | `types/artifacts.py` | Planned lemma with provenance |
| `KnownResult` | `types/artifacts.py` | Result extracted from a paper |
| `FailedAttempt` | `types/artifacts.py` | Failed proof attempt record |
| `Counterexample` | `types/artifacts.py` | Discovered counterexample |
| `ExperimentResult` | `types/artifacts.py` | Numerical validation results |
| `NumericalBound` | `types/artifacts.py` | Theoretical vs empirical bound comparison |
| `Bibliography` | `types/artifacts.py` | Collection of papers + BibTeX |
| `Paper` | `types/artifacts.py` | Single paper metadata |
| `AgentResult` | `types/agents.py` | Result from one agent task |
| `SkillRecord` | `types/skills.py` | A skill with metadata |
| `EpisodicEntry` | `types/memory.py` | Session-scoped memory event |
| `CrossRunRecord` | `types/memory.py` | Persistent cross-run memory record |
| `KnowledgeNode` | `types/memory.py` | Theorem in the knowledge graph |

---

## Example: Run a Proof Session

```python
import asyncio
from eurekaclaw.main import EurekaSession, save_artifacts

async def main():
    session = EurekaSession()
    result = await session.run_detailed(
        conjecture="The sample complexity of transformers is O(L·d·log(d)/ε²)",
        domain="machine learning theory",
    )
    out = save_artifacts(result, "./results")
    print(f"Paper saved to: {out}")

asyncio.run(main())
```

## Example: Load and Re-generate Artifacts

```python
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import TheoryState, ResearchBrief
from eurekaclaw.main import save_artifacts, ResearchOutput
from pathlib import Path
import json

# Load existing session artifacts
session_dir = Path("results/my-session-id")
theory_state = TheoryState.model_validate_json((session_dir / "theory_state.json").read_text())
research_brief = ResearchBrief.model_validate_json((session_dir / "research_brief.json").read_text())

# Re-run writer agent
from eurekaclaw.agents.writer.agent import WriterAgent
from eurekaclaw.knowledge_bus.bus import KnowledgeBus

bus = KnowledgeBus(theory_state.session_id)
bus.put_theory_state(theory_state)
bus.put_research_brief(research_brief)
# ... run writer agent and save
```
