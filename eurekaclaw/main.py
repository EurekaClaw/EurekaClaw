"""EurekaSession — top-level entry point for a research session."""

from __future__ import annotations

import asyncio
import logging
import uuid

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
from eurekaclaw.types.tasks import InputSpec, ResearchOutput

logger = logging.getLogger(__name__)


class EurekaSession:
    """A complete EurekaClaw research session.

    Usage:
        session = EurekaSession()
        result = asyncio.run(session.run_detailed("Prove that sample complexity of transformers..."))
        result = asyncio.run(session.run_exploration("sample complexity of transformers"))
    """

    def __init__(self, session_id: str | None = None) -> None:
        self.session_id = session_id or str(uuid.uuid4())
        self.bus = KnowledgeBus(self.session_id)
        self._orchestrator: MetaOrchestrator | None = None

    @property
    def orchestrator(self) -> MetaOrchestrator:
        if not self._orchestrator:
            self._orchestrator = MetaOrchestrator(bus=self.bus)
        return self._orchestrator

    async def run(self, input_spec: InputSpec) -> ResearchOutput:
        """Run a complete research session from an InputSpec."""
        return await self.orchestrator.run(input_spec)

    async def run_detailed(self, conjecture: str, domain: str = "") -> ResearchOutput:
        """Level 1 mode: user provides a specific conjecture."""
        spec = InputSpec(
            mode="detailed",
            conjecture=conjecture,
            domain=domain or _infer_domain(conjecture),
            query=conjecture,
        )
        return await self.run(spec)

    async def run_from_papers(self, paper_ids: list[str], domain: str) -> ResearchOutput:
        """Level 2 mode: user provides reference papers for gap exploration."""
        spec = InputSpec(
            mode="reference",
            paper_ids=paper_ids,
            domain=domain,
            query=f"Identify research gaps in {domain}",
        )
        return await self.run(spec)

    async def run_exploration(self, domain: str, query: str = "") -> ResearchOutput:
        """Level 3 mode: open exploration of a domain."""
        spec = InputSpec(
            mode="exploration",
            domain=domain,
            query=query or f"Survey the frontier of {domain} and propose novel directions",
        )
        return await self.run(spec)


def run_research(conjecture: str, domain: str = "") -> ResearchOutput:
    """Synchronous entry point. Blocks until the session completes."""
    session = EurekaSession()
    return asyncio.run(session.run_detailed(conjecture, domain))


def _infer_domain(query: str) -> str:
    """Heuristically infer the research domain from a query string."""
    query_lower = query.lower()
    domain_keywords = {
        "sample complexity": "machine learning theory",
        "generalization": "machine learning theory",
        "VC dimension": "machine learning theory",
        "PAC learning": "machine learning theory",
        "transformer": "deep learning theory",
        "attention": "deep learning theory",
        "graph": "graph theory",
        "topology": "topology",
        "probability": "probability theory",
        "concentration": "probability theory",
        "complexity": "computational complexity",
        "NP": "computational complexity",
        "optimization": "optimization theory",
        "convex": "convex optimization",
    }
    for kw, domain in domain_keywords.items():
        if kw.lower() in query_lower:
            return domain
    return "theoretical mathematics"
