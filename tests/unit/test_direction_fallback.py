"""Unit tests for the direction planning fallback in MetaOrchestrator."""

import sys
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Stub out sentence_transformers before any eurekaclaw submodule is imported,
# since embedding_utils.py imports it at module level and it may not be installed
# in the test environment.
sys.modules.setdefault("sentence_transformers", MagicMock())

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ResearchBrief


@pytest.fixture
def brief():
    return ResearchBrief(
        session_id="test-session",
        input_mode="exploration",
        domain="bandit theory",
        query="tight regret bounds",
        open_problems=["No tight lower bound for heavy-tailed rewards"],
    )


@pytest.fixture
def bus(brief):
    b = KnowledgeBus(brief.session_id)
    b.put_research_brief(brief)
    return b


def _make_orchestrator(bus):
    """Build a MetaOrchestrator with all heavy dependencies mocked out."""
    from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator

    with patch("eurekaclaw.orchestrator.meta_orchestrator.create_client"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.build_default_registry"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.SkillRegistry"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.SkillInjector"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.MemoryManager"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.SurveyAgent"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.IdeationAgent"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.TheoryAgent"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.ExperimentAgent"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.WriterAgent"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.DivergentConvergentPlanner"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.GateController"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.PipelineManager"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.TaskRouter"), \
         patch("eurekaclaw.orchestrator.meta_orchestrator.ContinualLearningLoop"):
        orch = MetaOrchestrator(bus=bus)
    return orch


@pytest.mark.asyncio
async def test_fallback_called_when_diverge_returns_empty(bus, brief):
    """When diverge() returns [], _handle_manual_direction should be called."""
    orch = _make_orchestrator(bus)
    orch.planner.diverge = AsyncMock(return_value=[])

    with patch.object(orch, "_handle_manual_direction", new_callable=AsyncMock) as mock_manual:
        await orch._handle_direction_gate(brief)
        mock_manual.assert_called_once()


@pytest.mark.asyncio
async def test_fallback_called_when_diverge_raises(bus, brief):
    """When diverge() throws, _handle_manual_direction should be called."""
    orch = _make_orchestrator(bus)
    orch.planner.diverge = AsyncMock(side_effect=RuntimeError("LLM parse error"))

    with patch.object(orch, "_handle_manual_direction", new_callable=AsyncMock) as mock_manual:
        await orch._handle_direction_gate(brief)
        mock_manual.assert_called_once()


@pytest.mark.asyncio
async def test_fallback_not_called_when_diverge_succeeds(bus, brief):
    """When diverge() returns directions normally, no fallback should occur."""
    from eurekaclaw.types.artifacts import ResearchDirection
    orch = _make_orchestrator(bus)

    direction = ResearchDirection(
        direction_id="d1", title="Test", hypothesis="H1",
        novelty_score=0.8, soundness_score=0.8, transformative_score=0.7,
    )
    direction.compute_composite()
    orch.planner.diverge = AsyncMock(return_value=[direction])
    orch.planner.converge = AsyncMock(return_value=direction)

    with patch.object(orch, "_handle_manual_direction", new_callable=AsyncMock) as mock_manual:
        await orch._handle_direction_gate(brief)
        mock_manual.assert_not_called()

    updated = bus.get_research_brief()
    assert updated.selected_direction is not None
    assert updated.selected_direction.direction_id == "d1"


@pytest.mark.asyncio
async def test_manual_direction_sets_brief(bus, brief):
    """User input should be stored as the selected direction on the bus."""
    orch = _make_orchestrator(bus)

    with patch("eurekaclaw.orchestrator.meta_orchestrator.console") as mock_console:
        mock_console.input = MagicMock(return_value="UCB1 achieves O(sqrt(KT log T)) regret")
        await orch._handle_manual_direction(brief)

    updated = bus.get_research_brief()
    assert updated.selected_direction is not None
    assert "UCB1" in updated.selected_direction.hypothesis
    assert len(updated.directions) == 1


@pytest.mark.asyncio
async def test_manual_direction_empty_then_valid_input(bus, brief):
    """Empty input should re-prompt; a valid input on the second try succeeds."""
    orch = _make_orchestrator(bus)

    with patch("eurekaclaw.orchestrator.meta_orchestrator.console") as mock_console:
        mock_console.input = MagicMock(side_effect=["", "UCB1 achieves O(sqrt(KT)) regret"])
        await orch._handle_manual_direction(brief)

    updated = bus.get_research_brief()
    assert updated.selected_direction is not None
    assert "UCB1" in updated.selected_direction.hypothesis


@pytest.mark.asyncio
async def test_manual_direction_ctrl_c_raises(bus, brief):
    """Ctrl+C (KeyboardInterrupt / EOFError) should raise RuntimeError."""
    orch = _make_orchestrator(bus)

    with patch("eurekaclaw.orchestrator.meta_orchestrator.console") as mock_console:
        mock_console.input = MagicMock(side_effect=EOFError)
        with pytest.raises(RuntimeError):
            await orch._handle_manual_direction(brief)


# ---------------------------------------------------------------------------
# Tests specific to "ideation returned 0 directions" in prove / detailed mode
# ---------------------------------------------------------------------------

@pytest.fixture
def detailed_brief():
    """A ResearchBrief simulating the `prove` command (detailed mode)."""
    return ResearchBrief(
        session_id="test-session-detailed",
        input_mode="detailed",
        domain="number theory",
        query="prove 1+1=2",
        conjecture="1+1=2 in Peano arithmetic",
    )


@pytest.fixture
def detailed_bus(detailed_brief):
    b = KnowledgeBus(detailed_brief.session_id)
    b.put_research_brief(detailed_brief)
    return b


@pytest.mark.asyncio
async def test_fallback_called_when_ideation_returns_zero_in_detailed_mode(
    detailed_bus, detailed_brief
):
    """In prove/detailed mode with 0 ideation directions, _handle_manual_direction must be called."""
    orch = _make_orchestrator(detailed_bus)
    # brief.directions is empty — simulates ideation returning 0

    with patch.object(orch, "_handle_manual_direction", new_callable=AsyncMock) as mock_manual:
        await orch._handle_direction_gate(detailed_brief)
        mock_manual.assert_called_once()


@pytest.mark.asyncio
async def test_empty_enter_reprompts_even_with_conjecture(
    detailed_bus, detailed_brief
):
    """In prove mode, pressing Enter (empty input) should re-prompt, not silently accept conjecture."""
    orch = _make_orchestrator(detailed_bus)

    # User presses Enter twice, then types the conjecture explicitly
    with patch("eurekaclaw.orchestrator.meta_orchestrator.console") as mock_console:
        mock_console.input = MagicMock(side_effect=["", "", detailed_brief.conjecture])
        await orch._handle_manual_direction(detailed_brief)

    updated = detailed_bus.get_research_brief()
    assert updated.selected_direction is not None
    assert updated.selected_direction.hypothesis == detailed_brief.conjecture


@pytest.mark.asyncio
async def test_user_can_override_conjecture_in_detailed_mode(
    detailed_bus, detailed_brief
):
    """In prove mode, the user can type a different direction instead of accepting the conjecture."""
    orch = _make_orchestrator(detailed_bus)

    with patch("eurekaclaw.orchestrator.meta_orchestrator.console") as mock_console:
        mock_console.input = MagicMock(return_value="1+1=2 via ZFC set theory")
        await orch._handle_manual_direction(detailed_brief)

    updated = detailed_bus.get_research_brief()
    assert updated.selected_direction is not None
    assert "ZFC" in updated.selected_direction.hypothesis


@pytest.mark.asyncio
async def test_empty_input_no_conjecture_reprompts_then_accepts(bus, brief):
    """Empty input with no conjecture re-prompts; Ctrl+C eventually raises RuntimeError."""
    orch = _make_orchestrator(bus)
    # brief.conjecture is not set in the exploration fixture

    with patch("eurekaclaw.orchestrator.meta_orchestrator.console") as mock_console:
        # Two empty inputs, then Ctrl+C
        mock_console.input = MagicMock(side_effect=["", "", KeyboardInterrupt])
        with pytest.raises(RuntimeError):
            await orch._handle_manual_direction(brief)
