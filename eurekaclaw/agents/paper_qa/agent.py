"""PaperQAAgent — answers user questions about the generated paper."""

from __future__ import annotations

import logging

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)

_SYSTEM = (
    "You are a research assistant helping the author of a paper respond to questions or reviewer "
    "concerns. You will be given the full LaTeX source of the paper and a question. "
    "Give a clear, rigorous, and concise response that the author could use as a rebuttal or "
    "clarification. Reference specific sections or equations from the paper where relevant."
)


class PaperQAAgent(BaseAgent):
    """Single-call agent: reads the paper LaTeX from the bus and answers a question."""

    role = AgentRole.WRITER  # reuse WRITER slot — no new role needed

    def get_tool_names(self) -> list[str]:
        return []

    async def execute(self, task: Task) -> AgentResult:
        latex_paper = self.bus.get("paper_qa_latex") or ""
        question = self.bus.get("paper_qa_question") or task.description or ""

        if not latex_paper:
            return self._make_result(task, False, {}, error="No paper LaTeX found on bus")
        if not question:
            return self._make_result(task, False, {}, error="No question provided")

        user_msg = (
            f"PAPER (LaTeX source):\n```latex\n{latex_paper[:12000]}\n```\n\n"
            f"QUESTION:\n{question}"
        )

        from eurekaclaw.config import settings
        response = await self.client.messages.create(
            model=settings.eurekaclaw_model,
            max_tokens=4096,
            system=_SYSTEM,
            messages=[{"role": "user", "content": user_msg}],
        )

        answer_block = next(
            (b for b in response.content if getattr(b, "type", None) == "text"),
            None,
        )
        answer = answer_block.text if answer_block else ""

        self.bus.put("paper_qa_answer", answer)
        return self._make_result(task, True, {"answer": answer}, text_summary=answer[:200])
