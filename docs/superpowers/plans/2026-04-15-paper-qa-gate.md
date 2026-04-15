# Paper QA Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add interactive post-writer paper review with multi-turn QA, tool-equipped agent, and unlimited rewrite cycles to the CLI pipeline.

**Architecture:** Extract gate logic from MetaOrchestrator into a dedicated `PaperQAHandler` module. Enhance `PaperQAAgent` with tools (arxiv, web_search, semantic_scholar, latex_section_read), multi-turn history, and streaming. Add paper versioning, QA history persistence, and rewrite failure recovery.

**Tech Stack:** Python 3.11, Rich (CLI prompts/panels), Anthropic API (streaming), JSONL persistence

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `eurekaclaw/tools/latex_section.py` | Create | `latex_section_read` tool — parse LaTeX and extract sections by name/number |
| `eurekaclaw/tools/registry.py` | Modify | Register `LatexSectionReadTool` in `build_default_registry()` |
| `eurekaclaw/agents/paper_qa/agent.py` | Modify | Add tools, multi-turn `ask()` method, streaming tool loop |
| `eurekaclaw/orchestrator/paper_qa_handler.py` | Create | Gate interaction controller — CLI prompts, QA loop, rewrite loop, persistence |
| `eurekaclaw/orchestrator/meta_orchestrator.py` | Modify | Replace `_handle_paper_qa_gate` body with handler delegation |
| `eurekaclaw/ui/review_gate.py` | Modify | Add `reset_paper_qa()` for rewrite re-arm |
| `tests/unit/test_latex_section.py` | Create | Unit tests for LaTeX section parsing |
| `tests/unit/test_paper_qa_handler.py` | Create | Unit tests for handler flow logic |
| `tests/unit/test_paper_qa_agent.py` | Create | Unit tests for enhanced QA agent |

---

### Task 1: `latex_section_read` Tool — Tests

**Files:**
- Create: `tests/unit/test_latex_section.py`

- [ ] **Step 1: Write tests for LaTeX section extraction**

```python
"""Unit tests for LatexSectionReadTool section parsing."""

import pytest

from eurekaclaw.tools.latex_section import LatexSectionReadTool


SAMPLE_LATEX = r"""
\documentclass{article}
\title{Test Paper}
\begin{document}

\section{Introduction}
This is the introduction with some background.
We study convergence of spectral methods.

\section{Preliminaries}
\subsection{Notation}
Let $G = (V, E)$ be a graph.

\subsection{Key Definitions}
We define the Laplacian $L = D - A$.

\section{Main Results}
\subsection{Theorem 1}
The spectral gap satisfies $\lambda_2 \geq \frac{1}{n}$.

\begin{proof}
By Cheeger's inequality...
\end{proof}

\subsection{Theorem 2}
The bound is tight for regular graphs.

\section{Experiments}
We validate on random graphs.

\section{Conclusion}
We proved tight bounds on spectral gaps.

\end{document}
"""


@pytest.fixture
def tool(bus):
    bus.put("paper_qa_latex", SAMPLE_LATEX)
    return LatexSectionReadTool(bus=bus)


@pytest.mark.asyncio
async def test_extract_section_by_name(tool):
    result = await tool.call(section="Introduction")
    assert "convergence of spectral methods" in result
    assert "Notation" not in result


@pytest.mark.asyncio
async def test_extract_section_by_number(tool):
    result = await tool.call(section="3")
    assert "Theorem 1" in result
    assert "spectral gap" in result


@pytest.mark.asyncio
async def test_extract_subsection_by_name(tool):
    result = await tool.call(section="Notation")
    assert "Let $G = (V, E)$" in result


@pytest.mark.asyncio
async def test_extract_subsection_by_dotted_number(tool):
    result = await tool.call(section="2.1")
    assert "Let $G = (V, E)$" in result


@pytest.mark.asyncio
async def test_no_match_returns_available_sections(tool):
    result = await tool.call(section="Nonexistent")
    assert "Introduction" in result
    assert "Main Results" in result


@pytest.mark.asyncio
async def test_case_insensitive_match(tool):
    result = await tool.call(section="introduction")
    assert "convergence of spectral methods" in result


@pytest.mark.asyncio
async def test_no_latex_on_bus(bus):
    tool = LatexSectionReadTool(bus=bus)
    result = await tool.call(section="Introduction")
    assert "Error" in result or "no paper" in result.lower()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_latex_section.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eurekaclaw.tools.latex_section'`

- [ ] **Step 3: Commit test file**

```bash
git add tests/unit/test_latex_section.py
git commit -m "test: add unit tests for latex_section_read tool"
```

---

### Task 2: `latex_section_read` Tool — Implementation

**Files:**
- Create: `eurekaclaw/tools/latex_section.py`

- [ ] **Step 1: Implement LatexSectionReadTool**

```python
"""latex_section_read tool — extract sections from paper LaTeX by name or number."""

from __future__ import annotations

import re
import logging
from typing import Any

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)

# Regex matching \section{...}, \subsection{...}, \subsubsection{...}
_HEADING_RE = re.compile(
    r"\\(section|subsection|subsubsection)\*?\{([^}]+)\}",
)

_LEVEL = {"section": 0, "subsection": 1, "subsubsection": 2}


class LatexSectionReadTool(BaseTool):
    """Read a specific section from the paper LaTeX source by name or number."""

    name = "latex_section_read"
    description = (
        "Read a specific section from the paper's LaTeX source. "
        "Pass a section name (e.g. 'Introduction', 'Theorem 2') or "
        "number (e.g. '3', '3.1'). Returns the LaTeX content of that section."
    )

    def __init__(self, bus: KnowledgeBus) -> None:
        self.bus = bus

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "section": {
                    "type": "string",
                    "description": (
                        "Section name (e.g. 'Introduction', 'Theorem 2') "
                        "or number (e.g. '3', '3.1') to extract."
                    ),
                },
            },
            "required": ["section"],
        }

    async def call(self, section: str) -> str:
        latex = self.bus.get("paper_qa_latex") or ""
        if not latex:
            return "Error: no paper LaTeX available on the bus."
        return self._extract_section(latex, section.strip())

    # ------------------------------------------------------------------
    # Parsing
    # ------------------------------------------------------------------

    def _extract_section(self, latex: str, query: str) -> str:
        headings = self._parse_headings(latex)
        if not headings:
            return "No sections found in the LaTeX source."

        # Try matching by dotted number (e.g. "3", "2.1")
        match_idx = self._match_by_number(headings, query)
        if match_idx is None:
            # Try matching by name (case-insensitive substring)
            match_idx = self._match_by_name(headings, query)

        if match_idx is None:
            names = [h["title"] for h in headings]
            return (
                f"No section matching '{query}'. "
                f"Available sections: {', '.join(names)}"
            )

        return self._slice_content(latex, headings, match_idx)

    def _parse_headings(self, latex: str) -> list[dict]:
        """Return list of {level, title, number, start_pos}."""
        headings: list[dict] = []
        counters = [0, 0, 0]  # section, subsection, subsubsection

        for m in _HEADING_RE.finditer(latex):
            level = _LEVEL[m.group(1)]
            title = m.group(2).strip()

            # Increment counter at this level, reset deeper levels
            counters[level] += 1
            for deeper in range(level + 1, 3):
                counters[deeper] = 0

            # Build dotted number: "3" or "3.1" or "3.1.2"
            parts = [str(counters[i]) for i in range(level + 1)]
            number = ".".join(parts)

            headings.append({
                "level": level,
                "title": title,
                "number": number,
                "start": m.start(),
            })
        return headings

    def _match_by_number(self, headings: list[dict], query: str) -> int | None:
        # Check if query looks like a number pattern
        if not re.match(r"^\d+(\.\d+)*$", query):
            return None
        for i, h in enumerate(headings):
            if h["number"] == query:
                return i
        return None

    def _match_by_name(self, headings: list[dict], query: str) -> int | None:
        q = query.lower()
        for i, h in enumerate(headings):
            if q == h["title"].lower():
                return i
        # Fallback: substring match
        for i, h in enumerate(headings):
            if q in h["title"].lower():
                return i
        return None

    def _slice_content(self, latex: str, headings: list[dict], idx: int) -> str:
        """Extract content from the matched heading to the next same-or-higher-level heading."""
        start = headings[idx]["start"]
        level = headings[idx]["level"]

        # Find the end: next heading at same or higher level
        end = len(latex)
        for h in headings[idx + 1:]:
            if h["level"] <= level:
                end = h["start"]
                break

        return latex[start:end].strip()
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_latex_section.py -v`
Expected: All 7 tests PASS

- [ ] **Step 3: Commit**

```bash
git add eurekaclaw/tools/latex_section.py
git commit -m "feat: add latex_section_read tool for targeted section extraction"
```

---

### Task 3: Register `latex_section_read` in Tool Registry

**Files:**
- Modify: `eurekaclaw/tools/registry.py:55-81`

- [ ] **Step 1: Add LatexSectionReadTool to build_default_registry**

The tool needs a `bus` parameter, but `build_default_registry()` doesn't have access to one. Add an optional `bus` parameter:

In `eurekaclaw/tools/registry.py`, replace the function `build_default_registry` (lines 55-80):

```python
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
```

- [ ] **Step 2: Update MetaOrchestrator to pass bus to build_default_registry**

In `eurekaclaw/orchestrator/meta_orchestrator.py`, line 54, change:

```python
# Before:
self.tool_registry = tool_registry or build_default_registry()

# After:
self.tool_registry = tool_registry or build_default_registry(bus=bus)
```

- [ ] **Step 3: Run existing tool tests to verify no regressions**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_tools.py -v`
Expected: All existing tests PASS (they don't pass bus, so latex_section_read is simply not registered — backward compatible)

- [ ] **Step 4: Commit**

```bash
git add eurekaclaw/tools/registry.py eurekaclaw/orchestrator/meta_orchestrator.py
git commit -m "feat: register latex_section_read tool in default registry"
```

---

### Task 4: Enhanced PaperQAAgent — Tests

**Files:**
- Create: `tests/unit/test_paper_qa_agent.py`

- [ ] **Step 1: Write tests for enhanced PaperQAAgent**

```python
"""Unit tests for enhanced PaperQAAgent with multi-turn and tool support."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from eurekaclaw.agents.paper_qa.agent import PaperQAAgent
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.tools.registry import ToolRegistry
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.memory.manager import MemoryManager


@pytest.fixture
def qa_setup(bus, session_id):
    """Set up PaperQAAgent with mocked LLM client."""
    bus.put("paper_qa_latex", r"\section{Intro}\nSome content.")
    tool_reg = ToolRegistry()
    skill_reg = SkillRegistry()
    injector = SkillInjector(skill_reg)
    memory = MemoryManager(session_id=session_id)

    mock_client = MagicMock()
    agent = PaperQAAgent(
        bus=bus,
        tool_registry=tool_reg,
        skill_injector=injector,
        memory=memory,
        client=mock_client,
    )
    return agent, mock_client


def _make_text_response(text: str):
    """Create a mock Anthropic response with a single text block."""
    block = MagicMock()
    block.type = "text"
    block.text = text
    response = MagicMock()
    response.content = [block]
    response.stop_reason = "end_turn"
    return response


def test_get_tool_names_includes_external_tools(qa_setup):
    agent, _ = qa_setup
    names = agent.get_tool_names()
    assert "arxiv_search" in names
    assert "semantic_scholar" in names
    assert "web_search" in names
    assert "latex_section_read" in names


@pytest.mark.asyncio
async def test_ask_returns_answer(qa_setup):
    agent, mock_client = qa_setup
    mock_client.messages.create = AsyncMock(
        return_value=_make_text_response("The bound follows from Jensen's inequality.")
    )

    result = await agent.ask(
        question="Why is the bound O(n^2)?",
        latex=r"\section{Intro}\nContent here.",
        history=[],
    )
    assert result.success
    assert "Jensen" in result.output["answer"]


@pytest.mark.asyncio
async def test_ask_passes_history(qa_setup):
    agent, mock_client = qa_setup
    mock_client.messages.create = AsyncMock(
        return_value=_make_text_response("Yes, regularity helps.")
    )

    history = [
        {"role": "user", "content": "Is the bound tight?"},
        {"role": "assistant", "content": "Not for regular graphs."},
    ]
    result = await agent.ask(
        question="Can we use regularity?",
        latex=r"\section{Intro}\nContent.",
        history=history,
    )
    assert result.success

    # Verify the messages sent to the LLM include history + new question
    call_kwargs = mock_client.messages.create.call_args
    messages = call_kwargs.kwargs.get("messages") or call_kwargs[1].get("messages")
    assert len(messages) == 3  # 2 history + 1 new question
    assert messages[0]["content"] == "Is the bound tight?"
    assert messages[2]["content"] == "Can we use regularity?"


@pytest.mark.asyncio
async def test_ask_empty_latex_fails(qa_setup):
    agent, _ = qa_setup
    result = await agent.ask(question="Hello?", latex="", history=[])
    assert result.failed
    assert "LaTeX" in result.error


@pytest.mark.asyncio
async def test_ask_empty_question_fails(qa_setup):
    agent, _ = qa_setup
    result = await agent.ask(question="", latex="some latex", history=[])
    assert result.failed
    assert "question" in result.error.lower()


@pytest.mark.asyncio
async def test_execute_backward_compat(qa_setup):
    """execute() should delegate to ask() for backward compatibility."""
    agent, mock_client = qa_setup
    mock_client.messages.create = AsyncMock(
        return_value=_make_text_response("Answer from execute path.")
    )

    from eurekaclaw.types.tasks import Task
    task = Task(
        task_id="t1",
        name="paper_qa",
        agent_role="writer",
        description="What is the main result?",
    )
    result = await agent.execute(task)
    assert result.success
    assert "execute path" in result.output["answer"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_paper_qa_agent.py -v`
Expected: FAIL — `PaperQAAgent` has no `ask` method yet

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_paper_qa_agent.py
git commit -m "test: add unit tests for enhanced PaperQAAgent"
```

---

### Task 5: Enhanced PaperQAAgent — Implementation

**Files:**
- Modify: `eurekaclaw/agents/paper_qa/agent.py`

- [ ] **Step 1: Rewrite PaperQAAgent with multi-turn ask() and tool support**

Replace the entire contents of `eurekaclaw/agents/paper_qa/agent.py`:

```python
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

        Streams text tokens to the console for real-time feedback.
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
                # Print answer text to console for real-time feedback
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_paper_qa_agent.py -v`
Expected: All 7 tests PASS

- [ ] **Step 3: Also run latex_section tests to check no regressions**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_latex_section.py tests/unit/test_paper_qa_agent.py -v`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add eurekaclaw/agents/paper_qa/agent.py
git commit -m "feat: enhance PaperQAAgent with tools, multi-turn history, and streaming"
```

---

### Task 6: Add `reset_paper_qa` to review_gate.py

**Files:**
- Modify: `eurekaclaw/ui/review_gate.py:165-204`

- [ ] **Step 1: Add reset_paper_qa function**

In `eurekaclaw/ui/review_gate.py`, insert after `submit_paper_qa` (after line 194), before the Cleanup section:

```python
def reset_paper_qa(session_id: str) -> None:
    """Re-arm the paper QA gate for another review round after rewrite."""
    with _lock:
        if session_id in _paper_qa:
            _paper_qa[session_id] = _GateEntry()
```

- [ ] **Step 2: Run existing gate tests**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/test_gates.py -v`
Expected: PASS (no regressions)

- [ ] **Step 3: Commit**

```bash
git add eurekaclaw/ui/review_gate.py
git commit -m "feat: add reset_paper_qa for rewrite re-arm"
```

---

### Task 7: PaperQAHandler — Tests

**Files:**
- Create: `tests/unit/test_paper_qa_handler.py`

- [ ] **Step 1: Write tests for handler flow logic**

```python
"""Unit tests for PaperQAHandler — CLI interaction flow."""

import json
import pytest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus
from eurekaclaw.types.artifacts import ResearchBrief


@pytest.fixture
def handler_setup(bus, session_id, tmp_path):
    """Build a PaperQAHandler with mocked dependencies."""
    # Create a pipeline with a completed writer task
    writer_task = Task(
        task_id="w1",
        name="writer",
        agent_role="writer",
        description="Write paper",
        status=TaskStatus.COMPLETED,
        outputs={"latex_paper": r"\section{Intro}\nTest paper content."},
    )
    qa_gate_task = Task(
        task_id="g1",
        name="paper_qa_gate",
        agent_role="orchestrator",
        description="Paper QA gate",
    )
    pipeline = TaskPipeline(
        pipeline_id="p1",
        session_id=session_id,
        tasks=[writer_task, qa_gate_task],
    )

    brief = ResearchBrief(
        session_id=session_id,
        input_mode="exploration",
        domain="test",
        query="test query",
    )

    handler = PaperQAHandler(
        bus=bus,
        agents={},
        router=MagicMock(),
        client=MagicMock(),
        tool_registry=MagicMock(),
        skill_injector=MagicMock(),
        memory=MagicMock(),
        gate_controller=MagicMock(),
    )
    # Override session dir to tmp_path for test isolation
    handler._session_dir = tmp_path

    return handler, pipeline, brief


@pytest.mark.asyncio
async def test_skip_when_user_declines(handler_setup):
    handler, pipeline, brief = handler_setup
    with patch.object(handler, "_should_review", return_value=False):
        await handler.run(pipeline, brief)
    # Should save v1 but not enter QA loop
    assert handler._paper_version == 1


@pytest.mark.asyncio
async def test_accept_without_questions(handler_setup):
    handler, pipeline, brief = handler_setup
    with (
        patch.object(handler, "_should_review", return_value=True),
        patch.object(handler, "_display_latex_preview"),
        patch.object(handler, "_prompt_question", return_value=""),
    ):
        await handler.run(pipeline, brief)
    assert handler._paper_version == 1


@pytest.mark.asyncio
async def test_qa_history_persisted(handler_setup):
    handler, pipeline, brief = handler_setup

    # Simulate: user asks one question, then accepts
    question_calls = iter(["What is the main result?", ""])
    choice_calls = iter(["a"])

    mock_result = MagicMock()
    mock_result.success = True
    mock_result.output = {"answer": "The main result is..."}
    mock_result.failed = False

    with (
        patch.object(handler, "_should_review", return_value=True),
        patch.object(handler, "_display_latex_preview"),
        patch.object(handler, "_prompt_question", side_effect=lambda: next(question_calls)),
        patch.object(handler, "_ask_qa_agent", new_callable=AsyncMock, return_value="The main result is..."),
        patch.object(handler, "_prompt_after_answer", side_effect=lambda: next(choice_calls)),
    ):
        await handler.run(pipeline, brief)

    # Check history file was written
    history_file = handler._session_dir / "paper_qa_history.jsonl"
    assert history_file.exists()
    lines = history_file.read_text().strip().split("\n")
    assert len(lines) == 2  # one user turn + one assistant turn
    assert json.loads(lines[0])["role"] == "user"
    assert json.loads(lines[1])["role"] == "assistant"


@pytest.mark.asyncio
async def test_paper_version_saved(handler_setup):
    handler, pipeline, brief = handler_setup
    with patch.object(handler, "_should_review", return_value=False):
        await handler.run(pipeline, brief)
    v1_file = handler._session_dir / "paper_v1.tex"
    assert v1_file.exists()
    assert "Test paper content" in v1_file.read_text()


@pytest.mark.asyncio
async def test_no_latex_skips_gracefully(handler_setup):
    handler, pipeline, brief = handler_setup
    # Remove latex from writer outputs
    pipeline.tasks[0].outputs = {}
    with patch.object(handler, "_should_review", return_value=True):
        await handler.run(pipeline, brief)
    assert handler._paper_version == 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_paper_qa_handler.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eurekaclaw.orchestrator.paper_qa_handler'`

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_paper_qa_handler.py
git commit -m "test: add unit tests for PaperQAHandler flow logic"
```

---

### Task 8: PaperQAHandler — Implementation

**Files:**
- Create: `eurekaclaw/orchestrator/paper_qa_handler.py`

- [ ] **Step 1: Implement PaperQAHandler**

```python
"""PaperQAHandler — interactive paper review gate with QA and rewrite loops."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from rich.panel import Panel
from rich.prompt import Confirm

from eurekaclaw.agents.paper_qa.agent import PaperQAAgent
from eurekaclaw.config import settings
from eurekaclaw.console import console
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient
from eurekaclaw.memory.manager import MemoryManager
from eurekaclaw.orchestrator.gate import GateController
from eurekaclaw.orchestrator.router import TaskRouter
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.tools.registry import ToolRegistry
from eurekaclaw.types.agents import AgentRole, BaseAgent
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import Task, TaskPipeline, TaskStatus

logger = logging.getLogger(__name__)


class PaperQAHandler:
    """Encapsulates the full Paper QA Gate flow for CLI (and later UI).

    Manages two nested loops:
    - Outer loop: review paper → optionally rewrite → review again
    - Inner loop: ask questions → QA agent answers → decide next action
    """

    def __init__(
        self,
        bus: KnowledgeBus,
        agents: dict[AgentRole, BaseAgent],
        router: TaskRouter,
        client: LLMClient,
        tool_registry: ToolRegistry,
        skill_injector: SkillInjector,
        memory: MemoryManager,
        gate_controller: GateController,
    ) -> None:
        self.bus = bus
        self.agents = agents
        self.router = router
        self.client = client
        self.tool_registry = tool_registry
        self.skill_injector = skill_injector
        self.memory = memory
        self.gate = gate_controller

        self._qa_agent: PaperQAAgent | None = None
        self._history: list[dict[str, Any]] = []
        self._paper_version: int = 0
        self._session_dir: Path = settings.runs_dir / bus.session_id

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def run(self, pipeline: TaskPipeline, brief: ResearchBrief) -> None:
        """Main entry point — called from MetaOrchestrator."""
        latex = self._get_latex_from_pipeline(pipeline)
        if not latex:
            console.print("[dim]No paper LaTeX found — skipping review.[/dim]")
            return

        self._save_paper_version(latex)
        self.bus.put("paper_qa_latex", latex)

        if not self._should_review():
            return

        await self._review_loop(pipeline, brief, latex)

    # ------------------------------------------------------------------
    # Review loops
    # ------------------------------------------------------------------

    async def _review_loop(
        self, pipeline: TaskPipeline, brief: ResearchBrief, latex: str
    ) -> None:
        """Outer loop: review → QA → rewrite → review ..."""
        while True:
            self._display_latex_preview(latex)
            action = await self._qa_loop(latex)

            if action == "accept":
                console.print(
                    f"[green]Paper accepted (v{self._paper_version})[/green]"
                )
                break

            if action == "rewrite":
                new_latex = await self._do_rewrite(pipeline, brief)
                if new_latex is None:
                    latex = self._rollback_paper()
                    console.print(
                        "[yellow]Rewrite failed — rolled back to "
                        f"v{self._paper_version}[/yellow]"
                    )
                else:
                    latex = new_latex
                    self._save_paper_version(latex)
                    self.bus.put("paper_qa_latex", latex)

    async def _qa_loop(self, latex: str) -> str:
        """Inner loop: question → QA agent → user decides.

        Returns:
            "accept" or "rewrite"
        """
        while True:
            question = self._prompt_question()
            if not question:
                return "accept"

            console.print("\n[blue]QA Agent thinking...[/blue]")
            answer = await self._ask_qa_agent(latex, question)

            self._history.append({
                "role": "user",
                "content": question,
                "ts": datetime.now(timezone.utc).isoformat(),
                "version": self._paper_version,
            })
            self._history.append({
                "role": "assistant",
                "content": answer,
                "ts": datetime.now(timezone.utc).isoformat(),
                "version": self._paper_version,
            })
            self._persist_history()

            choice = self._prompt_after_answer()
            if choice == "a":
                return "accept"
            if choice == "r":
                return "rewrite"
            # choice == "q": continue inner loop

    # ------------------------------------------------------------------
    # QA Agent interaction
    # ------------------------------------------------------------------

    def _get_or_create_qa_agent(self) -> PaperQAAgent:
        if self._qa_agent is None:
            self._qa_agent = PaperQAAgent(
                bus=self.bus,
                tool_registry=self.tool_registry,
                skill_injector=self.skill_injector,
                memory=self.memory,
                client=self.client,
            )
        return self._qa_agent

    async def _ask_qa_agent(self, latex: str, question: str) -> str:
        agent = self._get_or_create_qa_agent()
        # Pass only role-content pairs to the agent (strip metadata)
        clean_history = [
            {"role": h["role"], "content": h["content"]} for h in self._history
        ]
        result = await agent.ask(
            question=question, latex=latex, history=clean_history
        )
        if result.failed:
            console.print(f"[red]QA Agent error: {result.error}[/red]")
            return f"Error: {result.error}"
        return result.output.get("answer", "")

    # ------------------------------------------------------------------
    # Rewrite
    # ------------------------------------------------------------------

    async def _do_rewrite(
        self, pipeline: TaskPipeline, brief: ResearchBrief
    ) -> str | None:
        """Collect revision prompt, re-run theory + writer. Returns new LaTeX or None."""
        revision_prompt = self._prompt_revision()
        if not revision_prompt:
            console.print("[dim]No revision instructions — skipping rewrite.[/dim]")
            return None

        # Save rewrite context
        self._save_rewrite_context(revision_prompt)

        # Build feedback from QA history + revision prompt
        qa_summary = self._summarize_qa_history()
        feedback = (
            f"\n\n[User revision request after paper review]:\n"
            f"QA discussion summary:\n{qa_summary}\n\n"
            f"Revision instructions:\n{revision_prompt}"
        )

        # Reset theory and writer tasks
        theory_task = next(
            (t for t in pipeline.tasks if t.name == "theory"), None
        )
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )

        if theory_task is not None:
            theory_task.description = (theory_task.description or "") + feedback
            theory_task.retries = 0
            theory_task.status = TaskStatus.PENDING
        if writer_task is not None:
            writer_task.retries = 0
            writer_task.status = TaskStatus.PENDING

        self.bus.put_pipeline(pipeline)
        console.print("[blue]Re-running theory + writer with feedback...[/blue]")

        try:
            for task in pipeline.tasks:
                if task.name not in ("theory", "writer"):
                    continue
                if task.status != TaskStatus.PENDING:
                    continue

                task.mark_started()
                console.print(f"[blue]> Running: {task.name}[/blue]")
                agent = self.router.resolve(task)
                result = await agent.execute(task)

                if result.failed:
                    task.mark_failed(result.error)
                    console.print(
                        f"[red]Failed: {task.name}: {result.error[:100]}[/red]"
                    )
                    # Partial failure: if theory failed, writer can still
                    # generate a paper with [TODO] markers
                    if task.name == "theory":
                        console.print(
                            "[yellow]Theory failed — writer will generate "
                            "paper with [TODO] markers[/yellow]"
                        )
                        continue
                    return None

                task_outputs = dict(result.output)
                if result.text_summary:
                    task_outputs["text_summary"] = result.text_summary
                task.mark_completed(task_outputs)
                console.print(f"[green]Done: {task.name}[/green]")

            self.bus.put_pipeline(pipeline)

            # Extract new LaTeX
            new_latex = self._get_latex_from_pipeline(pipeline)
            return new_latex

        except Exception as e:
            logger.exception("Rewrite failed: %s", e)
            console.print(f"[red]Rewrite error: {e}[/red]")
            return None

    # ------------------------------------------------------------------
    # CLI prompts
    # ------------------------------------------------------------------

    def _should_review(self) -> bool:
        """CLI: prompt user; UI: would use review_gate (handled in future)."""
        try:
            return Confirm.ask(
                "\n[bold]Review the paper?[/bold]", default=False
            )
        except (KeyboardInterrupt, EOFError):
            return False

    def _prompt_question(self) -> str:
        try:
            q = console.input(
                "\n[bold]Question[/bold] [dim](Enter to accept):[/dim] "
            ).strip()
            return q
        except (KeyboardInterrupt, EOFError):
            return ""

    def _prompt_after_answer(self) -> str:
        """Returns 'a' (accept), 'q' (question), or 'r' (rewrite)."""
        console.print(
            "\n[bold]What next?[/bold]  "
            "[green][a]ccept[/green]  "
            "[cyan][q]uestion[/cyan]  "
            "[yellow][r]ewrite[/yellow]"
        )
        while True:
            try:
                choice = console.input("-> ").strip().lower()
            except (KeyboardInterrupt, EOFError):
                return "a"
            if choice in ("a", "accept"):
                return "a"
            if choice in ("q", "question"):
                return "q"
            if choice in ("r", "rewrite"):
                return "r"
            console.print("[red]Please enter 'a', 'q', or 'r'.[/red]")

    def _prompt_revision(self) -> str:
        try:
            return console.input(
                "\n[bold]Describe what to fix:[/bold]\n-> "
            ).strip()
        except (KeyboardInterrupt, EOFError):
            return ""

    # ------------------------------------------------------------------
    # Display
    # ------------------------------------------------------------------

    def _display_latex_preview(self, latex: str) -> None:
        lines = latex.split("\n")
        total = len(lines)
        head = 80
        tail = 20

        if total <= head + tail:
            preview = latex
        else:
            top = "\n".join(lines[:head])
            bottom = "\n".join(lines[-tail:])
            omitted = total - head - tail
            preview = f"{top}\n\n... ({omitted} lines omitted) ...\n\n{bottom}"

        console.print(Panel(
            preview,
            title=f"[cyan]Paper Preview (v{self._paper_version})[/cyan]",
            border_style="cyan",
            subtitle=f"{total} lines total",
        ))

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def _get_latex_from_pipeline(self, pipeline: TaskPipeline) -> str:
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )
        if writer_task and writer_task.outputs:
            return writer_task.outputs.get("latex_paper", "")
        return ""

    def _save_paper_version(self, latex: str) -> None:
        self._paper_version += 1
        self._session_dir.mkdir(parents=True, exist_ok=True)
        path = self._session_dir / f"paper_v{self._paper_version}.tex"
        path.write_text(latex, encoding="utf-8")
        logger.info("Saved %s", path)

    def _rollback_paper(self) -> str:
        """Load the previous paper version. Decrements version counter."""
        if self._paper_version <= 1:
            return ""
        prev = self._paper_version - 1
        path = self._session_dir / f"paper_v{prev}.tex"
        if path.exists():
            self._paper_version = prev
            return path.read_text(encoding="utf-8")
        return ""

    def _persist_history(self) -> None:
        """Append the last two entries (Q+A pair) to JSONL."""
        self._session_dir.mkdir(parents=True, exist_ok=True)
        path = self._session_dir / "paper_qa_history.jsonl"
        with path.open("a", encoding="utf-8") as f:
            for entry in self._history[-2:]:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _save_rewrite_context(self, revision_prompt: str) -> None:
        self._session_dir.mkdir(parents=True, exist_ok=True)
        ctx = {
            "qa_summary": self._summarize_qa_history(),
            "revision_prompt": revision_prompt,
            "rewrite_round": self._paper_version,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        path = self._session_dir / f"rewrite_context_v{self._paper_version}.json"
        path.write_text(json.dumps(ctx, indent=2, ensure_ascii=False), encoding="utf-8")

    def _summarize_qa_history(self) -> str:
        """Build a concise text summary of the QA conversation for feedback injection."""
        if not self._history:
            return "(no prior discussion)"
        parts: list[str] = []
        for h in self._history:
            role = "User" if h["role"] == "user" else "QA Agent"
            content = h["content"][:300]
            parts.append(f"{role}: {content}")
        return "\n".join(parts)
```

- [ ] **Step 2: Run handler tests**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_paper_qa_handler.py -v`
Expected: All 5 tests PASS

- [ ] **Step 3: Run all new tests together**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/unit/test_latex_section.py tests/unit/test_paper_qa_agent.py tests/unit/test_paper_qa_handler.py -v`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add eurekaclaw/orchestrator/paper_qa_handler.py
git commit -m "feat: add PaperQAHandler with CLI review, QA loop, and rewrite"
```

---

### Task 9: Wire Handler into MetaOrchestrator

**Files:**
- Modify: `eurekaclaw/orchestrator/meta_orchestrator.py:711-816`

- [ ] **Step 1: Replace `_handle_paper_qa_gate` method body**

In `eurekaclaw/orchestrator/meta_orchestrator.py`, replace the entire `_handle_paper_qa_gate` method (lines 711-816) with:

```python
    async def _handle_paper_qa_gate(self, pipeline: TaskPipeline, brief: ResearchBrief) -> None:
        """After writer completes, offer the user a chance to review the paper.

        Delegates to PaperQAHandler which manages:
        - CLI y/N prompt (default skip)
        - Multi-turn QA with tool-equipped PaperQAAgent
        - Unlimited rewrite cycles (theory + writer re-run)
        - Paper versioning and QA history persistence
        - Graceful failure recovery with rollback
        """
        from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler

        handler = PaperQAHandler(
            bus=self.bus,
            agents=self.agents,
            router=self.router,
            client=self.client,
            tool_registry=self.tool_registry,
            skill_injector=self.skill_injector,
            memory=self.memory,
            gate_controller=self.gate,
        )
        await handler.run(pipeline, brief)
```

- [ ] **Step 2: Run the full test suite**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/ -v --timeout=30`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add eurekaclaw/orchestrator/meta_orchestrator.py
git commit -m "refactor: delegate paper_qa_gate to PaperQAHandler"
```

---

### Task 10: Integration Smoke Test

**Files:**
- No new files — manual verification

- [ ] **Step 1: Verify import chain works**

Run:
```bash
cd /Users/chenggong/Downloads/EurekaClaw && python -c "
from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler
from eurekaclaw.agents.paper_qa.agent import PaperQAAgent
from eurekaclaw.tools.latex_section import LatexSectionReadTool
print('All imports OK')
"
```
Expected: `All imports OK`

- [ ] **Step 2: Verify tool registration works**

Run:
```bash
cd /Users/chenggong/Downloads/EurekaClaw && python -c "
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.tools.registry import build_default_registry
bus = KnowledgeBus('test')
reg = build_default_registry(bus=bus)
assert 'latex_section_read' in reg
print(f'Registry has {len(reg)} tools, latex_section_read registered')
"
```
Expected: `Registry has 8 tools, latex_section_read registered`

- [ ] **Step 3: Verify latex_section_read works end-to-end**

Run:
```bash
cd /Users/chenggong/Downloads/EurekaClaw && python -c "
import asyncio
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.tools.latex_section import LatexSectionReadTool

bus = KnowledgeBus('test')
bus.put('paper_qa_latex', r'''
\section{Introduction}
We study graphs.
\section{Results}
Theorem 1 is proved.
''')
tool = LatexSectionReadTool(bus=bus)
result = asyncio.run(tool.call(section='Results'))
print(result)
assert 'Theorem 1' in result
print('OK')
"
```
Expected: Prints the Results section content and `OK`

- [ ] **Step 4: Run full test suite one final time**

Run: `cd /Users/chenggong/Downloads/EurekaClaw && python -m pytest tests/ -v --timeout=30`
Expected: All PASS

- [ ] **Step 5: Commit any fixes if needed, then final summary commit**

```bash
git add -A
git status
# Only commit if there are changes
git diff --cached --quiet || git commit -m "chore: integration verification complete for paper QA gate"
```
