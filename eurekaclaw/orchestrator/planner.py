"""DivergentConvergentPlanner — generates 5 research directions, scores them, selects 1."""

from __future__ import annotations

import json
import logging
import uuid

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import ResearchBrief, ResearchDirection

logger = logging.getLogger(__name__)

DIVERGE_SYSTEM = """\
You are a creative research direction generator for theoretical research.

Generate 5 conceptually distinct research directions based on a research brief.
Each direction must:
1. Target a different gap in the literature
2. Use different mathematical tools or proof strategies
3. Have a different level of ambition (one bold, one incremental, three in between)

For each direction, provide a precise mathematical hypothesis.
"""

CONVERGE_SYSTEM = """\
You are a research direction evaluator. Score each direction on three axes:
1. Scientific Novelty (0-1): How different is this from existing work?
2. Technical Soundness (0-1): Is the hypothesis likely true and provable?
3. Transformative Potential (0-1): How much would this advance the field if proved?

Be strict — most directions should score below 0.7 on each axis.
Return the scores and select the best direction.
"""


class DivergentConvergentPlanner:
    """Generates 5 research directions (diverge) then scores and selects 1 (converge)."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def diverge(self, brief: ResearchBrief) -> list[ResearchDirection]:
        """Generate 5 conceptually distinct research directions."""
        open_problems = "\n".join(f"- {p}" for p in brief.open_problems[:5])
        math_objects = ", ".join(brief.key_mathematical_objects[:8])

        response = await self.client.messages.create(
            model=settings.active_model,
            max_tokens=settings.max_tokens_planner,
            system=DIVERGE_SYSTEM,
            messages=[{
                "role": "user",
                "content": f"""\
Generate 5 distinct research directions for:

Domain: {brief.domain}
Query: {brief.query}
Conjecture hint: {brief.conjecture or "(none)"}
Open problems: {open_problems or "(from survey)"}
Key math objects: {math_objects or "(from domain)"}

Return JSON: {{"directions": [
  {{"title": "...", "hypothesis": "LaTeX statement...", "approach": "...", "novelty_rationale": "..."}}
]}}
""",
            }],
        )
        if not response.content:
            raise ValueError("LLM returned empty content list")
        return self._parse_directions(response.content[0].text)

    async def converge(
        self, directions: list[ResearchDirection], brief: ResearchBrief
    ) -> ResearchDirection:
        """Score directions and return the best one."""
        if not directions:
            raise ValueError("No directions to converge on")
        if len(directions) == 1:
            return directions[0]

        # Compact representation: title + first 120 chars of hypothesis + first 80
        # chars of approach.  Saves ~300-400 tokens vs. full text in the converge
        # call.
        directions_text = "\n".join(
            f"[{i+1}] {d.title} | "
            f"Hyp: {d.hypothesis[:120].rstrip()}{'...' if len(d.hypothesis) > 120 else ''} | "
            f"Approach: {d.approach_sketch[:80].rstrip()}{'...' if len(d.approach_sketch) > 80 else ''}"
            for i, d in enumerate(directions)
        )

        response = await self.client.messages.create(
            model=settings.active_model,
            max_tokens=settings.max_tokens_planner // 2,
            system=CONVERGE_SYSTEM,
            messages=[{
                "role": "user",
                "content": f"""\
Score and select the best research direction for domain: {brief.domain}

{directions_text}

Return JSON: {{
  "scores": [
    {{"direction_index": 0, "novelty": 0.0-1.0, "soundness": 0.0-1.0, "transformative": 0.0-1.0}}
  ],
  "best_index": 0,
  "rationale": "..."
}}
""",
            }],
        )
        if not response.content:
            raise ValueError("LLM returned empty content list")
        return self._apply_scores(directions, response.content[0].text)

    def _parse_directions(self, text: str) -> list[ResearchDirection]:
        directions = []
        for delim_start, delim_end in [("```json", "```"), ("{", None)]:
            try:
                if delim_start in text:
                    start = text.index(delim_start) + len(delim_start)
                    if delim_end:
                        end = text.index(delim_end, start)
                        data = json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        data = json.loads(text[text.index("{"):end])
                    for d in data.get("directions", []):
                        rd = ResearchDirection(
                            direction_id=str(uuid.uuid4()),
                            title=d.get("title", "Research Direction"),
                            hypothesis=d.get("hypothesis", ""),
                            approach_sketch=d.get("approach", ""),
                        )
                        directions.append(rd)
                    return directions
            except (json.JSONDecodeError, ValueError):
                continue
        return directions

    def _apply_scores(self, directions: list[ResearchDirection], text: str) -> ResearchDirection:
        try:
            for delim_start, delim_end in [("```json", "```"), ("{", None)]:
                if delim_start in text:
                    start = text.index(delim_start) + len(delim_start)
                    if delim_end:
                        end = text.index(delim_end, start)
                        data = json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        data = json.loads(text[text.index("{"):end])

                    scores = data.get("scores", [])
                    for score_entry in scores:
                        idx = score_entry.get("direction_index", 0)
                        if 0 <= idx < len(directions):
                            d = directions[idx]
                            d.novelty_score = float(score_entry.get("novelty", 0.5))
                            d.soundness_score = float(score_entry.get("soundness", 0.5))
                            d.transformative_score = float(score_entry.get("transformative", 0.5))
                            d.compute_composite()

                    best_idx = int(data.get("best_index", 0))
                    if 0 <= best_idx < len(directions):
                        return directions[best_idx]
        except (json.JSONDecodeError, ValueError, KeyError):
            pass

        # Fallback: pick the one with the highest computed composite
        for d in directions:
            if d.composite_score == 0:
                d.novelty_score = 0.5
                d.soundness_score = 0.5
                d.transformative_score = 0.5
                d.compute_composite()
        return max(directions, key=lambda d: d.composite_score)
