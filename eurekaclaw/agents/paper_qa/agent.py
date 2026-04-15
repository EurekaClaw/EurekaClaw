"""PaperQAAgent — multi-turn QA with tool access and streaming output."""

from __future__ import annotations

import logging
from typing import Any

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.console import console
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)

_SYSTEM_TEMPLATE = (
    "You are a research assistant helping the author respond to questions "
    "about their paper. You have access to tools for searching arXiv, "
    "Semantic Scholar, and the web. You can also read specific sections "
    "of the paper via latex_section_read.\n\n"
    "Give clear, rigorous responses. Reference specific sections, "
    "equations, or theorems from the paper where relevant.\n\n"
    "PAPER (LaTeX source):\n```latex\n{latex}\n```"
)

_MAX_TOOL_ITERATIONS = 5
_MAX_TOOL_RESULT_CHARS = 30_000


class PaperQAAgent(BaseAgent):
    """Multi-turn QA agent with tool access for paper review."""

    role = AgentRole.WRITER

    def get_tool_names(self) -> list[str]:
        return ["arxiv_search", "semantic_scholar", "web_search", "latex_section_read"]

    def _role_system_prompt(self, task: Task) -> str:
        latex = self.bus.get("paper_qa_latex") or ""
        return _SYSTEM_TEMPLATE.format(latex=latex)

    async def execute(self, task: Task) -> AgentResult:
        """Backward-compatible single-turn execute. Delegates to ask()."""
        latex = self.bus.get("paper_qa_latex") or ""
        question = self.bus.get("paper_qa_question") or task.description or ""
        return await self.ask(question=question, latex=latex, history=[], task=task)

    async def ask(
        self,
        question: str,
        latex: str,
        history: list[dict[str, str]],
        task: Task | None = None,
    ) -> AgentResult:
        """Answer a question about the paper with multi-turn context.

        Args:
            question: Current user question.
            latex: Full LaTeX source (placed in system prompt for cache reuse).
            history: Prior QA turns [{"role": "user"|"assistant", "content": ...}].
            task: Optional task for result construction.

        Returns:
            AgentResult with answer in output["answer"].
        """
        if not latex:
            return self._make_qa_result(
                task, success=False, answer="", error="No paper LaTeX provided"
            )
        if not question.strip():
            return self._make_qa_result(
                task, success=False, answer="", error="No question provided"
            )

        system = _SYSTEM_TEMPLATE.format(latex=latex)
        messages = self._build_messages(history, question)
        tools = self.tool_registry.definitions_for(self.get_tool_names())

        try:
            answer = await self._tool_loop(system, messages, tools)
        except Exception as e:
            logger.exception("PaperQAAgent call failed")
            return self._make_qa_result(
                task, success=False, answer="", error=str(e)
            )

        self.bus.put("paper_qa_answer", answer)
        return self._make_qa_result(task, success=True, answer=answer)

    def _build_messages(
        self, history: list[dict[str, str]], question: str
    ) -> list[dict[str, Any]]:
        """Convert QA history + new question into Anthropic messages format."""
        messages: list[dict[str, Any]] = []
        for turn in history:
            messages.append({"role": turn["role"], "content": turn["content"]})
        messages.append({"role": "user", "content": question})
        return messages

    async def _tool_loop(
        self,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
    ) -> str:
        """Call model in a loop, handling tool_use blocks.

        Prints text and tool calls to console for real-time feedback.
        Max _MAX_TOOL_ITERATIONS iterations to prevent runaway loops.
        """
        from eurekaclaw.config import settings

        final_text = ""

        for iteration in range(_MAX_TOOL_ITERATIONS):
            response = await self.client.messages.create(
                model=settings.active_model,
                max_tokens=4096,
                system=system,
                messages=messages,
                tools=tools or None,
            )

            # Collect text and tool_use blocks
            text_parts: list[str] = []
            tool_calls: list[Any] = []
            for block in response.content:
                if block.type == "text":
                    text_parts.append(block.text)
                elif block.type == "tool_use":
                    tool_calls.append(block)

            if text_parts:
                final_text = " ".join(text_parts)
                for part in text_parts:
                    console.print(part, highlight=False)

            # No tool calls — done
            if not tool_calls or response.stop_reason == "end_turn":
                break

            # Serialize assistant turn with tool_use blocks
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
            messages.append({"role": "assistant", "content": serialized})

            # Execute tools
            tool_results: list[dict] = []
            for tc in tool_calls:
                console.print(
                    f"  [dim]tool: {tc.name}({str(tc.input)[:80]})[/dim]",
                    highlight=False,
                )
                result = await self.tool_registry.call(tc.name, tc.input)
                if len(result) > _MAX_TOOL_RESULT_CHARS:
                    result = (
                        result[:_MAX_TOOL_RESULT_CHARS]
                        + "\n\n[... truncated]"
                    )
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": result,
                })
            messages.append({"role": "user", "content": tool_results})

        return final_text

    def _make_qa_result(
        self,
        task: Task | None,
        success: bool,
        answer: str,
        error: str = "",
    ) -> AgentResult:
        """Build AgentResult, handling None task for handler-driven calls."""
        return AgentResult(
            task_id=task.task_id if task else "paper_qa_inline",
            agent_role=self.role,
            success=success,
            output={"answer": answer} if answer else {},
            text_summary=answer[:200] if answer else "",
            error=error,
        )
