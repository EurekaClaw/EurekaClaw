# Memory System

EurekaClaw uses a **four-tier memory system** managed by `MemoryManager`.

```
eurekaclaw/memory/
├── manager.py          MemoryManager (main interface)
├── episodic.py         EpisodicMemory (in-RAM ring buffer)
├── persistent.py       PersistentMemory (cross-run JSON file)
└── knowledge_graph.py  KnowledgeGraph (theorem dependency network)

eurekaclaw/learning/
└── memory_extractor.py  SessionMemoryExtractor (Tier 4: domain markdown insights)
```

Storage layout under `~/.eurekaclaw/` (configurable via `EUREKACLAW_DIR`):

```
~/.eurekaclaw/
├── memory/
│   ├── persistent.json        ← Tier 2: cross-run key-value store
│   └── knowledge_graph.json   ← Tier 3: theorem dependency graph
├── memories/
│   └── <domain>/
│       ├── YYYYMMDD_<slug>.md ← Tier 4: per-domain insight files
│       └── _index.json        ← Tier 4: index for semantic search
└── skills/                    ← skill files updated by ContinualLearningLoop
```

---

## Tier 1 — Episodic Memory (session-scoped)

**File:** `eurekaclaw/memory/episodic.py`

In-RAM ring buffer (max 500 entries). Records agent events during the current session. Lost when the process ends — never persisted to disk.

```python
def log_event(
    agent_role: str,
    content: str,
    metadata: dict | None = None
) -> EpisodicEntry
```
Log a structured event (tool call, result, decision, error) from an agent. Called automatically by `BaseAgent` after each tool call.

```python
def recent_events(
    n: int = 20,
    agent_role: str | None = None
) -> list[EpisodicEntry]
```
Return the N most recent events, optionally filtered by agent role.

---

## Tier 2 — Persistent Memory (cross-run key-value)

**File:** `eurekaclaw/memory/persistent.py`
**Storage:** `~/.eurekaclaw/memory/persistent.json`

Stores arbitrary JSON-serializable key-value records that survive across sessions.

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

---

## Tier 3 — Knowledge Graph (theorem dependency network)

**File:** `eurekaclaw/memory/knowledge_graph.py`
**Storage:** `~/.eurekaclaw/memory/knowledge_graph.json`

A directed graph that tracks proven theorems and their dependencies across all sessions. Exportable to networkx for analysis.

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
Record a dependency between two theorems. Relation types: `"uses"`, `"generalizes"`, `"specializes"`, `"contradicts"`.

```python
def find_related_theorems(node_id: str, depth: int = 2) -> list[KnowledgeNode]
```
BFS traversal — returns theorems within `depth` hops of `node_id`.

---

## Tier 4 — Domain Memories (cross-session markdown insights)

**File:** `eurekaclaw/learning/memory_extractor.py`
**Storage:** `~/.eurekaclaw/memories/<domain>/YYYYMMDD_<slug>.md`

The primary mechanism for cross-session learning. After each session, `SessionMemoryExtractor` uses the fast model to analyse `TheoryState` and extract structured insights in four categories:

| Category | What gets saved |
|---|---|
| `domain_knowledge` | New facts, lemmas, theorems discovered or confirmed |
| `proof_strategy` | Proof techniques that worked (or failed) in this domain |
| `open_problems` | Conjectures raised but not resolved |
| `pitfalls` | Approaches that looked promising but failed, with root cause |

Only entries with `confidence >= 0.5` are saved. A sha256 fingerprint index (`_index.json`) deduplicates exact matches. Near-duplicates (keyword overlap > 40%) are checked by the LLM and merged when redundant.

### Injection into future sessions

At the start of each session, `BaseAgent.build_system_prompt()` calls:

```python
memory.load_for_injection(domain, k=4, query=task_description)
```

This selects the 4 most **relevant** high-confidence `.md` files for the domain using cosine similarity against `query`, strips frontmatter, and injects the content into the system prompt as `<memories>...</memories>`.

**Semantic ranking:** each memory file's embedding is stored in `_index.json` at write time (via `eurekaclaw/memory/embedding_utils.py`). At retrieval time, candidates are scored by `cosine_similarity(query_embedding, memory_embedding)` and the top-k are returned. Falls back to recency ordering if embeddings are unavailable.

---

## Lifecycle

```
During session
  BaseAgent.execute() → memory.log_event() → Tier 1 (RAM only)

After session (ContinualLearningLoop.post_run())
  SessionMemoryExtractor.extract_and_save()
    → LLM analysis of TheoryState (proven lemmas + failed attempts)
    → write ~/.eurekaclaw/memories/<domain>/YYYYMMDD_<slug>.md  [Tier 4]

  ToolPatternExtractor.extract_and_save()
    → analyse tool-call patterns → generate new Skill files

  SkillRegistry.update_stats()
    → EMA α=0.3 update on success_rate for all injected skills

Next session startup
  MetaOrchestrator → MemoryManager.load_for_injection(domain)
    → top-4 Tier 4 files → injected into agent system prompts
```

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
    tags: list[str] = []
    created_at: datetime
```

---

## Storage Locations

| Tier | Storage | Location |
|---|---|---|
| Tier 1: Episodic | RAM (process lifetime) | — |
| Tier 2: Persistent | JSON file | `~/.eurekaclaw/memory/persistent.json` |
| Tier 3: Knowledge graph | JSON file | `~/.eurekaclaw/memory/knowledge_graph.json` |
| Tier 4: Domain insights | Markdown files | `~/.eurekaclaw/memories/<domain>/` |
| Run artifacts | Per-session JSON | `~/.eurekaclaw/runs/<session_id>/` |
