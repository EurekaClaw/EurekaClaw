"""BaseAgent ABC — streaming execution, skill injection, tool-use loop."""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any, AsyncIterator

from tenacity import retry, stop_after_attempt, wait_exponential

from eurekaclaw.agents.session import AgentSession
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.llm.types import NormalizedMessage
from eurekaclaw.memory.manager import MemoryManager
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.tools.registry import ToolRegistry
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


class BaseAgent(ABC):
    """All specialized agents inherit from this.

    Provides:
    - Streaming LLM calls via Anthropic API
    - Tool-use loop with automatic dispatch
    - Skill injection into system prompt
    - Session-based context management
    - Retry with exponential backoff
    """

    role: AgentRole

    def __init__(
        self,
        bus: KnowledgeBus,
        tool_registry: ToolRegistry,
        skill_injector: SkillInjector,
        memory: MemoryManager,
        client: LLMClient | None = None,
    ) -> None:
        self.bus = bus
        self.tool_registry = tool_registry
        self.skill_injector = skill_injector
        self.memory = memory
        self.client: LLMClient = client or create_client()
        self.session = AgentSession()

    @abstractmethod
    async def execute(self, task: Task) -> AgentResult:
        """Execute the given task. Must return an AgentResult."""
        ...

    @abstractmethod
    def get_tool_names(self) -> list[str]:
        """Return the names of tools this agent is allowed to use."""
        ...

    def build_system_prompt(self, task: Task) -> str:
        """Construct system prompt = role description + injected skills."""
        skills = self.skill_injector.top_k(task=task, role=self.role.value, k=5)
        skill_block = self.skill_injector.render_for_prompt(skills)
        base = self._role_system_prompt(task)
        if skill_block:
            return f"{base}\n\n{skill_block}"
        return base

    @abstractmethod
    def _role_system_prompt(self, task: Task) -> str:
        """Role-specific system prompt content."""
        ...

    async def run_agent_loop(
        self,
        task: Task,
        initial_user_message: str,
        max_turns: int = 20,
    ) -> tuple[str, dict[str, int]]:
        """Run the full agent loop with tool-use until the model stops."""
        system = self.build_system_prompt(task)
        tools = self.tool_registry.definitions_for(self.get_tool_names())
        self.session.clear()
        self.session.add_user(initial_user_message)

        total_tokens: dict[str, int] = {"input": 0, "output": 0}
        final_text = ""

        for turn in range(max_turns):
            response = await self._call_model(
                system=system,
                messages=self.session.get_messages(),
                tools=tools,
            )
            if response.usage:
                total_tokens["input"] += response.usage.input_tokens
                total_tokens["output"] += response.usage.output_tokens

            # Collect text content
            text_parts = []
            tool_calls = []
            for block in response.content:
                if block.type == "text":
                    text_parts.append(block.text)
                elif block.type == "tool_use":
                    tool_calls.append(block)

            if text_parts:
                final_text = " ".join(text_parts)

            # Add assistant turn to history with properly serialized content blocks.
            # The Anthropic API requires tool_use turns to carry the full content
            # block list (text + tool_use dicts), not a plain Python repr string.
            if tool_calls:
                serialized: list[dict] = []
                for block in response.content:
                    if block.type == "text":
                        serialized.append({"type": "text", "text": block.text})
                    elif block.type == "tool_use":
                        serialized.append({
                            "type": "tool_use",
                            "id": block.id,
                            "name": block.name,
                            "input": block.input,
                        })
                self.session.add_assistant(serialized)
            else:
                self.session.add_assistant(final_text)

            # If no tool calls, we're done
            if response.stop_reason == "end_turn" or not tool_calls:
                break

            # Execute tools and continue
            tool_results = []
            for tool_call in tool_calls:
                logger.debug("Tool call: %s(%s)", tool_call.name, tool_call.input)
                result = await self.tool_registry.call(tool_call.name, tool_call.input)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_call.id,
                    "content": result,
                })
                self.memory.log_event(
                    self.role.value,
                    f"Tool {tool_call.name}: {result[:200]}",
                )

            # Add tool results as user message
            self.session._messages.append({"role": "user", "content": tool_results})
            self.session.trim_to_fit()

        return final_text, total_tokens

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=30))
    async def _call_model(
        self,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> NormalizedMessage:
        from eurekaclaw.config import settings
        try:
            return await self.client.messages.create(
                model=settings.eurekaclaw_model,
                max_tokens=8192,
                system=system,
                messages=messages,
                tools=tools or None,
            )
        except Exception as e:
            # Log the real error body before tenacity swallows it into RetryError
            logger.error(
                "LLM call failed (model=%s): %s: %s",
                settings.eurekaclaw_model, type(e).__name__, e,
            )
            raise

    def _make_result(
        self,
        task: Task,
        success: bool,
        output: dict[str, Any],
        text_summary: str = "",
        error: str = "",
        token_usage: dict[str, int] | None = None,
    ) -> AgentResult:
        return AgentResult(
            task_id=task.task_id,
            agent_role=self.role,
            success=success,
            output=output,
            text_summary=text_summary,
            error=error,
            token_usage=token_usage or {},
        )
