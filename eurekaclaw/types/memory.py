"""Memory tier types."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class EpisodicEntry(BaseModel):
    """Within-session episodic memory entry."""
    entry_id: str
    session_id: str
    agent_role: str
    content: str
    metadata: dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class CrossRunRecord(BaseModel):
    """Cross-session persistent memory record."""
    record_id: str
    key: str          # namespaced key e.g. "theory.failed_strategies.sample_complexity"
    value: Any
    tags: list[str] = Field(default_factory=list)
    source_session: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class KnowledgeNode(BaseModel):
    """Node in the cross-project theorem knowledge graph."""
    node_id: str
    theorem_name: str
    formal_statement: str
    domain: str = ""
    session_id: str = ""
    related_to: list[str] = Field(default_factory=list)  # other node_ids
    tags: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
