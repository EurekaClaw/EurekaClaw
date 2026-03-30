"""BaseAgent ABC — streaming execution, skill injection, tool-use loop."""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any, AsyncIterator

from tenacity import stop_after_attempt, wait_exponential, Retrying
from tenacity.asyncio import AsyncRetrying

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

_COMPRESS_SYSTEM = (
    "You are a research assistant summarising the progress of an ongoing task. "
    "Produce a concise bullet-point summary (≤8 bullets) that captures: "
    "(1) the original goal, "
    "(2) every important finding or tool result so far, "
    "(3) any decisions already made, "
    "(4) what remains to be done. "
    "Preserve all numbers, citations, and key facts verbatim. "
    "Be brief — this summary replaces a long tool-call history."
)


class BaseAgent(ABC):
    """All specialized agents inherit from this.

    Provides:
    - Streaming LLM calls via Anthropic API
    - Tool-use loop with automatic dispatch
    - Skill injection into system prompt
    - Session-based context management
    - Periodic context compression to keep the window manageable
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
        brief = self.bus.get_research_brief()
        selected_skill_names = brief.selected_skills if brief else []
        selected_skills = []
        seen: set[str] = set()

        for name in selected_skill_names:
            skill = self.skill_injector.registry.get(name)
            if not skill:
                continue
            if skill.meta.agent_roles and self.role.value not in skill.meta.agent_roles:
                continue
            selected_skills.append(skill)
            seen.add(skill.meta.name)

        auto_skills = self.skill_injector.top_k(task=task, role=self.role.value, k=5)
        skills = selected_skills[:5]
        for skill in auto_skills:
            if skill.meta.name in seen:
                continue
            skills.append(skill)
            seen.add(skill.meta.name)
            if len(skills) >= 5:
                break

        skill_block = self.skill_injector.render_for_prompt(skills)
        # Record injected skill names on bus so learning loop can update stats
        if skills:
            existing: set = self.bus.get("injected_skills") or set()
            existing.update(s.meta.name for s in skills)
            self.bus.put("injected_skills", existing)
        base = self._role_system_prompt(task)
        parts = [base]
        if skill_block:
            parts.append(skill_block)
        workflow_hint: str = self.bus.get("domain_workflow_hint") or ""
        if workflow_hint:
            parts.append(f"<domain_guidance>\n{workflow_hint}\n</domain_guidance>")
        return "\n\n".join(parts)

    @abstractmethod
    def _role_system_prompt(self, task: Task) -> str:
        """Role-specific system prompt content."""
        ...

    async def run_agent_loop(
        self,
        task: Task,
        initial_user_message: str,
        max_turns: int | None = None,
        max_tokens: int | None = None,
    ) -> tuple[str, dict[str, int]]:
        """Run the full agent loop with tool-use until the model stops.

        Context compression is triggered every ``context_compress_after_turns``
        turns. The fast model summarises accumulated history into a short bullet
        list, reducing input tokens for long-running agents.
        """
        from eurekaclaw.config import settings
        _max_turns = max_turns if max_turns is not None else settings.theory_stage_max_turns
        compress_every = settings.context_compress_after_turns  # 0 = disabled

        system = self.build_system_prompt(task)
        tools = self.tool_registry.definitions_for(self.get_tool_names())
        self.session.clear()
        self.session.add_user(initial_user_message)

        from eurekaclaw.llm.base import get_global_tokens
        _token_start = get_global_tokens()
        final_text = ""

        for turn in range(_max_turns):
            # --- Periodic context compression ---
            if (
                compress_every > 0
                and turn > 0
                and turn % compress_every == 0
                and len(self.session) > compress_every
            ):
                summary = await self._compress_history()
                self.session.compress_to_summary(initial_user_message, summary)
                logger.debug(
                    "[%s] Context compressed at turn %d (session → 1 message)",
                    self.role.value, turn,
                )

            response = await self._call_model(
                system=system,
                messages=self.session.get_messages(),
                tools=tools,
                max_tokens=max_tokens,
            )

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
            # Cap each tool result to ~7.5k tokens to prevent context window overflow.
            _MAX_TOOL_RESULT_CHARS = 30_000
            tool_results = []
            for tool_call in tool_calls:
                logger.debug("Tool call: %s(%s)", tool_call.name, tool_call.input)
                result = await self.tool_registry.call(tool_call.name, tool_call.input)
                if len(result) > _MAX_TOOL_RESULT_CHARS:
                    result = result[:_MAX_TOOL_RESULT_CHARS] + "\n\n[... truncated — result too large for context window]"
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

        _token_end = get_global_tokens()
        total_tokens = {
            "input": _token_end["input"] - _token_start["input"],
            "output": _token_end["output"] - _token_start["output"],
        }
        return final_text, total_tokens

    async def _compress_history(self) -> str:
        """Use the fast model to summarise the current conversation history."""
        from eurekaclaw.config import settings

        msgs = self.session.get_messages()
        lines: list[str] = []
        for m in msgs[-12:]:
            role = m["role"].upper()
            content = m["content"]
            if isinstance(content, list):
                parts = []
                for block in content:
                    if isinstance(block, dict):
                        if block.get("type") == "text":
                            parts.append(block.get("text", "")[:300])
                        elif block.get("type") == "tool_use":
                            parts.append(f"[tool:{block.get('name')}({str(block.get('input', ''))[:150]})]")
                        elif block.get("type") == "tool_result":
                            parts.append(f"[result:{str(block.get('content', ''))[:300]}]")
                content_str = " ".join(parts)
            else:
                content_str = str(content)[:600]
            lines.append(f"{role}: {content_str}")

        history_text = "\n".join(lines)
        try:
            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=settings.max_tokens_compress,
                system=_COMPRESS_SYSTEM,
                messages=[{"role": "user", "content": f"Conversation so far:\n{history_text}\n\nWrite the progress summary now."}],
            )
            if not response.content:
                raise ValueError("LLM returned empty content list")
            return response.content[0].text
        except Exception as e:
            logger.warning("Context compression LLM call failed (%s) — using fallback", e)
            summaries = [
                str(m["content"])[:200]
                for m in msgs
                if m["role"] == "assistant" and isinstance(m["content"], str)
            ]
            if not summaries:
                return "No intermediate findings recorded yet. Continue working on the task."
            return "Previous findings: " + " | ".join(summaries[-3:])

    async def _call_model(
        self,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        max_tokens: int | None = None,
    ) -> NormalizedMessage:
        from eurekaclaw.config import settings
        _max_tokens = max_tokens if max_tokens is not None else settings.max_tokens_agent
        async for attempt in AsyncRetrying(
            stop=stop_after_attempt(settings.llm_retry_attempts),
            wait=wait_exponential(
                min=settings.llm_retry_wait_min,
                max=settings.llm_retry_wait_max,
            ),
            reraise=True,
        ):
            with attempt:
                try:
                    return await self.client.messages.create(
                        model=settings.active_model,
                        max_tokens=_max_tokens,
                        system=system,
                        messages=messages,
                        tools=tools or None,
                    )
                except Exception as e:
                    logger.error(
                        "LLM call failed (model=%s): %s: %s",
                        settings.active_model, type(e).__name__, e,
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
