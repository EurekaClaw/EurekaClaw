"""Analysis-oriented theory stages for memory-guided proof pipelines."""

from __future__ import annotations

import logging

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.memory.manager import MemoryManager
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

_MEMORY_ANALYSIS_SYSTEM = """\
You are a theory analysis assistant for rigorous mathematical proof planning in
machine learning theory, optimization, sampling, and related areas.

Use the recalled memory context only as guidance. Do not treat prior approaches as binding.
Your goal is to synthesize what prior sessions suggest about:
- promising proof routes
- likely failure modes
- reusable decomposition patterns
- special cases worth checking
- reusable theorems or lemmas from prior sessions

Return a concise structured note with these headings:
1. Forward analysis
2. Backward analysis
3. Special cases
4. Pitfalls from prior work
5. Reusable prior theorems/lemmas
6. Suggested route
"""

_MEMORY_ANALYSIS_USER = """\
Domain: {domain}
Informal statement:
{informal}

Research gap:
{research_gap}

Known results:
{known_results}

Cross-session memory context:
{memory_context}

Relevant prior theorems / lemmas from memory:
{memory_theorems}
"""

_TEMPLATE_SELECTOR_SYSTEM = """\
You classify theoretical proof tasks and select an appropriate proof template.

Choose the closest problem type and the most promising analytical template. Prefer
templates such as:
- optimism + confidence
- self-normalized concentration
- width sum / eluder style
- Lyapunov / one-step descent
- regularized gap decomposition
- coupling / contraction
- mixing + discretization
- lower bound / change of measure

Return JSON:
{
  "problem_type": "...",
  "proof_template": "...",
  "why": "2-4 sentences",
  "bottleneck_terms": ["...", "..."]
}
"""

_TEMPLATE_SELECTOR_USER = """\
Domain: {domain}
Informal statement:
{informal}

Research gap:
{research_gap}

Known results:
{known_results}

Analysis notes:
{analysis_notes}
"""

_SKELETON_BUILDER_SYSTEM = """\
You build proof skeletons for theoretical proofs.

Do not force a lemma DAG. Start from the target quantity, propose a decomposition,
identify the main analytical tools for each term, and say which steps truly need
independent lemmas. Be explicit about where rates come from.

Return a concise but structured outline with these headings:
1. Target quantity
2. Decomposition
3. Control of each term
4. Bottleneck
5. Candidate key lemmas
6. Parameter tuning / final rate
"""

_SKELETON_BUILDER_USER = """\
Domain: {domain}
Informal statement:
{informal}

Research gap:
{research_gap}

Problem type: {problem_type}
Proof template: {proof_template}

Analysis notes:
{analysis_notes}

Relevant prior theorems / lemmas from memory:
{memory_theorems}

Known results:
{known_results}
"""


class MemoryGuidedAnalyzer:
    """Summarize how existing memory should shape the current proof attempt."""

    def __init__(self, memory: MemoryManager | None = None, client: LLMClient | None = None) -> None:
        self.memory = memory
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        if not self.memory:
            return state

        # Construct a query for semantic retrieval of domain insights
        insight_query = "\n".join(filter(None, [state.informal_statement, state.research_gap]))
        memory_block = self.memory.load_for_injection(domain, k=4, query=insight_query)
        theorem_nodes = self.memory.retrieve_relevant_theorems(
            query="\n".join(filter(None, [state.informal_statement, state.research_gap])),
            domain=domain,
            limit=5,
        )
        theorem_lines = [
            f"- [{node.theorem_name}] {node.formal_statement[:220]}"
            for node in theorem_nodes
        ]
        state.memory_theorems = theorem_lines
        tagged_records = self.memory.recall_by_tag(domain)[:4] if domain else []
        hint_records = self.memory.recall_by_tag("proof_hint")[:3]
        event_lines = [
            f"- {entry.agent_role}: {entry.content[:120]}"
            for entry in self.memory.recent_events(6, agent_role="theory")
        ]
        tag_lines = [
            f"- [{record.key}] {str(record.value)[:200]}"
            for record in tagged_records + hint_records
        ]
        combined_context = "\n".join(
            part for part in [
                memory_block.strip(),
                "\n".join(tag_lines).strip(),
                "\n".join(event_lines).strip(),
            ] if part
        ).strip()
        if not combined_context:
            return state

        known_results = "\n".join(
            f"- {item.statement[:160]} (technique: {item.proof_technique})"
            for item in state.known_results[:8]
        ) or "(none)"

        try:
            response = await self.client.messages.create(
                model=settings.fast_model,
                max_tokens=1200,
                system=_MEMORY_ANALYSIS_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": _MEMORY_ANALYSIS_USER.format(
                        domain=domain or "mathematical research",
                        informal=state.informal_statement[:800],
                        research_gap=state.research_gap[:1200],
                        known_results=known_results,
                        memory_context=combined_context[:3000],
                        memory_theorems="\n".join(theorem_lines) or "(none)",
                    ),
                }],
            )
            if response.content:
                state.analysis_notes = response.content[0].text.strip()
                logger.info("MemoryGuidedAnalyzer: produced %d chars of analysis", len(state.analysis_notes))
        except Exception as exc:
            logger.warning("MemoryGuidedAnalyzer failed: %s", exc)

        return state


class TemplateSelector:
    """Classify the problem and select a proof template."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        known_results = "\n".join(
            f"- {item.statement[:160]} (technique: {item.proof_technique})"
            for item in state.known_results[:8]
        ) or "(none)"

        try:
            response = await self.client.messages.create(
                model=settings.fast_model,
                max_tokens=900,
                system=_TEMPLATE_SELECTOR_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": _TEMPLATE_SELECTOR_USER.format(
                        domain=domain or "mathematical research",
                        informal=state.informal_statement[:800],
                        research_gap=state.research_gap[:1200],
                        known_results=known_results,
                        analysis_notes=state.analysis_notes[:1600] or "(none)",
                        memory_theorems="\n".join(state.memory_theorems[:5]) or "(none)",
                    ),
                }],
            )
            if response.content:
                payload = _parse_json_object(response.content[0].text)
                state.problem_type = str(payload.get("problem_type", "")).strip()
                state.proof_template = str(payload.get("proof_template", "")).strip()
                why = str(payload.get("why", "")).strip()
                bottlenecks = payload.get("bottleneck_terms", [])
                if why:
                    tail = why
                    if bottlenecks:
                        tail += "\nBottleneck terms: " + ", ".join(str(item) for item in bottlenecks[:5])
                    state.analysis_notes = (state.analysis_notes + "\n\n" + tail).strip()
                logger.info(
                    "TemplateSelector: type=%s template=%s",
                    state.problem_type or "(unset)",
                    state.proof_template or "(unset)",
                )
        except Exception as exc:
            logger.warning("TemplateSelector failed: %s", exc)

        return state


class ProofSkeletonBuilder:
    """Build a proof skeleton before extracting technical lemmas."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        known_results = "\n".join(
            f"- {item.statement[:160]} (technique: {item.proof_technique})"
            for item in state.known_results[:8]
        ) or "(none)"

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=1600,
                system=_SKELETON_BUILDER_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": _SKELETON_BUILDER_USER.format(
                        domain=domain or "mathematical research",
                        informal=state.informal_statement[:900],
                        research_gap=state.research_gap[:1200],
                        problem_type=state.problem_type or "(unspecified)",
                        proof_template=state.proof_template or "(unspecified)",
                        analysis_notes=state.analysis_notes[:1800] or "(none)",
                        known_results=known_results,
                    ),
                }],
            )
            if response.content:
                state.proof_skeleton = response.content[0].text.strip()
                logger.info("ProofSkeletonBuilder: produced %d chars", len(state.proof_skeleton))
        except Exception as exc:
            logger.warning("ProofSkeletonBuilder failed: %s", exc)

        return state


def _parse_json_object(text: str) -> dict:
    import json
    import re

    match = re.search(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", text)
    if match:
        try:
            return json.loads(match.group(1))
        except Exception:
            pass
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            return json.loads(match.group(0))
        except Exception:
            pass
    return {}
