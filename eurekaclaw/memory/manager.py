"""MemoryManager — unified interface to all three memory tiers."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.memory.episodic import EpisodicMemory
from eurekaclaw.memory.knowledge_graph import KnowledgeGraph
from eurekaclaw.memory.persistent import PersistentMemory
from eurekaclaw.types.memory import CrossRunRecord, EpisodicEntry, KnowledgeNode


class MemoryManager:
    """Unified read/write interface across session, cross-run, and graph memory."""

    def __init__(self, session_id: str, memory_dir: Path | None = None) -> None:
        memory_dir = memory_dir or settings.memory_dir
        memory_dir.mkdir(parents=True, exist_ok=True)
        self.session = EpisodicMemory(session_id)
        self.persistent = PersistentMemory(memory_dir)
        self.graph = KnowledgeGraph(memory_dir)

    # --- Episodic (session-scoped) ----------------------------------------

    def log_event(self, agent_role: str, content: str, metadata: dict[str, Any] | None = None) -> EpisodicEntry:
        return self.session.record(agent_role, content, metadata)

    def recent_events(self, n: int = 20, agent_role: str | None = None) -> list[EpisodicEntry]:
        return self.session.get_recent(n, agent_role)

    # --- Persistent (cross-run) -------------------------------------------

    def remember(self, key: str, value: Any, tags: list[str] | None = None, source_session: str = "") -> None:
        self.persistent.put(key, value, tags=tags, source_session=source_session)

    def recall(self, key: str) -> Any | None:
        return self.persistent.get(key)

    def recall_by_tag(self, tag: str) -> list[CrossRunRecord]:
        return self.persistent.get_by_tag(tag)

    # --- Knowledge graph --------------------------------------------------

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
