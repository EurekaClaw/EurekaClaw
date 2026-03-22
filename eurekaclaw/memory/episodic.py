"""Within-session episodic memory — ring buffer of events for the current session."""

from __future__ import annotations

import uuid
from collections import deque
from typing import Any

from eurekaclaw.types.memory import EpisodicEntry


class EpisodicMemory:
    """Bounded in-memory event buffer for a single research session."""

    def __init__(self, session_id: str, max_entries: int = 500) -> None:
        self.session_id = session_id
        self._buffer: deque[EpisodicEntry] = deque(maxlen=max_entries)

    def record(self, agent_role: str, content: str, metadata: dict[str, Any] | None = None) -> EpisodicEntry:
        entry = EpisodicEntry(
            entry_id=str(uuid.uuid4()),
            session_id=self.session_id,
            agent_role=agent_role,
            content=content,
            metadata=metadata or {},
        )
        self._buffer.append(entry)
        return entry

    def get_recent(self, n: int = 20, agent_role: str | None = None) -> list[EpisodicEntry]:
        entries = list(self._buffer)
        if agent_role:
            entries = [e for e in entries if e.agent_role == agent_role]
        return entries[-n:]

    def get_all(self) -> list[EpisodicEntry]:
        return list(self._buffer)

    def search(self, keyword: str) -> list[EpisodicEntry]:
        kw = keyword.lower()
        return [e for e in self._buffer if kw in e.content.lower()]

    def __len__(self) -> int:
        return len(self._buffer)
