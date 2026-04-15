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
