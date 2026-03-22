"""Unit tests for the KnowledgeBus."""

import pytest

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import Paper, ResearchBrief, TheoryState


def test_put_and_get_research_brief(bus, research_brief):
    bus.put_research_brief(research_brief)
    retrieved = bus.get_research_brief()
    assert retrieved is not None
    assert retrieved.session_id == research_brief.session_id
    assert retrieved.domain == research_brief.domain


def test_put_and_get_theory_state(bus, theory_state):
    bus.put_theory_state(theory_state)
    retrieved = bus.get_theory_state()
    assert retrieved is not None
    assert retrieved.theorem_id == theory_state.theorem_id


def test_append_citations(bus, session_id):
    papers = [
        Paper(paper_id="p1", title="Paper 1", authors=["A"], year=2023),
        Paper(paper_id="p2", title="Paper 2", authors=["B"], year=2024),
    ]
    bus.append_citations(papers)
    bib = bus.get_bibliography()
    assert bib is not None
    assert len(bib.papers) == 2

    # Append again — no duplicates
    bus.append_citations(papers)
    bib = bus.get_bibliography()
    assert len(bib.papers) == 2


def test_subscribe_callback(bus, research_brief):
    received = []
    bus.subscribe("research_brief", lambda b: received.append(b))
    bus.put_research_brief(research_brief)
    assert len(received) == 1
    assert received[0].session_id == research_brief.session_id


def test_generic_key_value(bus):
    bus.put("custom_key", {"foo": "bar"})
    val = bus.get("custom_key")
    assert val == {"foo": "bar"}

    missing = bus.get("nonexistent", default=42)
    assert missing == 42
