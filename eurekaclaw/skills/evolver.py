"""SkillEvolver — post-run LLM-based skill distillation from session failures/successes."""

from __future__ import annotations

import logging
import re
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.types.artifacts import FailedAttempt, ProofRecord
from eurekaclaw.types.skills import SkillMeta, SkillRecord

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

DISTILL_PROMPT = """\
You are a research skill distillation expert. Analyze the following session evidence \
(failures and successes) from a theoretical research session and extract reusable \
research strategies as a skill.

Session evidence:
{evidence}

Your task: Generate one concise, reusable research skill in this exact format:

---SKILL START---
# <Skill Title>

## When to apply
<1-2 sentences: describe when this strategy is useful>

## Strategy
<3-5 actionable steps or heuristics>

## Example application
<Brief concrete example>

## Pitfalls to avoid
<1-3 things that went wrong and how to avoid them>
---SKILL END---

Also provide metadata:
- tags: [comma-separated tags like theory, proof, induction]
- agent_roles: [comma-separated: survey, ideation, theory, experiment, writer]
- pipeline_stages: [comma-separated stages]
- description: <one-line description>
"""


class SkillEvolver:
    """Analyzes session failures and successes, generates new skill .md files."""

    def __init__(self, registry: SkillRegistry, client: LLMClient | None = None) -> None:
        self.registry = registry
        self.client: LLMClient = client or create_client()

    async def distill_from_session(
        self,
        session_id: str,
        failures: list[FailedAttempt],
        successes: list[ProofRecord],
        agent_role: str = "theory",
    ) -> list[SkillRecord]:
        """Generate new skills from session evidence via LLM distillation."""
        if not failures and not successes:
            return []

        evidence_parts = []
        for f in failures[:5]:
            evidence_parts.append(f"FAILURE [{f.lemma_id}]: {f.failure_reason}\nAttempt: {f.attempt_text[:200]}")
        for s in successes[:5]:
            evidence_parts.append(f"SUCCESS [{s.lemma_id}]: {s.proof_text[:200]}")

        evidence = "\n\n".join(evidence_parts)
        if not evidence.strip():
            return []

        try:
            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=settings.max_tokens_compress,
                messages=[{"role": "user", "content": DISTILL_PROMPT.format(evidence=evidence)}],
            )
            if not response.content:
                raise ValueError("LLM returned empty content list")
            text = response.content[0].text
            return self._parse_skill_response(text, session_id, agent_role)
        except Exception as e:
            logger.warning("Skill distillation failed: %s", e)
            return []

    def _parse_skill_response(
        self, text: str, session_id: str, agent_role: str
    ) -> list[SkillRecord]:
        """Parse LLM output into SkillRecord objects and persist them."""
        skills = []
        if "---SKILL START---" not in text or "---SKILL END---" not in text:
            return skills

        start = text.index("---SKILL START---") + len("---SKILL START---")
        end = text.index("---SKILL END---")
        skill_text = text[start:end].strip()

        # Extract metadata lines
        tags: list[str] = []
        roles: list[str] = [agent_role]
        stages: list[str] = []
        description = ""
        content_lines = []

        for line in skill_text.split("\n"):
            stripped = line.strip()
            if stripped.startswith("- tags:"):
                tags = [t.strip(" []") for t in stripped[7:].split(",")]
            elif stripped.startswith("- agent_roles:"):
                roles = [r.strip(" []") for r in stripped[14:].split(",")]
            elif stripped.startswith("- pipeline_stages:"):
                stages = [s.strip(" []") for s in stripped[18:].split(",")]
            elif stripped.startswith("- description:"):
                description = stripped[14:].strip()
            else:
                content_lines.append(line)

        content = "\n".join(content_lines).strip()

        # Derive a human-readable name from the H1 title in the skill content.
        raw_title = ""
        for line in content_lines:
            stripped = line.strip()
            if stripped.startswith("# "):
                raw_title = stripped[2:].strip()
                break
        uid = uuid.uuid4().hex[:6]
        if raw_title:
            title_slug = re.sub(r"[^a-z0-9]+", "_", raw_title.lower()).strip("_")[:40]
            skill_name = f"distilled_{title_slug}_{uid}"
            description = description or raw_title
        else:
            skill_name = f"distilled_{session_id[:8]}_{uid}"

        meta = SkillMeta(
            name=skill_name,
            version="1.0",
            tags=[t for t in tags if t],
            agent_roles=[r for r in roles if r],
            pipeline_stages=[s for s in stages if s],
            description=description or "Distilled from session evidence",
            source="distilled",
            created_at=datetime.utcnow(),
        )
        record = SkillRecord(meta=meta, content=content)
        self.registry.upsert(record)
        skills.append(record)
        logger.info("Distilled new skill: %s", skill_name)
        return skills
