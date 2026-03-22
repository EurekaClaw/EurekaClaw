"""Unit tests for the Divergent-Convergent planner."""

import pytest
from unittest.mock import AsyncMock, MagicMock

from eurekaclaw.orchestrator.planner import DivergentConvergentPlanner
from eurekaclaw.types.artifacts import ResearchBrief, ResearchDirection


@pytest.fixture
def mock_brief():
    return ResearchBrief(
        session_id="s1",
        input_mode="detailed",
        domain="ML theory",
        query="Prove transformer bounds",
        open_problems=["No tight sample complexity bounds for attention"],
        key_mathematical_objects=["Rademacher complexity", "VC dimension"],
    )


def test_planner_parse_directions():
    planner = DivergentConvergentPlanner.__new__(DivergentConvergentPlanner)
    text = '```json\n{"directions": [{"title": "Dir 1", "hypothesis": "H1", "approach": "A1", "novelty_rationale": "N1"}, {"title": "Dir 2", "hypothesis": "H2", "approach": "A2", "novelty_rationale": "N2"}]}\n```'
    directions = planner._parse_directions(text)
    assert len(directions) == 2
    assert directions[0].title == "Dir 1"


def test_planner_apply_scores_selects_best():
    planner = DivergentConvergentPlanner.__new__(DivergentConvergentPlanner)
    directions = [
        ResearchDirection(direction_id="d1", title="Dir 1", hypothesis="H1"),
        ResearchDirection(direction_id="d2", title="Dir 2", hypothesis="H2"),
    ]
    text = '{"scores": [{"direction_index": 0, "novelty": 0.3, "soundness": 0.3, "transformative": 0.3}, {"direction_index": 1, "novelty": 0.9, "soundness": 0.8, "transformative": 0.7}], "best_index": 1}'
    best = planner._apply_scores(directions, text)
    assert best.title == "Dir 2"
    assert best.novelty_score == 0.9


def test_planner_apply_scores_fallback():
    planner = DivergentConvergentPlanner.__new__(DivergentConvergentPlanner)
    directions = [
        ResearchDirection(direction_id="d1", title="Dir 1", hypothesis="H1"),
    ]
    # Invalid JSON should not crash
    best = planner._apply_scores(directions, "invalid json here")
    assert best.direction_id == "d1"
