"""Cross-project theorem knowledge graph using networkx."""

from __future__ import annotations

import json
import logging
import uuid
from pathlib import Path
from typing import Any

from eurekaclaw.types.memory import KnowledgeNode

logger = logging.getLogger(__name__)


class KnowledgeGraph:
    """Directed graph linking theorems and lemmas across research sessions."""

    def __init__(self, memory_dir: Path) -> None:
        self.memory_dir = memory_dir
        self._graph_path = memory_dir / "knowledge_graph.json"
        self._nodes: dict[str, KnowledgeNode] = {}
        self._edges: list[tuple[str, str, str]] = []  # (from_id, to_id, relation)
        self._load()

    def _load(self) -> None:
        if self._graph_path.exists():
            try:
                data = json.loads(self._graph_path.read_text())
                self._nodes = {k: KnowledgeNode.model_validate(v) for k, v in data.get("nodes", {}).items()}
                self._edges = [tuple(e) for e in data.get("edges", [])]  # type: ignore
                logger.debug("Loaded knowledge graph: %d nodes, %d edges", len(self._nodes), len(self._edges))
            except Exception as e:
                logger.warning("Failed to load knowledge graph: %s", e)

    def _save(self) -> None:
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        data = {
            "nodes": {k: v.model_dump(mode="json") for k, v in self._nodes.items()},
            "edges": [list(e) for e in self._edges],
        }
        self._graph_path.write_text(json.dumps(data, indent=2))

    def add_theorem(
        self,
        theorem_name: str,
        formal_statement: str,
        domain: str = "",
        session_id: str = "",
        tags: list[str] | None = None,
    ) -> KnowledgeNode:
        node = KnowledgeNode(
            node_id=str(uuid.uuid4()),
            theorem_name=theorem_name,
            formal_statement=formal_statement,
            domain=domain,
            session_id=session_id,
            tags=tags or [],
        )
        self._nodes[node.node_id] = node
        self._save()
        return node

    def add_edge(self, from_id: str, to_id: str, relation: str = "uses") -> None:
        """Relation types: 'uses', 'generalizes', 'specializes', 'contradicts'."""
        if from_id in self._nodes and to_id in self._nodes:
            self._edges.append((from_id, to_id, relation))
            self._save()

    def find_related(self, node_id: str, depth: int = 2) -> list[KnowledgeNode]:
        """BFS traversal to find related theorems within depth hops."""
        visited = {node_id}
        frontier = {node_id}
        for _ in range(depth):
            next_frontier = set()
            for nid in frontier:
                neighbors = {e[1] for e in self._edges if e[0] == nid}
                neighbors |= {e[0] for e in self._edges if e[1] == nid}
                next_frontier |= neighbors - visited
            visited |= next_frontier
            frontier = next_frontier
        visited.discard(node_id)
        return [self._nodes[nid] for nid in visited if nid in self._nodes]

    def search_by_domain(self, domain: str) -> list[KnowledgeNode]:
        return [n for n in self._nodes.values() if domain.lower() in n.domain.lower()]

    def search_by_tag(self, tag: str) -> list[KnowledgeNode]:
        return [n for n in self._nodes.values() if tag in n.tags]

    def all_nodes(self) -> list[KnowledgeNode]:
        return list(self._nodes.values())

    def to_networkx(self) -> Any:
        try:
            import networkx as nx  # type: ignore
            G = nx.DiGraph()
            for nid, node in self._nodes.items():
                G.add_node(nid, **node.model_dump(exclude={"related_to"}))
            for from_id, to_id, relation in self._edges:
                G.add_edge(from_id, to_id, relation=relation)
            return G
        except ImportError:
            raise ImportError("networkx is required for graph operations. Run: pip install networkx")

    def stats(self) -> dict[str, int]:
        return {"nodes": len(self._nodes), "edges": len(self._edges)}
