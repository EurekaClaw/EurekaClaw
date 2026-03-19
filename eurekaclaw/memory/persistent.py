"""Cross-session persistent memory — JSON file store under ~/.eurekaclaw/memory/."""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from eurekaclaw.types.memory import CrossRunRecord

logger = logging.getLogger(__name__)


class PersistentMemory:
    """Persistent key-value store that survives across research sessions."""

    def __init__(self, memory_dir: Path) -> None:
        self.memory_dir = memory_dir
        self._store_path = memory_dir / "persistent.json"
        self._data: dict[str, CrossRunRecord] = {}
        self._load()

    def _load(self) -> None:
        if self._store_path.exists():
            try:
                raw = json.loads(self._store_path.read_text())
                self._data = {k: CrossRunRecord.model_validate(v) for k, v in raw.items()}
                logger.debug("Loaded %d persistent memory records", len(self._data))
            except Exception as e:
                logger.warning("Failed to load persistent memory: %s", e)

    def _save(self) -> None:
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        self._store_path.write_text(
            json.dumps({k: v.model_dump(mode="json") for k, v in self._data.items()}, indent=2)
        )

    def put(self, key: str, value: Any, tags: list[str] | None = None, source_session: str = "") -> CrossRunRecord:
        record = CrossRunRecord(
            record_id=str(uuid.uuid4()),
            key=key,
            value=value,
            tags=tags or [],
            source_session=source_session,
            updated_at=datetime.utcnow(),
        )
        self._data[key] = record
        self._save()
        return record

    def get(self, key: str) -> Any | None:
        record = self._data.get(key)
        return record.value if record else None

    def get_by_tag(self, tag: str) -> list[CrossRunRecord]:
        return [r for r in self._data.values() if tag in r.tags]

    def search_keys(self, prefix: str) -> list[CrossRunRecord]:
        return [r for r in self._data.values() if r.key.startswith(prefix)]

    def delete(self, key: str) -> None:
        if key in self._data:
            del self._data[key]
            self._save()

    def all_records(self) -> list[CrossRunRecord]:
        return list(self._data.values())
