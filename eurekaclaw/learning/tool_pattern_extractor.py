"""ToolPatternExtractor — auto-generate skills from successful tool call sequences.

When a proof succeeds, analyze which tools were called and in what order,
then distill that sequence into a reusable skill so future sessions can
replicate the winning pattern without trial-and-error.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from datetime import datetime
from pathlib import Path

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.skills import SkillMeta, SkillRecord
from eurekaclaw.knowledge_bus.bus import KnowledgeBus

logger = logging.getLogger(__name__)

_PATTERN_PROMPT = """\
You are analyzing a successful mathematical proof session to extract a reusable tool-use pattern.

Domain: {domain}
Conjecture proved: {conjecture}

Tools used in order (with outcomes):
{tool_sequence}

Proven lemmas summary:
{lemmas_summary}

Extract a reusable skill describing WHEN and HOW to use these tools in this sequence.
Be concrete and actionable. Focus on the tool ordering logic, not the math content.

Output format:
---SKILL START---
# <Title: specific tool pattern name>

## When to apply
<1-2 sentences: what kind of conjecture or proof step benefits from this tool sequence>

## Tool sequence
<Numbered list of tools in order, with brief reason for each step>

## Key parameters
<What inputs/settings matter most for each tool>

## Success indicators
<How to know the sequence is working vs. when to bail out early>
---SKILL END---

Metadata (on separate lines after ---SKILL END---):
tags: <comma-separated>
agent_roles: theory,experiment
pipeline_stages: proof_attempt,experiment
description: <one line>
"""


class ToolPatternExtractor:
    """Extracts successful tool-call patterns and saves them as skill files."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()
        self._skills_dir = settings.skills_dir
        self._skills_dir.mkdir(parents=True, exist_ok=True)

    async def extract_and_save(
        self,
        bus: KnowledgeBus,
        domain: str = "",
    ) -> list[SkillRecord]:
        """Analyze bus artifacts for successful tool sequences and generate skills."""
        theory_state = bus.get_theory_state()
        if not theory_state or not theory_state.proven_lemmas:
            return []

        tool_calls: list[dict] = bus.get("tool_call_log") or []
        if not tool_calls:
            logger.debug("No tool call log on bus — skipping tool pattern extraction")
            return []

        # Group tool calls by lemma (keyed by lemma_id in tool call metadata)
        lemma_tools: dict[str, list[dict]] = {}
        for call in tool_calls:
            lid = call.get("lemma_id", "unknown")
            lemma_tools.setdefault(lid, []).append(call)

        new_skills: list[SkillRecord] = []
        for lemma_id, record in theory_state.proven_lemmas.items():
            calls = lemma_tools.get(lemma_id, [])
            if not calls or len(calls) < 2:
                # Single-tool proofs are not interesting patterns
                continue
            # Only extract patterns for high-confidence verified proofs
            node = theory_state.lemma_dag.get(lemma_id)
            conf = node.confidence_score if node else None
            if conf is not None and conf < 0.7:
                continue

            skill = await self._generate_skill(
                domain=domain,
                conjecture=(theory_state.informal_statement or theory_state.formal_statement or ""),
                tool_calls=calls,
                lemma_id=lemma_id,
                proof_text=record.proof_text[:300],
            )
            if skill:
                self._save_skill(skill)
                new_skills.append(skill)

        if new_skills:
            logger.info(
                "ToolPatternExtractor: generated %d new tool-pattern skills", len(new_skills)
            )
        return new_skills

    async def _generate_skill(
        self,
        domain: str,
        conjecture: str,
        tool_calls: list[dict],
        lemma_id: str,
        proof_text: str,
    ) -> SkillRecord | None:
        tool_sequence = "\n".join(
            f"{i+1}. {c.get('tool_name','?')}({json.dumps(c.get('args',{}))[:80]}) "
            f"→ {'✓' if c.get('success') else '✗'} {c.get('summary','')[:60]}"
            for i, c in enumerate(tool_calls[:10])
        )
        lemmas_summary = f"[{lemma_id}]: {proof_text}"

        try:
            response = await self.client.messages.create(
                model=settings.fast_model,
                max_tokens=settings.max_tokens_compress,
                system="You extract reusable research tool-use patterns from successful proofs.",
                messages=[{"role": "user", "content": _PATTERN_PROMPT.format(
                    domain=domain or "mathematical research",
                    conjecture=conjecture[:200],
                    tool_sequence=tool_sequence,
                    lemmas_summary=lemmas_summary,
                )}],
            )
            text = response.content[0].text if response.content else ""
            return self._parse_skill(text, domain)
        except Exception as e:
            logger.warning("Tool pattern extraction failed for %s: %s", lemma_id, e)
            return None

    def _parse_skill(self, text: str, domain: str) -> SkillRecord | None:
        match = re.search(r"---SKILL START---\n(.*?)\n---SKILL END---", text, re.DOTALL)
        if not match:
            return None
        content = match.group(1).strip()

        tags = ["tool_pattern", domain.replace(" ", "_")] if domain else ["tool_pattern"]
        description = f"Tool pattern extracted from {domain} session" if domain else "Auto-extracted tool pattern"

        # Parse metadata lines after ---SKILL END---
        after = text[match.end():]
        for line in after.splitlines():
            if line.startswith("tags:"):
                tags += [t.strip() for t in line[5:].split(",") if t.strip()]
            elif line.startswith("description:"):
                description = line[12:].strip()

        title_match = re.search(r"^# (.+)$", content, re.MULTILINE)
        name = title_match.group(1).strip() if title_match else f"tool_pattern_{uuid.uuid4().hex[:6]}"

        meta = SkillMeta(
            name=name,
            description=description,
            tags=list(set(tags)),
            agent_roles=["theory", "experiment"],
            pipeline_stages=["proof_attempt", "experiment"],
            source="tool_pattern_extractor",
            created_at=datetime.now().astimezone().isoformat(),
        )
        return SkillRecord(meta=meta, content=content)

    def _save_skill(self, skill: SkillRecord) -> None:
        safe_name = re.sub(r"[^\w\-]", "_", skill.meta.name)[:60]
        
        path = self._skills_dir / f"{safe_name}"
        path.mkdir(parents=True, exist_ok=True)

        filename = path / "SKILL.md"
        frontmatter = (
            f"---\n"
            f"name: {skill.meta.name}\n"
            f"description: {skill.meta.description}\n"
            f"tags: [{', '.join(skill.meta.tags)}]\n"
            f"agent_roles: [{', '.join(skill.meta.agent_roles)}]\n"
            f"pipeline_stages: [{', '.join(skill.meta.pipeline_stages)}]\n"
            f"source: {skill.meta.source}\n"
            f"created_at: {skill.meta.created_at}\n"
            f"---\n\n"
        )
        filename.write_text(frontmatter + skill.content, encoding="utf-8")
        logger.info("Saved tool-pattern skill: %s", path)
