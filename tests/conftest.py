"""Shared pytest fixtures for EurekaClaw tests."""

import pytest

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ResearchBrief, TheoryState


@pytest.fixture
def session_id() -> str:
    return "test-session-001"


@pytest.fixture
def bus(session_id: str) -> KnowledgeBus:
    return KnowledgeBus(session_id)


@pytest.fixture
def research_brief(session_id: str) -> ResearchBrief:
    return ResearchBrief(
        session_id=session_id,
        input_mode="detailed",
        domain="machine learning theory",
        query="Prove generalization bounds for transformers",
        conjecture="The sample complexity of transformers is O(L*d/eps^2)",
    )


@pytest.fixture
def theory_state(session_id: str) -> TheoryState:
    return TheoryState(
        session_id=session_id,
        theorem_id="thm-001",
        informal_statement="The sample complexity of transformers is O(L*d/eps^2)",
        formal_statement="",
        status="pending",
    )
