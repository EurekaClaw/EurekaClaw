"""IdeationAgent — hypothesis generation, gap identification, cross-disciplinary connections."""

from __future__ import annotations

import json
import logging
import uuid

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.artifacts import ResearchDirection
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


class IdeationAgent(BaseAgent):
    """Generates novel research hypotheses from survey findings.

    Uses a DeepInnovator-style approach: identifies gaps, makes cross-domain
    connections, and ranks hypotheses by novelty × impact × feasibility.
    """

    role = AgentRole.IDEATION

    def get_tool_names(self) -> list[str]:
        return ["web_search", "arxiv_search"]

    def _role_system_prompt(self, task: Task) -> str:
        return """\
You are the Ideation Agent of EurekaClaw. Your role is to generate novel research hypotheses.

Your process:
1. **Gap analysis**: From the survey findings, identify what theorems are missing or incomplete
2. **Cross-domain connection**: Look for analogies from adjacent fields
3. **Hypothesis generation**: For each gap, formulate a precise mathematical conjecture
4. **Scoring**: Rate each hypothesis on Novelty (0-1), Feasibility (0-1), and Impact (0-1)

For each hypothesis, provide:
- A precise mathematical statement (use LaTeX notation)
- The key insight behind why this might be true
- A sketch of what the proof strategy might look like
- Why this is novel (what it improves over prior work)
- Potential obstacles

Be creative but grounded. A good hypothesis is surprising yet believable.
Output a JSON object with "directions" as a list of 5 research directions.
"""

    async def execute(self, task: Task) -> AgentResult:
        brief = self.bus.get_research_brief()
        if not brief:
            return self._make_result(task, False, {}, error="No ResearchBrief found on bus")

        bib = self.bus.get_bibliography()
        papers_summary = ""
        if bib and bib.papers:
            top_papers = sorted(bib.papers, key=lambda p: p.relevance_score, reverse=True)[:10]
            papers_summary = "\n".join(
                f"- {p.title} ({p.year}): {p.abstract[:200]}" for p in top_papers
            )

        open_problems = "\n".join(f"- {p}" for p in brief.open_problems[:10])
        math_objects = ", ".join(brief.key_mathematical_objects[:10])

        user_message = f"""\
Based on this literature survey, generate 5 novel research directions.

Domain: {brief.domain}
Research Question: {brief.query}

Open Problems:
{open_problems or "(none identified yet)"}

Key Mathematical Objects: {math_objects or "(none identified yet)"}

Top Papers:
{papers_summary or "(no papers yet)"}

Generate exactly 5 research directions, each as a precise mathematical conjecture with:
1. A formal hypothesis statement in LaTeX
2. Novelty score (0-1) and rationale
3. Feasibility score (0-1) and proof sketch
4. Impact score (0-1) and significance
5. Key obstacle to overcome

Return as JSON: {{"directions": [{{...}}, ...]}}
"""

        try:
            text, tokens = await self.run_agent_loop(task, user_message, max_turns=6)
            directions_data = self._parse_directions(text)

            # Convert to ResearchDirection objects and store on brief
            directions = []
            for d in directions_data:
                def _as_str(v: object) -> str:
                    """Coerce LLM value to string (it sometimes returns a dict)."""
                    if isinstance(v, dict):
                        return v.get("statement", v.get("text", str(v)))
                    return str(v) if v is not None else ""

                rd = ResearchDirection(
                    direction_id=str(uuid.uuid4()),
                    title=_as_str(d.get("title", "Research Direction")),
                    hypothesis=_as_str(d.get("hypothesis", d.get("formal_statement", ""))),
                    approach_sketch=_as_str(d.get("proof_sketch", d.get("approach", ""))),
                    novelty_score=float(d.get("novelty_score", 0.5)),
                    soundness_score=float(d.get("feasibility_score", 0.5)),
                    transformative_score=float(d.get("impact_score", 0.5)),
                )
                rd.compute_composite()
                directions.append(rd)

            brief.directions = directions
            self.bus.put_research_brief(brief)

            self.memory.log_event(
                self.role.value,
                f"Generated {len(directions)} research directions",
            )

            return self._make_result(
                task,
                success=True,
                output={"directions": [d.model_dump() for d in directions]},
                text_summary=f"Generated {len(directions)} research directions",
                token_usage=tokens,
            )
        except Exception as e:
            logger.exception("Ideation agent failed")
            return self._make_result(task, False, {}, error=str(e))

    def _parse_directions(self, text: str) -> list[dict]:
        # 1. Fenced code block: ```json ... ```
        for fence in ("```json", "```"):
            if fence in text:
                try:
                    start = text.index(fence) + len(fence)
                    end = text.index("```", start)
                    data = json.loads(text[start:end].strip())
                    if isinstance(data, dict) and "directions" in data:
                        return data["directions"]
                    if isinstance(data, list):
                        return data
                except (json.JSONDecodeError, ValueError):
                    pass

        # 2. Find the JSON object that contains a "directions" key directly,
        #    rather than grabbing the first "{" which may be inside prose text.
        search = text
        while '{"directions"' in search or '"directions"' in search:
            try:
                idx = search.index("{")
                end = search.rindex("}") + 1
                data = json.loads(search[idx:end])
                if isinstance(data, dict) and "directions" in data:
                    return data["directions"]
                if isinstance(data, list):
                    return data
            except (json.JSONDecodeError, ValueError):
                pass
            # Advance past the first "{" and retry
            next_brace = search.find("{", 1)
            if next_brace == -1:
                break
            search = search[next_brace:]

        return []
