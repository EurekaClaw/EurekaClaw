"""WriterAgent — hierarchical paper generation (LaTeX or Markdown) from research artifacts."""

from __future__ import annotations

import logging
import re
from pathlib import Path

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.config import settings
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


def _compute_cite_keys(papers: list) -> list[str]:
    """Generate cite keys using the same algorithm as _generate_thebibliography.

    Must stay in sync with _generate_thebibliography below.
    """
    keys: list[str] = []
    seen: set[str] = set()
    for p in papers:
        authors = getattr(p, "authors", None) or []
        year = getattr(p, "year", None) or ""
        first_author = (authors[0].split()[-1] if authors else "unknown").lower()
        base = re.sub(r"[^a-z0-9]", "", first_author) + str(year)
        key = base
        suffix = 1
        while key in seen:
            key = f"{base}{chr(ord('a') + suffix - 1)}"
            suffix += 1
        seen.add(key)
        keys.append(key)
    return keys


# ---------------------------------------------------------------------------
# EurekaTemplate-based LaTeX preamble
# ---------------------------------------------------------------------------
# Uses the eureka.cls custom class (copied to output dir by save_artifacts).
# %%  →  literal % in LaTeX output (LaTeX line-continuation comments)
# %s  →  replaced at runtime with (title, abstract)
# ---------------------------------------------------------------------------
LATEX_PREAMBLE = r"""\nonstopmode
\documentclass[]{eureka}

%% Additional packages not already loaded by eureka.cls
\usepackage{amsthm}
\usepackage{xargs}
\usepackage{tabularx}
\usepackage[toc,page,header]{appendix}

%% Theorem environments (eureka.cls does not define these)
\newtheorem{theorem}{Theorem}
\newtheorem{lemma}[theorem]{Lemma}
\newtheorem{corollary}[theorem]{Corollary}
\newtheorem{definition}[theorem]{Definition}
\newtheorem{proposition}[theorem]{Proposition}
\newtheorem{assumption}[theorem]{Assumption}
\newtheorem{conjecture}[theorem]{Conjecture}
\newtheorem{claim}[theorem]{Claim}
\newtheorem{example}[theorem]{Example}
\newtheorem{fact}[theorem]{Fact}
\newtheorem{observation}[theorem]{Observation}
\newtheorem{maintheorem}[theorem]{Main Theorem}
\newtheorem{remark}{Remark}
\newtheorem{auxlemma}[theorem]{Lemma}

%% Common math macros
\newcommand{\R}{\mathbb{R}}
\newcommand{\N}{\mathbb{N}}
\newcommand{\Z}{\mathbb{Z}}
\newcommand{\E}{\mathbb{E}}
\newcommand{\Prob}{\mathbb{P}}
\DeclareMathOperator{\softmax}{softmax}
\DeclareMathOperator{\Att}{Att}
\DeclareMathOperator*{\argmax}{arg\,max}
\DeclareMathOperator*{\argmin}{arg\,min}
\newcommand{\norm}[1]{\left\lVert#1\right\rVert}
\newcommand{\abs}[1]{\left|#1\right|}
\newcommand{\inner}[2]{\langle #1, #2 \rangle}

%% Header: EurekaClaw logo on the first page
\setleftheadercontent{%%
  \headerlogospace{1.6mm}%%
  \adjustbox{valign=c}{\raisebox{0.15mm}{\includegraphics[height=15.2mm]{logo-claw.png}}}%%
}
\setrightheadericon{}
\setrunningheadericon{}
\setheadergroupname{}

\title{%s}
\setfrontauthors{%%
  \authorrow{%%
    \authorentry{EurekaClaw Autonomous Research System}{}}%%
}
\usecustomauthorlayout

\abstract{%s}

\begin{document}
\maketitle
"""

LATEX_END = r"""
\end{document}
"""

_PROOF_STYLE_RULES = """\

PROOF WRITING RULES (strictly enforced):
- Every lemma proof MUST begin with 1-2 sentences of informal intuition before the formal argument.
  Example: "Intuitively, this holds because UCB's confidence bonus shrinks faster than the gap Δ_i grows."
- NEVER write "it is easy to see", "clearly", "by standard arguments", "it follows that",
  "trivially", or "one can show" without immediately justifying the claim in the next sentence.
- Every inequality must explicitly cite which lemma, theorem, or named bound justifies it.
  Bad:  "...therefore E[N_i(T)] ≤ 8 log T / Δ_i²"
  Good: "...by Lemma 3 (Hoeffding concentration) applied with δ = t^{-2}, we get E[N_i(T)] ≤ 8 log T / Δ_i²"
- If a step requires a calculation that takes more than one line, write it out inline — do not skip it.
- Every theorem, lemma, proposition, corollary, or claim in the paper must either have a proof or an explicit citation.
- If a result is adapted from prior work, cite the source and prove the modified part.
- LOW-CONFIDENCE LEMMAS: any lemma marked [LOW CONFIDENCE] in the input has NOT been formally
  verified. You MUST add a \\textcolor{orange}{\\textbf{[Unverified step — see discussion]}} tag
  immediately after its \\end{proof}, and add a paragraph in the Limitations section explaining
  which steps lack formal verification and why they are believed to hold.
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
If the paper contains an algorithm, typeset it in a proper LaTeX algorithm environment with a caption and label.
Ensure all citations are in \\cite{key} format.
Every theorem, lemma, proposition, corollary, or claim must either be proved in the paper or explicitly cited.
Do not leave theorem-like statements unsupported.
Before finalizing the LaTeX, sanity-check environment matching, brace balance, required packages, and custom macro definitions.
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
Every theorem, lemma, proposition, corollary, or claim must either be proved in the paper or explicitly cited.
Do not leave theorem-like statements unsupported.
Make the paper self-contained — a reader should understand it without other references.
"""

_PROOF_STYLE_RULES_MARKDOWN = _PROOF_STYLE_RULES.replace(
    "\\textcolor{orange}{\\textbf{[Unverified step — see discussion]}}",
    "**⚠ [Unverified step — see discussion]**",
)


class WriterAgent(BaseAgent):
    """Generates a complete paper (LaTeX or Markdown) from all knowledge bus artifacts."""

    role = AgentRole.WRITER

    def get_tool_names(self) -> list[str]:
        return ["citation_manager"]

    def _role_system_prompt(self, task: Task) -> str:
        if settings.output_format == "markdown":
            base = _MARKDOWN_SYSTEM_PROMPT
            return base + _PROOF_STYLE_RULES_MARKDOWN if settings.enforce_proof_style else base
        base = _LATEX_SYSTEM_PROMPT
        return base + _PROOF_STYLE_RULES if settings.enforce_proof_style else base

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

        # Build context for the writer, tagging low-confidence lemmas explicitly
        lemma_entries = [
            (theory_state.lemma_dag.get(lid), rec, lid)
            for lid, rec in theory_state.proven_lemmas.items()
            if theory_state.lemma_dag.get(lid)
        ]
        if fmt == "markdown":
            proven_proofs = "\n\n".join(
                (
                    f"**Lemma** [{lid}]{' [LOW CONFIDENCE — not formally verified]' if not rec.verified else ''}:"
                    f" {node.statement}\n\n**Proof**: {rec.proof_text[:1500]}"
                )
                for node, rec, lid in lemma_entries
                if node is not None
            )
        else:
            proven_proofs = "\n\n".join(
                (
                    f"% {'[LOW CONFIDENCE — not formally verified]' if not rec.verified else '[verified]'}\n"
                    f"\\begin{{lemma}}[{lid}]\n{node.statement}\n\\end{{lemma}}\n"
                    f"\\begin{{proof}}\n{rec.proof_text[:1500]}\n\\end{{proof}}"
                )
                for node, rec, lid in lemma_entries
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
            # Pre-compute the exact cite keys that _generate_bibtex will use,
            # so the LLM can reference them correctly in \cite{} commands.
            cite_keys = _compute_cite_keys([p for p in bib.papers[:15]])
            citations = "\n".join(
                f"- \\cite{{{key}}} — {p.title} ({p.year}), {', '.join(p.authors[:2])}"
                for key, p in zip(cite_keys, bib.papers[:15])
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
            _no_refs = "(no references — omit \\bibliography and \\bibliographystyle commands)"
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

Key references to cite (use EXACTLY these \\cite{{}} keys — they match the references.bib file):
{citations or _no_refs}

Write the full paper body (abstract through conclusion) in LaTeX.
Use \\begin{{theorem}}...\\end{{theorem}} environments.
Include all proofs using \\begin{{proof}}...\\end{{proof}}.
"""

        try:
            text, tokens = await self.run_agent_loop(
                task, user_message, max_turns=settings.writer_max_turns
            )

            if fmt == "markdown":
                paper_content = self._extract_markdown(text)
                output_key = "latex_paper"  # reuse existing key for compatibility
            else:
                abstract_text = self._extract_abstract(text) or (
                    f"We present theoretical results in {brief.domain}. "
                    f"Our main contribution is: {theory_state.informal_statement[:200]}"
                )
                latex_body = self._extract_latex(text)
                inline_bib = self._generate_thebibliography(bib.papers if bib else [])
                paper_content = (
                    LATEX_PREAMBLE % (
                        self._escape_latex(title),
                        abstract_text,
                    )
                    + latex_body
                    + ("\n\\clearpage\n" + inline_bib if inline_bib else "")
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
        """Extract the paper body, stripping all document-level boilerplate.

        LATEX_PREAMBLE already provides: \\documentclass, packages, theorem
        environments, \\title, \\author, \\date, \\begin{document}, \\maketitle,
        and \\begin{abstract}...\\end{abstract}.  Any of those emitted by the LLM
        must be removed to avoid duplicates in the final file.
        """
        import re

        # 1. Unwrap markdown code fences if present
        if "```latex" in text:
            start = text.index("```latex") + 8
            end = text.index("```", start) if "```" in text[start:] else len(text)
            text = text[start:end].strip()

        # 2. If the LLM output a full document, take only the body
        #    (everything between \begin{document} and \end{document})
        if r"\begin{document}" in text:
            text = text[text.index(r"\begin{document}") + len(r"\begin{document}"):]

        # Step 3: strip \end{document} and everything after
        if r"\end{document}" in text:
            text = text[:text.rindex(r"\end{document}")]


        # 3. Strip preamble-style lines that may appear before or after
        #    \begin{document} when the LLM writes a full or partial document.
        _PREAMBLE_PREFIXES = (
            r"\documentclass",
            r"\usepackage",
            r"\geometry",
            r"\newtheorem",
            r"\newcommand",
            r"\renewcommand",
            r"\DeclareMathOperator",
            r"\theoremstyle",
            r"\setlength",
            r"\pagestyle",
            r"\setcounter",
        )
        lines = [
            l for l in text.splitlines()
            if not any(l.lstrip().startswith(p) for p in _PREAMBLE_PREFIXES)
        ]
        text = "\n".join(lines)

        # 4. Strip \title{...}, \author{...}, \date{...} — possibly spanning
        #    multiple lines (match balanced braces up to depth 1 is enough here)
        for cmd in (r"\title", r"\author", r"\date"):
            text = re.sub(
                r"(?m)^[ \t]*" + re.escape(cmd) + r"\{[^}]*\}[ \t]*\n?", "", text
            )

        # 5. Strip \maketitle and duplicate \begin{abstract}...\end{abstract}
        text = re.sub(r"(?m)^[ \t]*\\maketitle[ \t]*\n?", "", text)
        text = re.sub(
            r"(?s)\\begin\{abstract\}.*?\\end\{abstract\}", "", text
        )

        # 6. Normalize broken or mis-cased environment names produced by the LLM.
        #    e.g. \begin{Proof} → \begin{proof}, \begin{le mma} → \begin{lemma}
        _ENV_FIXES = {
            "Proof": "proof", "PROOF": "proof",
            "Lemma": "lemma", "LEMMA": "lemma",
            "le mma": "lemma", "lem ma": "lemma",
            "Theorem": "theorem", "THEOREM": "theorem",
            "Corollary": "corollary", "COROLLARY": "corollary",
            "Definition": "definition", "DEFINITION": "definition",
            "Proposition": "proposition", "PROPOSITION": "proposition",
            "Assumption": "assumption", "ASSUMPTION": "assumption",
            "Remark": "remark", "REMARK": "remark",
            "Example": "example", "EXAMPLE": "example",
            "Claim": "claim", "CLAIM": "claim",
        }
        for wrong, correct in _ENV_FIXES.items():
            text = text.replace(r"\begin{" + wrong + "}", r"\begin{" + correct + "}")
            text = text.replace(r"\end{" + wrong + "}", r"\end{" + correct + "}")

        # 7. Close any unclosed environments (LLM may be truncated by max_tokens).
        #    Scan \begin{X}/\end{X} pairs; append missing \end{X} in reverse order.
        #    Also drop any trailing partial tabular row (no closing \\) before closing.
        text = WriterAgent._close_open_environments(text)

        return text.strip()

    @staticmethod
    def _close_open_environments(text: str) -> str:
        """Detect unclosed LaTeX environments and append the missing \\end{} tags."""
        import re
        # Process \begin{X} and \end{X} in document order using a stack
        tokens = re.finditer(r"\\(begin|end)\{([^}]+)\}", text)
        stack: list[str] = []
        for m in tokens:
            kind, env = m.group(1), m.group(2)
            if kind == "begin":
                stack.append(env)
            elif kind == "end" and stack and stack[-1] == env:
                stack.pop()
            # Mismatched \end (wrong env name) — ignore, don't pop
        if not stack:
            return text
        # For tabular: drop trailing incomplete row (no closing \\)
        if "tabular" in stack:
            lines = text.rstrip().splitlines()
            while lines:
                last = lines[-1].strip()
                if not last or last.startswith(r"\end") or last.endswith("\\\\"):
                    break
                lines.pop()
            text = "\n".join(lines)
        # Append missing \end{} in reverse stack order
        closing = "\n".join(r"\end{" + env + "}" for env in reversed(stack))
        return text + "\n" + closing

    @staticmethod
    def _extract_abstract(text: str) -> str:
        """Pull the content of \\begin{abstract}...\\end{abstract} from LLM output.

        Returns empty string if not found; used to populate \\abstract{} in the
        eureka.cls preamble rather than leaving it as a placeholder.
        """
        m = re.search(r"\\begin\{abstract\}(.*?)\\end\{abstract\}", text, re.DOTALL)
        if m:
            return m.group(1).strip()
        return ""

    @staticmethod
    def _generate_thebibliography(papers: list) -> str:
        """Generate an inline \\begin{thebibliography}...\\end{thebibliography} block.

        Uses the same key-generation algorithm as _compute_cite_keys so that
        \\bibitem{key} entries exactly match the \\cite{key} commands the LLM
        was told to use.  natbib (loaded by eureka.cls with [numbers]) renders
        these as [1], [2], ... in the text.
        """
        if not papers:
            return ""

        lines = [r"\bibliographystyle{plainnat}", r"\begin{thebibliography}{99}"]
        seen: set[str] = set()

        for p in papers:
            authors = getattr(p, "authors", None) or []
            year = getattr(p, "year", None) or ""
            venue = getattr(p, "venue", None) or ""
            arxiv_id = getattr(p, "arxiv_id", None) or ""
            title = getattr(p, "title", None) or ""

            # Key generation — must match _compute_cite_keys exactly
            first_author = (authors[0].split()[-1] if authors else "unknown").lower()
            base = re.sub(r"[^a-z0-9]", "", first_author) + str(year)
            key = base
            suffix = 1
            while key in seen:
                key = f"{base}{chr(ord('a') + suffix - 1)}"
                suffix += 1
            seen.add(key)

            # Author string — up to 5 authors then "et al."
            author_str = ", ".join(authors[:5])
            if len(authors) > 5:
                author_str += " et~al."

            lines.append(f"\\bibitem{{{key}}}")
            lines.append(author_str)
            lines.append(f"\\newblock {title}")
            if arxiv_id:
                lines.append(
                    f"\\newblock {{\\em arXiv preprint arXiv:{arxiv_id}}}, {year}."
                )
            elif venue:
                lines.append(f"\\newblock {{\\em {venue}}}, {year}.")
            else:
                lines.append(f"\\newblock {year}.")
            lines.append("")  # blank line between entries

        lines.append(r"\end{thebibliography}")
        return "\n".join(lines)

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
