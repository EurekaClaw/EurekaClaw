"""Unit tests for the tool registry and built-in tools."""

import pytest

from eurekaclaw.tools.registry import ToolRegistry
from eurekaclaw.tools.base import BaseTool
from eurekaclaw.tools.citation import CitationManagerTool


class MockTool(BaseTool):
    name = "mock_tool"
    description = "A mock tool for testing"

    def input_schema(self):
        return {"type": "object", "properties": {"x": {"type": "string"}}, "required": ["x"]}

    async def call(self, x: str) -> str:
        return f"result: {x}"


@pytest.mark.asyncio
async def test_tool_registry_register_and_call():
    registry = ToolRegistry()
    tool = MockTool()
    registry.register(tool)

    assert "mock_tool" in registry
    assert len(registry) == 1

    result = await registry.call("mock_tool", {"x": "hello"})
    assert result == "result: hello"


@pytest.mark.asyncio
async def test_tool_registry_unknown_tool():
    registry = ToolRegistry()
    result = await registry.call("nonexistent", {})
    assert "Error" in result


def test_tool_to_anthropic_def():
    tool = MockTool()
    defn = tool.to_anthropic_tool_def()
    assert defn["name"] == "mock_tool"
    assert "input_schema" in defn
    assert defn["input_schema"]["required"] == ["x"]


@pytest.mark.asyncio
async def test_citation_manager_generate_bibtex():
    tool = CitationManagerTool()
    result = await tool.call(
        action="generate_bibtex",
        paper_data={
            "title": "Attention Is All You Need",
            "authors": ["Vaswani", "Shazeer"],
            "year": 2017,
            "venue": "NeurIPS",
        },
    )
    import json
    data = json.loads(result)
    assert "bibtex" in data
    assert "vaswani2017" in data["cite_key"]
    assert "@inproceedings" in data["bibtex"]
