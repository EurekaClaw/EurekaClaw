"""SessionMemoryExtractor — extract and persist cross-session domain insights.

After each session, an LLM analyzes what happened and saves structured
memories to ~/.eurekaclaw/memories/. Future sessions load relevant memories
for context injection.

Memory categories:
  - domain_knowledge : new facts/lemmas/theorems discovered or confirmed
  - proof_strategy   : proof techniques that worked (or failed) in this domain
  - open_problems    : conjectures raised but not resolved
  - pitfalls         : approaches that looked promising but didn't work

Storage layout:
  ~/.eurekaclaw/memories/
    <domain>/
      <YYYYMMDD>_<slug>.md    ← one file per insight
    _index.json               ← dedup fingerprints (sha256 of content)
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Literal

from eurekaclaw.config import settings
from eurekaclaw.memory.embedding_utils import get_embedding # New import
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.knowledge_bus.bus import KnowledgeBus

logger = logging.getLogger(__name__)

MemoryCategory = Literal["domain_knowledge", "proof_strategy", "open_problems", "pitfalls"]

_EXTRACT_PROMPT = """\
You are analyzing a completed mathematical research session to extract lasting memories.

Domain: {domain}
Conjecture attempted: {conjecture}
Session outcome: {outcome}

Proven lemmas:
{lemmas}

Failed attempts summary:
{failures}

Extract memorable insights in these four categories. Only include high-value insights
that would meaningfully help a future session in the same domain. Skip obvious facts.

Output as JSON:
{{
  "domain_knowledge": [
    {{"title": "short title", "content": "1-3 sentence insight", "confidence": 0.0-1.0}}
  ],
  "proof_strategy": [
    {{"title": "strategy name", "content": "when and how to apply this", "confidence": 0.0-1.0}}
  ],
  "open_problems": [
    {{"title": "problem name", "content": "what remains unresolved and why", "confidence": 1.0}}
  ],
  "pitfalls": [
    {{"title": "pitfall name", "content": "what failed and the root cause", "confidence": 0.0-1.0}}
  ]
}}

Return only the JSON, no other text.
"""

_MERGE_PROMPT = """\
Two memory entries may be duplicates. Should they be merged?

Existing:
{existing}

New:
{new}

Reply with JSON: {{"merge": true/false, "merged_content": "merged text if merge=true"}}
"""


class SessionMemoryExtractor:
    """Extracts session insights and persists them as markdown memory files."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()
        self._base_dir = settings.eurekaclaw_dir / "memories"
        self._base_dir.mkdir(parents=True, exist_ok=True)

    def _load_domain_index(self, domain_dir: Path) -> dict[str, dict]:
        index_path = domain_dir / "_index.json"
        if index_path.exists():
            try:
                return json.loads(index_path.read_text())
            except Exception:
                return {}
        return {}

    def _save_domain_index(self, domain_dir: Path, index: dict[str, dict]) -> None:
        index_path = domain_dir / "_index.json"
        index_path.write_text(json.dumps(index, indent=2))

    def _fingerprint(self, content: str) -> str:
        return hashlib.sha256(content.strip().lower().encode()).hexdigest()[:16]

    async def extract_and_save(
        self,
        bus: KnowledgeBus,  
        domain: str = "",
    ) -> list[dict]:
        """Extract memories from the bus and save non-duplicate ones to disk."""
        theory_state = bus.get_theory_state()
        if not theory_state:
            return []

        lemmas_text = "\n".join(
            f"- [{lid}] (verified={r.verified}): {r.proof_text[:120]}"
            for lid, r in list(theory_state.proven_lemmas.items())[:8]
        )
        failures_text = "\n".join(
            f"- [{f.lemma_id}]: {f.failure_reason[:100]}"
            for f in theory_state.failed_attempts[:5]
        ) or "(none)"

        try:
            response = await self.client.messages.create(
                model=settings.fast_model,
                max_tokens=settings.max_tokens_formalizer,
                system="You extract lasting research insights from proof sessions. Be concise and precise.",
                messages=[{"role": "user", "content": _EXTRACT_PROMPT.format(
                    domain=domain or "mathematical research",
                    conjecture=(theory_state.informal_statement or theory_state.formal_statement or "")[:300],
                    outcome=theory_state.status,
                    lemmas=lemmas_text or "(none)",
                    failures=failures_text,
                )}],
            )
            text = response.content[0].text if response.content else "{}"
            data = self._parse_json(text)
        except Exception as e:
            logger.warning("Memory extraction LLM call failed: %s", e)
            return []

        saved: list[dict] = []
        domain_slug = re.sub(r"[^\w]", "_", domain.lower())[:30] if domain else "general"
        domain_dir = self._base_dir / domain_slug
        domain_index = self._load_domain_index(domain_dir)
        domain_dir.mkdir(exist_ok=True)

        for category in ("domain_knowledge", "proof_strategy", "open_problems", "pitfalls"):
            entries = data.get(category, [])
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                title = entry.get("title", "untitled")
                content = entry.get("content", "").strip()
                confidence = float(entry.get("confidence", 0.8))

                if not content or confidence < 0.5:
                    continue

                fp = self._fingerprint(title + content)
                if any(entry_data.get("fingerprint") == fp for entry_data in domain_index.values()):
                    logger.debug("Skipping duplicate memory: %s", title)
                    continue

                # Check for near-duplicates and potentially merge
                merged = await self._try_merge(domain_dir, category, title, content)
                if merged:
                    logger.info("Merged memory '%s' into existing entry", title)
                    continue

                # Save new memory file
                date_str = datetime.now().astimezone().strftime("%Y%m%d")
                slug = re.sub(r"[^\w]", "_", title.lower())[:40]
                path = domain_dir / f"{date_str}_{slug}.md"
                if path.exists():
                    path = domain_dir / f"{date_str}_{slug}_{fp[:4]}.md"

                md = (
                    f"---\n"
                    f"category: {category}\n"
                    f"title: {title}\n"
                    f"domain: {domain or 'general'}\n"
                    f"confidence: {confidence:.2f}\n"
                    f"created_at: {datetime.now().astimezone().isoformat()}\n"
                    f"---\n\n"
                    f"# {title}\n\n"
                    f"{content}\n"
                )
                path.write_text(md, encoding="utf-8")

                # Generate and store embedding
                embedding = get_embedding(f"{title} {content}")
                domain_index[path.name] = {
                    "fingerprint": fp,
                    "created_at": datetime.now().astimezone().isoformat(),
                    "embedding": embedding,
                    "category": category,
                }
                saved.append({"title": title, "category": category, "path": str(path)})
                logger.info("Saved memory [%s] '%s' → %s", category, title, path.name)

        if saved:
            self._save_domain_index(domain_dir, domain_index)
        return saved

    async def _try_merge(
        self, domain_dir: Path, category: str, title: str, content: str
    ) -> bool:
        """Check the 3 most recent same-category files for near-duplicate content."""
        existing_files = sorted(
            (f for f in domain_dir.glob("*.md") if category in f.read_text(encoding="utf-8")[:200]),
            key=lambda f: f.stat().st_mtime,
            reverse=True,
        )[:3]

        for ef in existing_files:
            existing_content = ef.read_text(encoding="utf-8")
            # Fast keyword overlap check before calling LLM
            existing_words = set(existing_content.lower().split())
            new_words = set((title + " " + content).lower().split())
            overlap = len(existing_words & new_words) / max(len(new_words), 1)
            if overlap < 0.4:
                continue

            # Worth asking LLM to decide
            try:
                response = await self.client.messages.create(
                    model=settings.fast_model,
                    max_tokens=settings.max_tokens_compress,
                    system="You decide whether two memory entries should be merged.",
                    messages=[{"role": "user", "content": _MERGE_PROMPT.format(
                        existing=existing_content[200:600],
                        new=f"Title: {title}\n{content}",
                    )}],
                )
                result = self._parse_json(response.content[0].text if response.content else "{}")
                if result.get("merge"):
                    # Overwrite existing file with merged content
                    merged_content = result.get("merged_content", content)
                    lines = existing_content.split("---\n", 2)
                    if len(lines) >= 3:
                        ef.write_text(lines[0] + "---\n" + lines[1] + "---\n\n" + merged_content)
                    return True
            except Exception:
                pass

        return False

    def _parse_json(self, text: str) -> dict:
        for pattern in [r"```json\n(.*?)```", r"(\{.*\})"]:
            m = re.search(pattern, text, re.DOTALL)
            if m:
                try:
                    return json.loads(m.group(1))
                except json.JSONDecodeError:
                    continue
        try:
            return json.loads(text)
        except Exception:
            return {}
