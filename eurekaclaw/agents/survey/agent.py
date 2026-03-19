"""SurveyAgent — deep literature search using arXiv, Semantic Scholar, and web search."""

from __future__ import annotations

import json
import logging

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.artifacts import Bibliography, Paper, ResearchBrief
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


def _to_str_list(items: list) -> list[str]:
    """Coerce a list that may contain strings or dicts to a list of strings."""
    result = []
    for item in items:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict):
            # Try common keys the LLM uses for the human-readable label
            for key in ("name", "title", "problem", "object", "description", "text"):
                if key in item:
                    result.append(str(item[key]))
                    break
            else:
                # Fallback: join all values
                result.append(", ".join(str(v) for v in item.values() if v))
        else:
            result.append(str(item))
    return result


class SurveyAgent(BaseAgent):
    """Searches arXiv, Semantic Scholar, and web for relevant literature.

    Produces:
    - Updated ResearchBrief with citation graph, open problems, key math objects
    - Bibliography artifact with structured paper metadata
    """

    role = AgentRole.SURVEY

    def get_tool_names(self) -> list[str]:
        return ["arxiv_search", "semantic_scholar_search", "web_search", "citation_manager"]

    def _role_system_prompt(self, task: Task) -> str:
        return """\
You are the Survey Agent of EurekaClaw, a multi-agent system for theoretical research.

Your mission:
1. Search arXiv and Semantic Scholar for papers relevant to the research question
2. Identify the frontier of the field: What is the current state of the art?
3. Extract open problems and unexplored gaps from the literature
4. Build a citation graph and identify the most influential papers
5. Summarize key mathematical objects, definitions, and techniques in the area
6. Decompose each important paper into: Insight, Research Trending, Serendipity

Use the available search tools systematically. Start broad (3-5 searches), then drill into the most relevant papers.

Output a structured JSON summary with:
- papers: list of the most relevant papers with metadata
- open_problems: list of explicit open questions from the literature
- key_mathematical_objects: central definitions, theorems, techniques
- research_frontier: what directions are most active right now
- citation_graph_summary: which papers are most highly cited / influential
"""

    async def execute(self, task: Task) -> AgentResult:
        brief = self.bus.get_research_brief()
        if not brief:
            return self._make_result(task, False, {}, error="No ResearchBrief found on bus")

        query = brief.query or brief.domain
        domain = brief.domain

        user_message = f"""\
Conduct a comprehensive literature survey for the following research area:

Domain: {domain}
Research Question: {query}
Additional Context: {brief.conjecture or "No specific conjecture yet — do open exploration"}

Please:
1. Search arXiv for the 10-15 most relevant recent papers
2. Search Semantic Scholar for highly-cited foundational works
3. Identify at least 5 specific open problems
4. List the key mathematical objects/definitions in this area
5. Summarize the research frontier

Return your final findings as a JSON object with keys:
papers, open_problems, key_mathematical_objects, research_frontier, insights
"""

        try:
            text, tokens = await self.run_agent_loop(task, user_message, max_turns=8)

            # Try to extract structured data from the response
            survey_data = self._parse_survey_output(text)

            # Update the bibliography on the knowledge bus
            papers = [
                Paper(
                    paper_id=p.get("arxiv_id") or p.get("s2_id") or p.get("title", "")[:20],
                    title=p.get("title", ""),
                    authors=p.get("authors", []),
                    year=p.get("year"),
                    abstract=p.get("abstract", ""),
                    venue=p.get("venue", ""),
                    arxiv_id=p.get("arxiv_id") or "",
                    semantic_scholar_id=p.get("s2_id") or "",
                    citation_count=p.get("citation_count", 0),
                    url=p.get("url", ""),
                    relevance_score=p.get("relevance_score", 0.0),
                )
                for p in survey_data.get("papers", [])
            ]
            self.bus.append_citations(papers)

            # Update the research brief with survey findings.
            # The LLM may return lists of dicts instead of lists of strings;
            # coerce each item to a plain string so downstream agents don't crash.
            brief.open_problems = _to_str_list(survey_data.get("open_problems", []))
            brief.key_mathematical_objects = _to_str_list(survey_data.get("key_mathematical_objects", []))
            self.bus.put_research_brief(brief)

            # Ensure bibliography exists
            bib = self.bus.get_bibliography() or Bibliography(session_id=brief.session_id)
            self.bus.put_bibliography(bib)

            self.memory.log_event(
                self.role.value,
                f"Survey complete: {len(papers)} papers, {len(brief.open_problems)} open problems",
            )

            return self._make_result(
                task,
                success=True,
                output=survey_data,
                text_summary=text[:500],
                token_usage=tokens,
            )
        except Exception as e:
            logger.exception("Survey agent failed")
            return self._make_result(task, False, {}, error=str(e))

    def _parse_survey_output(self, text: str) -> dict:
        """Try to extract JSON from the agent's text output."""
        # Find JSON block
        if "```json" in text:
            start = text.index("```json") + 7
            end = text.index("```", start)
            try:
                return json.loads(text[start:end].strip())
            except json.JSONDecodeError:
                pass
        if "{" in text and "}" in text:
            try:
                start = text.index("{")
                end = text.rindex("}") + 1
                return json.loads(text[start:end])
            except (json.JSONDecodeError, ValueError):
                pass
        # Fallback: return empty structure
        return {
            "papers": [],
            "open_problems": [],
            "key_mathematical_objects": [],
            "research_frontier": text[:1000],
            "insights": [],
        }
