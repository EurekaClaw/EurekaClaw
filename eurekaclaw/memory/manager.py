"""MemoryManager — unified interface to all memory tiers.

Four tiers:
  1. Episodic   — in-session ring buffer (agents log events during a run)
  2. Persistent — cross-run key-value JSON store (structured facts)
  3. KnowledgeGraph — theorem dependency graph (networkx)
  4. DomainMemories — per-domain markdown insights extracted after each session
                      (used for prompt injection in future runs)

All tiers live under ~/.eurekaclaw/:
  memory/persistent.json            ← tier 2
  memory/knowledge_graph.json       ← tier 3
  memories/<domain>/<date>.md       ← tier 4 (written by SessionMemoryExtractor)
  memories/<domain>/_index.json     ← tier 4 (index for semantic search)
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.memory.episodic import EpisodicMemory
from eurekaclaw.memory.knowledge_graph import KnowledgeGraph
from eurekaclaw.memory.persistent import PersistentMemory
from eurekaclaw.memory.embedding_utils import get_embedding, cosine_similarity # New imports
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

    def retrieve_relevant_theorems(
        self,
        query: str,
        domain: str = "",
        limit: int = 5,
    ) -> list[KnowledgeNode]:
        """Return the most relevant theorems/lemmas from the knowledge graph.

        Uses a lightweight lexical overlap score over theorem name + statement.
        This keeps retrieval deterministic and dependency-free while making the
        graph actually useful during proof planning.
        """
        import re

        def tokenize(text: str) -> set[str]:
            return {
                token
                for token in re.findall(r"[A-Za-z][A-Za-z0-9_]{2,}", text.lower())
                if token not in {"theorem", "lemma", "proof", "result", "using", "show", "bound"}
            }

        query_tokens = tokenize(query)
        if not query_tokens and not domain:
            return []

        candidates = self.graph.search_by_domain(domain) if domain else self.graph.all_nodes()
        if not candidates:
            candidates = self.graph.all_nodes()

        scored: list[tuple[int, KnowledgeNode]] = []
        domain_lower = domain.lower()
        for node in candidates:
            haystack = f"{node.theorem_name}\n{node.formal_statement}"
            node_tokens = tokenize(haystack)
            overlap = len(query_tokens & node_tokens)
            if domain_lower and domain_lower in node.domain.lower():
                overlap += 2
            if overlap > 0:
                scored.append((overlap, node))

        scored.sort(key=lambda item: (-item[0], item[1].created_at), reverse=False)
        return [node for _score, node in scored[:limit]]

    # --- Tier 4: Domain markdown memories ---------------------------------
    def _get_domain_memories_path(self, domain: str) -> Path:
        domain_slug = re.sub(r"[^\w]", "_", domain.lower())[:30] if domain else "general"
        return settings.eurekaclaw_dir / "memories" / domain_slug

    def _load_domain_index(self, domain_path: Path) -> dict[str, dict]:
        index_path = domain_path / "_index.json"
        if index_path.exists():
            try:
                return json.loads(index_path.read_text())
            except Exception:
                return {}
        return {}

    def load_for_injection(self, domain: str, k: int = 4, query: str | None = None) -> str:
        """Load top-k domain memories as a formatted block for prompt injection,
        optionally using semantic search.
        """
        domain_path = self._get_domain_memories_path(domain)
        if not domain_path.exists():
            return ""

        domain_index = self._load_domain_index(domain_path)
        insight_files_with_data = []

        for filename, data in domain_index.items():
            file_path = domain_path / filename
            if file_path.exists():
                insight_files_with_data.append({
                    "filename": filename,
                    "file_path": file_path,
                    "created_at": data.get("created_at", datetime.min.isoformat()),
                    "embedding": data.get("embedding") # Retrieve stored embedding
                })

        selected_insights = []
        if query and insight_files_with_data:
            try:
                query_embedding = get_embedding(query)
                scored_insights = []
                for insight in insight_files_with_data:
                    if insight["embedding"]: # Only consider insights that have an embedding
                        similarity = cosine_similarity(query_embedding, insight["embedding"])
                        scored_insights.append((similarity, insight))
                
                # Sort by similarity in descending order
                scored_insights.sort(key=lambda x: x[0], reverse=True)
                selected_insights = [item[1] for item in scored_insights[:k]]
            except Exception as e:
                # If embedding or similarity calculation fails, fall back to chronological
                # logger.warning(f"Semantic search failed for domain {domain}: {e}. Falling back to chronological.")
                pass # Fallback handled below

        if not selected_insights: # If semantic search failed or no query, use chronological
            insight_files_with_data.sort(key=lambda x: x["created_at"], reverse=True)
            selected_insights = insight_files_with_data[:k]

        parts = ["<memories>"]
        for insight in selected_insights:
            text = insight["file_path"].read_text(encoding="utf-8")
            # Strip frontmatter
            body = re.sub(r"^---\n.*?---\n", "", text, flags=re.DOTALL).strip()
            parts.append(body[:400]) # Truncate to 400 chars as per original logic
        parts.append("</memories>")
        return "\n\n".join(parts)
