# Memory System

EurekaClaw uses a three-tier memory system managed by `MemoryManager`.

```
eurekaclaw/memory/
├── manager.py       MemoryManager (main interface)
├── episodic.py      EpisodicMemory (in-RAM ring buffer)
├── persistent.py    PersistentMemory (cross-run JSON file)
└── graph.py         KnowledgeGraph (theorem dependency network)
```

---

## MemoryManager

**File:** `eurekaclaw/memory/manager.py`

The single interface for all memory operations. Created once per session by `MetaOrchestrator`.

```python
class MemoryManager:
    def __init__(self, session_id: str, memory_dir: Path | None = None) -> None
```

### Episodic Memory (session-scoped)

Records events within the current session. Stored in RAM only; lost when the process ends.

```python
def log_event(
    agent_role: str,
    content: str,
    metadata: dict | None = None
) -> EpisodicEntry
```
Log a structured event (tool call, result, decision, error) from an agent.

```python
def recent_events(
    n: int = 20,
    agent_role: str | None = None
) -> list[EpisodicEntry]
```
Return the N most recent events, optionally filtered by agent role.

### Persistent Memory (cross-run)

Stores key-value records that survive across sessions. Backed by a JSON file at `EUREKACLAW_DIR/memory/persistent.json`.

```python
def remember(
    key: str,
    value: Any,
    tags: list[str] | None = None,
    source_session: str = ""
) -> None
```
Save or overwrite a cross-run record. `key` is typically namespaced (e.g., `"theory.failed_strategies.concentration_bounds"`).

```python
def recall(key: str) -> Any | None
```
Retrieve a value by exact key. Returns `None` if not found.

```python
def recall_by_tag(tag: str) -> list[CrossRunRecord]
```
Return all records that include the given tag.

### Knowledge Graph

Tracks proven theorems and their dependencies across sessions. Backed by `EUREKACLAW_DIR/memory/knowledge_graph.json`.

```python
def add_theorem(
    theorem_name: str,
    formal_statement: str,
    domain: str = "",
    session_id: str = "",
    tags: list[str] | None = None
) -> KnowledgeNode
```
Register a newly proved theorem.

```python
def link_theorems(from_id: str, to_id: str, relation: str = "uses") -> None
```
Record a dependency between two theorems (e.g., theorem A uses lemma B).

```python
def find_related_theorems(node_id: str, depth: int = 2) -> list[KnowledgeNode]
```
Return theorems within `depth` hops of `node_id` in the dependency graph.

---

## Data Models

**File:** `eurekaclaw/types/memory.py`

### EpisodicEntry

```python
class EpisodicEntry(BaseModel):
    entry_id: str
    session_id: str
    agent_role: str      # "survey", "theory", "writer", etc.
    content: str         # free-text event description
    metadata: dict = {}  # structured data (tool name, paper_id, etc.)
    timestamp: datetime
```

### CrossRunRecord

```python
class CrossRunRecord(BaseModel):
    record_id: str
    key: str             # namespaced key, e.g. "theory.failed_strategies.sample_complexity"
    value: Any           # arbitrary JSON-serializable value
    tags: list[str] = []
    source_session: str = ""
    created_at: datetime
    updated_at: datetime
```

### KnowledgeNode

```python
class KnowledgeNode(BaseModel):
    node_id: str
    theorem_name: str
    formal_statement: str
    domain: str = ""
    session_id: str = ""  # session that proved this theorem
    related_to: list[str] = []  # node_ids of related/dependent theorems
    tags: list[str] = []
    created_at: datetime
```

---

## Current Integration Status

The three-tier memory infrastructure is fully implemented, but **agent integration is a work in progress**:

- **Episodic memory** — logged by `MetaOrchestrator` at each pipeline stage
- **Knowledge graph** — `add_theorem()` is called when `TheoryState.status == "proved"`
- **Persistent memory** — infrastructure exists but `remember()` / `recall()` are not yet called from individual agents (planned for a future update)

Cross-session learning currently operates through the [Skills](skills.md) system (`ContinualLearningLoop`), which distills successful proof strategies into reusable skill files.

---

## Storage Locations

| Tier | Storage | Location |
|---|---|---|
| Episodic | RAM (process lifetime) | — |
| Persistent | JSON file | `~/.eurekaclaw/memory/persistent.json` |
| Knowledge graph | JSON file | `~/.eurekaclaw/memory/knowledge_graph.json` |
| Run artifacts | Per-session JSON | `~/.eurekaclaw/runs/<session_id>/` |
