"""ToolRegistry — typed tool definitions and dispatch."""

from __future__ import annotations

import logging
from typing import Any

from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)


class ToolRegistry:
    """Manages all available tools and provides dispatch by name."""

    def __init__(self) -> None:
        self._tools: dict[str, BaseTool] = {}

    def register(self, tool: BaseTool) -> None:
        self._tools[tool.name] = tool
        logger.debug("Registered tool: %s", tool.name)

    def get(self, name: str) -> BaseTool | None:
        return self._tools.get(name)

    def all_definitions(self) -> list[dict[str, Any]]:
        """Return all tool definitions in Anthropic format."""
        return [t.to_anthropic_tool_def() for t in self._tools.values()]

    def definitions_for(self, names: list[str]) -> list[dict[str, Any]]:
        """Return Anthropic-format definitions for a subset of tools by name."""
        return [
            self._tools[n].to_anthropic_tool_def()
            for n in names
            if n in self._tools
        ]

    async def call(self, name: str, inputs: dict[str, Any]) -> str:
        tool = self._tools.get(name)
        if tool is None:
            return f"Error: unknown tool '{name}'"
        try:
            return await tool.call(**inputs)
        except Exception as e:
            logger.exception("Tool %s failed", name)
            return f"Error running tool '{name}': {e}"

    def __contains__(self, name: str) -> bool:
        return name in self._tools

    def __len__(self) -> int:
        return len(self._tools)


def build_default_registry(bus: "KnowledgeBus | None" = None) -> ToolRegistry:
    """Build and return the default tool registry with all built-in (domain-agnostic) tools.

    Domain-specific tools (e.g. run_bandit_experiment) are registered separately
    by DomainPlugin.register_tools() in MetaOrchestrator.__init__().
    """
    from eurekaclaw.tools.arxiv import ArxivSearchTool
    from eurekaclaw.tools.citation import CitationManagerTool
    from eurekaclaw.tools.code_exec import CodeExecutionTool
    from eurekaclaw.tools.lean4 import Lean4Tool
    from eurekaclaw.tools.semantic_scholar import SemanticScholarTool
    from eurekaclaw.tools.web_search import WebSearchTool
    from eurekaclaw.tools.wolfram import WolframAlphaTool

    registry = ToolRegistry()
    for tool in [
        ArxivSearchTool(),
        SemanticScholarTool(),
        WebSearchTool(),
        CodeExecutionTool(),
        Lean4Tool(),
        WolframAlphaTool(),
        CitationManagerTool(),
    ]:
        registry.register(tool)
    if bus is not None:
        from eurekaclaw.tools.latex_section import LatexSectionReadTool
        registry.register(LatexSectionReadTool(bus=bus))
    return registry
