"""BaseTool ABC — all tools follow this interface."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, ClassVar


class BaseTool(ABC):
    """All tools inherit from this. They can be registered in ToolRegistry
    and exposed to agents as Anthropic tool-use definitions."""

    name: ClassVar[str]
    description: ClassVar[str]

    @abstractmethod
    def input_schema(self) -> dict[str, Any]:
        """Return JSON Schema for the tool's input parameters."""
        ...

    @abstractmethod
    async def call(self, **kwargs: Any) -> str:
        """Execute the tool. Returns a string result for LLM consumption."""
        ...

    def to_anthropic_tool_def(self) -> dict[str, Any]:
        """Convert to Anthropic tool-use definition format."""
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": self.input_schema(),
        }
