"""MemoryManager — unified interface to all memory tiers.

Four tiers:
  1. Episodic   — in-session ring buffer (agents log events during a run)
  2. Persistent — cross-run key-value JSON store (structured facts)
  3. KnowledgeGraph — theorem dependency graph (networkx)
  4. DomainMemories — per-domain markdown insights extracted after each session
                      (used for prompt injection in future runs)

All tiers live under ~/.eurekaclaw/:
  memory/persistent.json       ← tier 2
  memory/knowledge_graph.json  ← tier 3
  memories/<domain>/<date>.md  ← tier 4  (written by SessionMemoryExtractor)
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.memory.episodic import EpisodicMemory
from eurekaclaw.memory.knowledge_graph import KnowledgeGraph
from eurekaclaw.memory.persistent import PersistentMemory
from eurekaclaw.types.memory import CrossRunRecord, EpisodicEntry, KnowledgeNode


class MemoryManager:
    """Unified read/write interface across all memory tiers."""

    def __init__(self, session_id: str, memory_dir: Path | None = None) -> None:
        memory_dir = memory_dir or settings.memory_dir
        memory_dir.mkdir(parents=True, exist_ok=True)
        self.session = EpisodicMemory(session_id)
        self.persistent = PersistentMemory(memory_dir)
        self.graph = KnowledgeGraph(memory_dir)

    # --- Tier 1: Episodic (session-scoped) --------------------------------

    def log_event(self, agent_role: str, content: str, metadata: dict[str, Any] | None = None) -> EpisodicEntry:
        return self.session.record(agent_role, content, metadata)

    def recent_events(self, n: int = 20, agent_role: str | None = None) -> list[EpisodicEntry]:
        return self.session.get_recent(n, agent_role)

    # --- Tier 2: Persistent key-value (cross-run) -------------------------

    def remember(self, key: str, value: Any, tags: list[str] | None = None, source_session: str = "") -> None:
        self.persistent.put(key, value, tags=tags, source_session=source_session)

    def recall(self, key: str) -> Any | None:
        return self.persistent.get(key)

    def recall_by_tag(self, tag: str) -> list[CrossRunRecord]:
        return self.persistent.get_by_tag(tag)

    # --- Tier 3: Knowledge graph ------------------------------------------

    def add_theorem(
        self,
        theorem_name: str,
        formal_statement: str,
        domain: str = "",
        session_id: str = "",
        tags: list[str] | None = None,
    ) -> KnowledgeNode:
        return self.graph.add_theorem(theorem_name, formal_statement, domain, session_id, tags)

    def link_theorems(self, from_id: str, to_id: str, relation: str = "uses") -> None:
        self.graph.add_edge(from_id, to_id, relation)

    def find_related_theorems(self, node_id: str, depth: int = 2) -> list[KnowledgeNode]:
        return self.graph.find_related(node_id, depth)

    # --- Tier 4: Domain markdown memories ---------------------------------

    def load_for_injection(self, domain: str, k: int = 4) -> str:
        """Load top-k domain memories as a formatted block for prompt injection.

        Delegates to SessionMemoryExtractor which manages the markdown files
        at ~/.eurekaclaw/memories/<domain>/. Returns empty string if none exist.
        This is the canonical way for injectors/agents to access cross-session
        memories — no code outside memory/ should import SessionMemoryExtractor.
        """
        try:
            from eurekaclaw.learning.memory_extractor import SessionMemoryExtractor
            return SessionMemoryExtractor().load_for_injection(domain, k=k)
        except Exception:
            return ""
