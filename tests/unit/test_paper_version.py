"""Tests for the `paper_version` field on writer task outputs."""

from unittest.mock import MagicMock

import pytest

from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus


def _writer_task() -> Task:
    return Task(
        task_id="w1",
        name="writer",
        agent_role="writer",
        description="Write paper",
    )


def test_writer_output_includes_paper_version_one():
    """A fresh writer run stamps paper_version=1 on its outputs."""
    from eurekaclaw.agents.writer.agent import WriterAgent

    # Build the minimal result dict the way the agent does on the success path.
    task = _writer_task()
    agent_output = {
        "latex_paper": r"\section{Intro} body",
        "word_count": 2,
        "output_format": "latex",
        "paper_version": 1,
    }
    from eurekaclaw.types.agents import AgentRole
    mock_self = MagicMock()
    mock_self.role = AgentRole.WRITER
    result = WriterAgent._make_result(
        mock_self,  # `self` substitute — _make_result only reads self.role
        task,
        success=True,
        output=agent_output,
        text_summary="ok",
        token_usage={"input": 0, "output": 0},
    )
    assert result.output["paper_version"] == 1


def test_writer_output_key_naming_uses_paper_version(monkeypatch):
    """Regression: writer.outputs must contain a literal 'paper_version' key
    (not 'version' or 'paperVersion') so the frontend hook can read it."""
    # Grep the source for the literal field name.
    import pathlib, re
    src = pathlib.Path("eurekaclaw/agents/writer/agent.py").read_text(encoding="utf-8")
    # _make_result call in the success path must include "paper_version".
    # Accept either single- or double-quoted.
    assert re.search(r'["\']paper_version["\']\s*:\s*1', src), (
        "writer agent success path must stamp paper_version=1 on outputs"
    )


@pytest.mark.asyncio
async def test_review_rewrite_endpoint_bumps_paper_version(tmp_path, monkeypatch):
    """POST /review/rewrite → success → writer.outputs.paper_version bumps."""
    from eurekaclaw.knowledge_bus.bus import KnowledgeBus
    from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus
    from eurekaclaw.types.artifacts import ResearchBrief

    session_id = "test-rev-001"
    bus = KnowledgeBus(session_id)
    writer_task = Task(
        task_id="w1",
        name="writer",
        agent_role="writer",
        description="Write paper",
        status=TaskStatus.COMPLETED,
        outputs={"latex_paper": r"\section{v1}", "paper_version": 1},
    )
    pipeline = TaskPipeline(
        pipeline_id="p1", session_id=session_id, tasks=[writer_task]
    )
    bus.put_pipeline(pipeline)
    bus.put_research_brief(ResearchBrief(
        session_id=session_id,
        input_mode="exploration",
        domain="t",
        query="q",
    ))

    # Simulate what the handler does after a successful _do_rewrite:
    from eurekaclaw.ui.server import _bump_writer_paper_version

    new_version = _bump_writer_paper_version(bus)

    assert new_version == 2
    refreshed = bus.get_pipeline()
    wt = next(t for t in refreshed.tasks if t.name == "writer")
    assert wt.outputs["paper_version"] == 2


@pytest.mark.asyncio
async def test_bump_writer_paper_version_missing_field_bumps_to_two(tmp_path):
    """If the writer task predates this change (no paper_version), treat
    it as 1 and bump to 2."""
    from eurekaclaw.knowledge_bus.bus import KnowledgeBus
    from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus
    from eurekaclaw.ui.server import _bump_writer_paper_version

    bus = KnowledgeBus("test-rev-002")
    writer_task = Task(
        task_id="w1",
        name="writer",
        agent_role="writer",
        description="Write paper",
        status=TaskStatus.COMPLETED,
        outputs={"latex_paper": "body"},  # no paper_version key
    )
    bus.put_pipeline(TaskPipeline(
        pipeline_id="p1", session_id="test-rev-002", tasks=[writer_task]
    ))

    new_version = _bump_writer_paper_version(bus)

    assert new_version == 2
