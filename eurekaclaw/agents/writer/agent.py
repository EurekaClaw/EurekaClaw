"""WriterAgent — hierarchical paper generation (LaTeX or Markdown) from research artifacts."""

from __future__ import annotations

import logging
from pathlib import Path

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.config import settings
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)

LATEX_PREAMBLE = r"""\nonstopmode
\documentclass[12pt]{article}
\usepackage{amsmath, amssymb, amsthm}
\usepackage{hyperref}
\usepackage{natbib}
\usepackage{geometry}
\geometry{margin=1in}

\newtheorem{theorem}{Theorem}
\newtheorem{lemma}[theorem]{Lemma}
\newtheorem{corollary}[theorem]{Corollary}
\newtheorem{definition}[theorem]{Definition}
\newtheorem{proposition}[theorem]{Proposition}
\newtheorem{remark}{Remark}

\title{%s}
\author{EurekaClaw Autonomous Research System}
\date{\today}

\begin{document}
\maketitle
\begin{abstract}
%s
\end{abstract}

"""

LATEX_END = r"""
\bibliographystyle{plainnat}
\bibliography{references}
\end{document}
"""

_LATEX_SYSTEM_PROMPT = """\
You are the Writer Agent of EurekaClaw. You generate complete, publication-quality LaTeX papers \
from structured research artifacts.

Your output must follow standard theory paper format:
1. Abstract (150 words): problem, main result, significance
2. Introduction: motivation, contributions, paper overview
3. Preliminaries: notation, definitions, background
4. Main Results: state theorems prominently, then prove them
5. Experiments: empirical validation of theoretical bounds
6. Related Work: precise comparison with prior work
7. Conclusion: summary, limitations, future work

Use proper LaTeX theorem environments throughout.
Ensure all citations are in \\cite{key} format.
Make the paper self-contained — a reader should understand it without other references.
"""

_MARKDOWN_SYSTEM_PROMPT = """\
You are the Writer Agent of EurekaClaw. You generate complete, publication-quality Markdown papers \
from structured research artifacts.

Your output must follow standard theory paper format using Markdown headings:
1. ## Abstract (150 words): problem, main result, significance
2. ## Introduction: motivation, contributions, paper overview
3. ## Preliminaries: notation, definitions, background
4. ## Main Results: state theorems prominently, then prove them
5. ## Experiments: empirical validation of theoretical bounds
6. ## Related Work: precise comparison with prior work
7. ## Conclusion: summary, limitations, future work

Use **Theorem**, **Lemma**, **Proof** bold labels for formal results.
Use $...$ for inline math and $$...$$ for display math (LaTeX-style math is fine inside Markdown).
Make the paper self-contained — a reader should understand it without other references.
"""


class WriterAgent(BaseAgent):
    """Generates a complete paper (LaTeX or Markdown) from all knowledge bus artifacts."""

    role = AgentRole.WRITER

    def get_tool_names(self) -> list[str]:
        return ["citation_manager"]

    def _role_system_prompt(self, task: Task) -> str:
        if settings.output_format == "markdown":
            return _MARKDOWN_SYSTEM_PROMPT
        return _LATEX_SYSTEM_PROMPT

    async def execute(self, task: Task) -> AgentResult:
        brief = self.bus.get_research_brief()
        theory_state = self.bus.get_theory_state()
        exp_result = self.bus.get_experiment_result()
        bib = self.bus.get_bibliography()

        if not brief or not theory_state:
            return self._make_result(task, False, {}, error="Missing required artifacts on bus")

        direction = brief.selected_direction
        title = direction.title if direction else f"Results in {brief.domain}"
        fmt = settings.output_format

        # Build context for the writer
        if fmt == "markdown":
            proven_proofs = "\n\n".join(
                f"**Lemma**: {node.statement}\n\n**Proof**: {rec.proof_text[:1500]}"
                for node, rec in [
                    (theory_state.lemma_dag.get(lid), rec)
                    for lid, rec in theory_state.proven_lemmas.items()
                    if theory_state.lemma_dag.get(lid)
                ]
                if node is not None
            )
        else:
            proven_proofs = "\n\n".join(
                f"\\begin{{lemma}}\n{node.statement}\n\\end{{lemma}}\n\\begin{{proof}}\n{rec.proof_text[:1500]}\n\\end{{proof}}"
                for node, rec in [
                    (theory_state.lemma_dag.get(lid), rec)
                    for lid, rec in theory_state.proven_lemmas.items()
                    if theory_state.lemma_dag.get(lid)
                ]
                if node is not None
            )

        exp_summary = ""
        if exp_result:
            bounds_str = "\n".join(
                f"- {b.name}: theoretical={b.theoretical}, empirical={b.empirical}"
                for b in exp_result.bounds
            )
            exp_summary = f"Alignment score: {exp_result.alignment_score:.2f}\n{bounds_str}"

        citations = ""
        if bib and bib.papers:
            citations = "\n".join(
                f"- {p.title} ({p.year}), {', '.join(p.authors[:2])}"
                for p in bib.papers[:15]
            )

        if fmt == "markdown":
            user_message = f"""\
Write a complete Markdown research paper based on these artifacts:

Title: {title}
Domain: {brief.domain}
Main theorem: {theory_state.formal_statement}
Informal: {theory_state.informal_statement}

Proven lemmas (use in Results section):
{proven_proofs[:3000] or "(no proven lemmas)"}

Experimental results:
{exp_summary or "(no experiments run)"}

Key references to cite:
{citations or "(no references)"}

Start with a YAML front matter block:
---
title: "{title}"
author: EurekaClaw Autonomous Research System
---

Then write the full paper body using Markdown headings (## Abstract, ## Introduction, etc.).
Use **Theorem X**: and **Proof**: for formal results.
Use $...$ for inline math and $$...$$ for display math.
"""
        else:
            user_message = f"""\
Write a complete LaTeX research paper based on these artifacts:

Title: {title}
Domain: {brief.domain}
Main theorem: {theory_state.formal_statement}
Informal: {theory_state.informal_statement}

Proven lemmas (use in Proofs section):
{proven_proofs[:3000] or "(no proven lemmas)"}

Experimental results:
{exp_summary or "(no experiments run)"}

Key references to cite:
{citations or "(no references)"}

Write the full paper body (abstract through conclusion) in LaTeX.
Use \\begin{{theorem}}...\\end{{theorem}} environments.
Include all proofs using \\begin{{proof}}...\\end{{proof}}.
"""

        try:
            text, tokens = await self.run_agent_loop(task, user_message, max_turns=3)

            if fmt == "markdown":
                paper_content = self._extract_markdown(text)
                output_key = "latex_paper"  # reuse existing key for compatibility
            else:
                latex_body = self._extract_latex(text)
                paper_content = (
                    LATEX_PREAMBLE % (
                        self._escape_latex(title),
                        f"We present results in {self._escape_latex(brief.domain)}.",
                    )
                    + latex_body
                    + LATEX_END
                )
                output_key = "latex_paper"

            self.memory.log_event(self.role.value, f"Paper written ({fmt}): {len(paper_content)} characters")

            return self._make_result(
                task,
                success=True,
                output={output_key: paper_content, "word_count": len(text.split()), "output_format": fmt},
                text_summary=f"Paper generated ({fmt}): {len(text.split())} words",
                token_usage=tokens,
            )

        except Exception as e:
            logger.exception("Writer agent failed")
            return self._make_result(task, False, {}, error=str(e))

    def _extract_latex(self, text: str) -> str:
        """Extract LaTeX content, removing markdown code blocks if present.

        Also strips any document-level boilerplate the LLM may have included
        (\\documentclass, \\begin{document}, \\end{document}) since those are
        already provided by LATEX_PREAMBLE / LATEX_END.
        """
        if "```latex" in text:
            start = text.index("```latex") + 8
            end = text.index("```", start) if "```" in text[start:] else len(text)
            text = text[start:end].strip()

        # Drop preamble / document wrapper if the LLM included a full document
        if r"\begin{document}" in text:
            text = text[text.index(r"\begin{document}") + len(r"\begin{document}"):]
        if r"\end{document}" in text:
            text = text[:text.rindex(r"\end{document}")]
        # Drop \documentclass line(s) that might remain above \begin{document}
        lines = [l for l in text.splitlines() if not l.lstrip().startswith(r"\documentclass")]
        return "\n".join(lines).strip()

    @staticmethod
    def _escape_latex(s: str) -> str:
        """Escape LaTeX special characters in plain-text strings (e.g. titles)."""
        # Order matters: backslash first so we don't double-escape later subs
        replacements = [
            ("\\", r"\textbackslash{}"),
            ("&",  r"\&"),
            ("%",  r"\%"),
            ("$",  r"\$"),
            ("#",  r"\#"),
            ("_",  r"\_"),
            ("{",  r"\{"),
            ("}",  r"\}"),
            ("~",  r"\textasciitilde{}"),
            ("^",  r"\textasciicircum{}"),
        ]
        for char, escaped in replacements:
            s = s.replace(char, escaped)
        return s

    def _extract_markdown(self, text: str) -> str:
        """Extract Markdown content, removing code fences if present."""
        for fence in ("```markdown", "```md"):
            if fence in text:
                start = text.index(fence) + len(fence)
                end = text.index("```", start) if "```" in text[start:] else len(text)
                return text[start:end].strip()
        return text
