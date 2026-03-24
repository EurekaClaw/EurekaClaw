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


def _pretty_lemma_name(lid: str) -> str:
    """Convert a snake_case lemma id to a Title Case display name.

    e.g. 'kronecker_operator_alignment' → 'Kronecker Operator Alignment'
    """
    return " ".join(w.capitalize() for w in lid.split("_"))


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

%% SMiLe group math macro package — loads amsmath, amssymb, amsthm, bm,
%% bold/calligraphic/blackboard fonts, norms, brackets, operators, and
%% theorem environments with \ifx\undefined guards.
\usepackage{smile}

%% Extra packages not provided by smile.sty
\usepackage{xargs}
\usepackage{tabularx}

%% Theorem environments not defined by smile.sty (guarded against redefinition)
\ifx\observation\undefined\newtheorem{observation}[theorem]{Observation}\fi
\ifx\maintheorem\undefined\newtheorem{maintheorem}[theorem]{Main Theorem}\fi
\ifx\auxlemma\undefined\newtheorem{auxlemma}[theorem]{Lemma}\fi

%% Operators not provided by smile.sty
\DeclareMathOperator{\softmax}{softmax}
\DeclareMathOperator{\Att}{Att}

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
    \authorentry{EurekaClaw}{}}%%
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

MATH NOTATION — the preamble loads smile.sty which defines the macros below.
Use ONLY these macros (or plain LaTeX math). Do NOT redefine them and do NOT
introduce \\newcommand for anything already listed here.

  Blackboard bold — use these, NOT \\mathbb{} directly:
    \\RR (ℝ)  \\EE (𝔼)  \\PP (ℙ)  \\NN (ℕ)  \\ZZ (ℤ)  \\QQ (ℚ)  \\CC (ℂ)
    \\VV  \\II  \\TT  \\XX  \\YY  \\SSS  \\MM  \\LL  \\KK

  Calligraphic — use these, NOT \\mathcal{} directly:
    \\cA \\cB \\cC \\cD \\cE \\cF \\cG \\cH \\cI \\cJ \\cK \\cL \\cM
    \\cN \\cO \\cP \\cQ \\cR \\cS \\cT \\cU \\cV \\cW \\cX \\cY \\cZ

  Bold vectors/matrices (mathbf family — \\xb, \\Wb, …):
    lowercase: \\ab \\bbb \\cbb \\db \\eb \\fb \\gb \\hb \\ib \\jb \\kb \\lb \\mb
               \\nbb \\ob \\pb \\qb \\rb \\sbb \\tb \\ub \\vb \\wb \\xb \\yb \\zb
    uppercase: \\Ab \\Bb \\Cb \\Db \\Eb \\Fb \\Gb \\Hb \\Ib \\Jb \\Kb \\Lb \\Mb
               \\Nb \\Ob \\Pb \\Qb \\Rb \\Sbb \\Tb \\Ub \\Vb \\Wb \\Xb \\Yb \\Zb

  Bold vectors/matrices (bm family — \\bx, \\bW, …):
    lowercase: \\ba \\bb \\bc \\bd \\be \\bbf \\bg \\bh \\bj \\bk \\bl \\bbm
               \\bn \\bo \\bp \\bq \\br \\bs \\bt \\bu \\bv \\bw \\bx \\by \\bz
    uppercase: \\bA \\bB \\bC \\bD \\bE \\bF \\bG \\bH \\bI \\bJ \\bK \\bL \\bM
               \\bN \\bO \\bP \\bQ \\bR \\bS \\bT \\bU \\bV \\bW \\bX \\bY \\bZ

  Bold greek:
    \\balpha \\bbeta \\bgamma \\bepsilon \\bvarepsilon \\bzeta \\btheta \\bvartheta
    \\bkappa \\blambda \\bmu \\bnu \\bxi \\bpi \\bsigma \\btau \\bphi \\bvarphi
    \\bchi \\bpsi \\bomega
    \\bGamma \\bDelta \\bTheta \\bLambda \\bXi \\bPi \\bSigma \\bPhi \\bPsi \\bOmega

  Norms and brackets:
    \\norm{x}          fixed-size ||x||
    \\nbr{x}           auto-sized \\|x\\|
    \\bignorm{x}       large ||x||
    \\opnorm{x}{p}     triple-bar operator norm
    \\inner{x}{y}      auto-sized ⟨x, y⟩
    \\dotp{x}{y}       fixed-size ⟨x, y⟩
    \\bigdotp{x}{y}    large ⟨x, y⟩
    \\rbr{x}           auto-sized ( )
    \\sbr{x}           auto-sized [ ]
    \\cbr{x}           auto-sized { }
    \\abr{x}           auto-sized | |
    \\ceil{x}           ⌈x⌉
    \\floor{x}          ⌊x⌋

  Operators (already defined — do NOT redefine with \\DeclareMathOperator):
    \\argmin  \\argmax  \\minimize  \\sign  \\tr  \\diag  \\Var  \\Cov  \\corr    \\ind

  Other:
    \\zero  \\one              bold 0 / 1 vectors
    \\nicefrac{a}{b}          fraction that auto-switches to textstyle in inline math
    \\given                   conditional bar: p(y \\given x)
    \\ud                      upright d for integrals: \\int f(x)\\ud x
    \\hat{} → \\widehat{}     (auto-redefined by smile.sty)
    \\tilde{} → \\widetilde{} (auto-redefined by smile.sty)
    \\poly  \\polylog         for generic polynomial / polylogarithmic factors in bounds
    \\iid                     for "i.i.d." in math mode)
    \\iidsim                  for "i.i.d. \\sim" in math mode)

  Do NOT use or define: \\R \\N \\Z \\E \\Prob  — use \\RR \\NN \\ZZ \\EE \\PP instead.
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
Use $...$ for inline math and $$...$$ for display math (standard LaTeX math notation is fine inside Markdown).

MARKDOWN COMPATIBILITY — strictly follow these rules:
- End every proof with the Unicode QED symbol **□** (U+25A1) on its own line, never with \\hfill\\square or \\hfill\\blacksquare.
- NEVER use \\hfill — it is a LaTeX layout command with no Markdown equivalent. Drop it entirely.
- NEVER use bare LaTeX commands that only control layout or spacing: \\newpage, \\vspace, \\hspace, \\noindent, \\medskip, \\bigskip, \\smallskip, \\clearpage, \\linebreak, \\pagebreak.
- NEVER use \\infty as a standalone end marker. If you mean "infinity" in a mathematical expression, write $\\infty$ inside math delimiters.
- NEVER use \\textcolor, \\textbf, \\textit outside of math mode — use Markdown bold (**text**) and italic (*text*) instead.
- Theorem-like blocks: open with e.g. **Theorem 1** *(optional name).* and close the proof paragraph with □.

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
        # Pre-compute cite keys and build arxiv_id → cite_key lookup early so
        # the proven_proofs block can embed correct \citet{} keys for known lemmas.
        cite_keys: list[str] = []
        arxiv_to_citekey: dict[str, str] = {}
        citekey_to_num: dict[str, int] = {}   # key → 1-based index (Markdown only)
        md_references: str = ""               # numbered reference list for Markdown
        citations = ""
        if bib and bib.papers:
            cite_keys = _compute_cite_keys([p for p in bib.papers[:15]])
            citations = "\n".join(
                f"- \\cite{{{key}}} — {p.title} ({p.year}), {', '.join(p.authors[:2])}"
                for key, p in zip(cite_keys, bib.papers[:15])
            )
            for idx, (key, p) in enumerate(zip(cite_keys, bib.papers[:15]), start=1):
                citekey_to_num[key] = idx
                aid = (getattr(p, "arxiv_id", None) or getattr(p, "paper_id", None) or "").strip()
                if aid:
                    # Normalise: strip version suffix (e.g. "2512.07011v1" → "2512.07011")
                    arxiv_to_citekey[aid.split("v")[0]] = key
                    arxiv_to_citekey[aid] = key
            # Numbered reference list used in Markdown output
            md_references = "\n".join(
                f"[{idx}] {', '.join(p.authors[:3])}{'et al.' if len(p.authors) > 3 else ''}."
                f" {p.title}. {p.year}."
                + (f" arXiv:{p.arxiv_id}." if getattr(p, 'arxiv_id', None) else "")
                for idx, p in enumerate(bib.papers[:15], start=1)
            )

        # Build a provenance map for use inside the proven_proofs block
        prov_of: dict[str, str] = {pp.lemma_id: pp.provenance
                                    for pp in (theory_state.proof_plan or [])}
        src_of:  dict[str, str] = {pp.lemma_id: (getattr(pp, "source", "") or "")
                                    for pp in (theory_state.proof_plan or [])}

        def _proof_block_latex(lid: str, rec) -> str:  # type: ignore[return]
            """Return a \\begin{proof}...\\end{proof} snippet for the proven_proofs prompt."""
            prov = prov_of.get(lid, "new")
            src  = src_of.get(lid, "")
            if prov == "known":
                # Resolve the arxiv ID to a cite key (strip version suffix)
                src_base = src.split("v")[0]
                ckey = arxiv_to_citekey.get(src_base) or arxiv_to_citekey.get(src) or ""
                cite = f"\\cite{{{ckey}}}" if ckey else (f"\\cite{{{src}}}" if src else "the cited work")
                return f"\\begin{{proof}}\nRefer to {cite}.\n\\end{{proof}}"
            # adapted / new — full proof injected post-generation via placeholder
            return f"\\begin{{proof}}\n%%PROOF:{lid}%%\n\\end{{proof}}"

        # The full proof texts for adapted/new lemmas are injected post-generation
        # via %%PROOF:id%% placeholders (see _replace_proof_placeholders), keeping
        # the LLM context small.  Known lemmas get a \citet{} citation directly.
        if fmt == "markdown":
            proven_proofs = "\n\n".join(
                (
                    f"**Lemma** [{lid}]{' [LOW CONFIDENCE — not formally verified]' if not rec.verified else ''}:"
                    f" {node.statement}\n\n**Proof**: %%PROOF:{lid}%%"
                )
                for node, rec, lid in lemma_entries
                if node is not None
            )
        else:
            proven_proofs = "\n\n".join(
                (
                    f"% {'[LOW CONFIDENCE — not formally verified]' if not rec.verified else '[verified]'}\n"
                    f"\\begin{{lemma}}[{_pretty_lemma_name(lid)}]\\label{{lem:{lid}}}\n"
                    f"{node.statement}\n\\end{{lemma}}\n"
                    + _proof_block_latex(lid, rec)
                )
                for node, rec, lid in lemma_entries
                if node is not None
            )

        exp_summary = ""
        if exp_result and settings.experiment_mode != "false":
            bounds_str = "\n".join(
                f"- {b.name}: theoretical={b.theoretical}, empirical={b.empirical}"
                for b in exp_result.bounds
            )
            exp_summary = f"Alignment score: {exp_result.alignment_score:.2f}\n{bounds_str}"

        if fmt == "markdown":
            md_cite_list = "\n".join(
                f"- [{num}] {p.title} ({p.year}), {', '.join(p.authors[:2])}"
                for num, p in zip(range(1, len(cite_keys) + 1), (bib.papers[:15] if bib else []))
            ) or "(no references)"
            user_message = f"""\
Write a complete Markdown research paper based on these artifacts:

Title: {title}
Domain: {brief.domain}
Main theorem: {theory_state.formal_statement}
Informal: {theory_state.informal_statement}

Proven lemmas (use in Results section):
{proven_proofs or "(no proven lemmas)"}

Experimental results:
{exp_summary or "(no experiments run — do NOT include an Experiments section)"}

Key references (cite as [1], [2], ... — NEVER use \\cite{{}} in Markdown):
{md_cite_list}

Start with a YAML front matter block:
---
title: "{title}"
author: EurekaClaw Autonomous Research System
---

Then write the full paper body using Markdown headings (## Abstract, ## Introduction, etc.).
Use **Theorem X**: and **Proof**: for formal results.
Use $...$ for inline math and $$...$$ for display math.
CITATION RULE: use only [1], [2], ... style inline citations. Do NOT write \\cite{{key}} anywhere.
End the paper with a ## References section listing all cited works numerically.
"""
        else:
            _no_refs = "(no references — omit \\bibliography and \\bibliographystyle commands)"
            _exp_section_line = (
                "  \\\\section{{Experiments}}\\\\label{{sec:experiments}}"
                if exp_summary else
                "  (no Experiments section — experiments were not run)"
            )
            user_message = f"""\
Write a complete LaTeX research paper based on these artifacts:

Title: {title}
Domain: {brief.domain}
Main theorem: {theory_state.formal_statement}
Informal: {theory_state.informal_statement}

Proven lemmas (use in Proofs section):
{proven_proofs or "(no proven lemmas)"}

Experimental results:
{exp_summary or "(no experiments run — do NOT include an Experiments section)"}

Key references to cite (use EXACTLY these \\cite{{}} keys — they match the references.bib file):
{citations or _no_refs}

Write the full paper body (abstract through conclusion) in LaTeX.
Use \\begin{{theorem}}...\\end{{theorem}} environments.
For every lemma listed above, copy its \\begin{{lemma}}[Name]\\label{{lem:id}}...\\end{{lemma}}
and \\begin{{proof}}%%PROOF:id%%\\end{{proof}} blocks EXACTLY as given — preserve the
display name in square brackets, the \\label{{lem:id}}, and the %%PROOF:id%% placeholder
(it will be filled in automatically).  Use \\ref{{lem:id}} to cross-reference lemmas.
For the main theorem, write its proof in full inside \\begin{{proof}}...\\end{{proof}}.

MANDATORY SECTIONS — you MUST include ALL of the following \\section{{}} commands with
their \\label{{}} exactly as shown, in this order. Every section the introduction
roadmap mentions must actually appear in the paper body:

  \\section{{Introduction}}\\label{{sec:introduction}}
  \\section{{Preliminaries}}\\label{{sec:preliminaries}}
  \\section{{Main Results}}\\label{{sec:main_results}}
{_exp_section_line}
  \\section{{Related Work}}\\label{{sec:related_work}}
  \\section{{Limitations}}\\label{{sec:limitations}}
  \\section{{Conclusion}}\\label{{sec:conclusion}}

Do NOT reference a section with \\ref{{}} or \\cref{{}} unless you are going to write it.
If a section has little content, write at least two sentences rather than omitting it.
"""

        try:
            text, tokens = await self.run_agent_loop(
                task, user_message, max_turns=settings.writer_max_turns
            )

            if fmt == "markdown":
                paper_content = self._extract_markdown(text, citekey_to_num, md_references)
                # If the extracted content is clearly not the paper (LLM spent
                # all turns on tool calls), request the actual paper body now.
                if not self._looks_like_paper_markdown(paper_content):
                    logger.warning("WriterAgent: loop produced no Markdown body — requesting paper now")
                    text, extra = await self._request_paper_body(task, user_message, fmt)
                    tokens["input"] += extra.get("input", 0)
                    tokens["output"] += extra.get("output", 0)
                    paper_content = self._extract_markdown(text, citekey_to_num, md_references)
                output_key = "latex_paper"  # reuse existing key for compatibility
            else:
                latex_body = self._extract_latex(text)
                # If the body doesn't look like a real paper (LLM used all turns
                # on citation_manager calls and never wrote the paper), make one
                # explicit follow-up call with no tools to generate the content.
                if not self._looks_like_paper_latex(latex_body):
                    logger.warning("WriterAgent: loop produced no LaTeX body — requesting paper now")
                    text, extra = await self._request_paper_body(task, user_message, fmt)
                    tokens["input"] += extra.get("input", 0)
                    tokens["output"] += extra.get("output", 0)
                    latex_body = self._extract_latex(text)
                # Strip any spurious Experiments section when experiments are disabled.
                if not exp_summary:
                    latex_body = re.sub(
                        r"(?s)\\section\*?\{[Ee]xperiments?[^\}]*\}.*?"
                        r"(?=\\section|\\appendix|\\bibliography|\\end\{document\}|$)",
                        "",
                        latex_body,
                    )
                # Pass 1: expand %%PROOF:lemma_id%% placeholders with full proof text.
                latex_body = self._replace_proof_placeholders(
                    latex_body, theory_state, arxiv_to_citekey
                )
                # Pass 2: inject proofs for any lemma the LLM forgot to emit at all.
                latex_body = self._inject_missing_proofs(latex_body, theory_state)
                abstract_text = self._extract_abstract(text) or (
                    f"We present theoretical results in {brief.domain}. "
                    f"Our main contribution is: {theory_state.informal_statement[:200]}"
                )
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

        # 5b. Strip any \begin{thebibliography}...\end{thebibliography} blocks and
        #     associated \bibliographystyle / \bibliography commands written by the
        #     LLM.  A single, clean bibliography is always appended by
        #     _generate_thebibliography() after this method returns, so any
        #     LLM-generated copy would produce a duplicate.
        text = re.sub(
            r"(?s)\\begin\{thebibliography\}.*?\\end\{thebibliography\}", "", text
        )
        # Also strip standalone \bibliographystyle{...} and \bibliography{...} lines
        text = re.sub(r"(?m)^[ \t]*\\bibliographystyle\{[^}]*\}[ \t]*\n?", "", text)
        text = re.sub(r"(?m)^[ \t]*\\bibliography\{[^}]*\}[ \t]*\n?", "", text)

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
        text = WriterAgent._repair_brace_balance(text)

        # 8. Fix [lemma_id] / [lemma\_id] cross-references written by the LLM
        #    (e.g. in theorem proofs and prose) → Lemma~\ref{lem:lemma_id}.
        #    Require at least one underscore so normal math brackets are not touched.
        def _body_ref_repl(m: re.Match) -> str:  # type: ignore[type-arg]
            lid = m.group(1).replace(r"\_", "_")
            return f"Lemma~\\ref{{lem:{lid}}}"
        text = re.sub(
            r"(?<!\\)(?<!\{)\[([a-z][a-z0-9]*(?:(?:_|\\_)[a-z0-9]+)+)\]",
            _body_ref_repl, text,
        )

        return text.strip()

    @staticmethod
    def _clean_proof_text(pt: str, arxiv_to_citekey: dict | None = None) -> str:
        """Convert raw Prover output to clean LaTeX-compatible proof body.

        Strips:
        - The "Proof Strategy / Goals" preamble section (before the first
          standalone ``---`` separator line, or before the second ``###`` header
          when no ``---`` is present).
        - Trailing standalone ``---`` markers.
        - Markdown ``###`` headers inside the formal proof.
        - ``**bold**`` / ``*italic*`` markers → converted to ``\\textit{}``.
        - Numbered/bulleted list prefixes (``1.  **Title**: text`` →
          ``\\textit{Title.} text``; plain ``1.  text`` → plain ``text``).
        - ``Cited from: <arxiv_id>.`` → ``Refer to \\cite{key}.``.
        - ``[lemma_id]`` and ``[lemma\\_id]`` cross-references →
          ``Lemma~\\ref{lem:lemma_id}``.
        - ``$$...$$`` display-math → ``\\[...\\]``.
        """
        import re

        arxiv_to_citekey = arxiv_to_citekey or {}

        # ── Step 1: extract the formal proof body ─────────────────────────────
        # The Prover structures its output as:
        #   [Strategy/Goals section]
        #   ---
        #   [Formal Proof section]          ← we want this
        #   ---                             ← trailing separator (strip)
        #
        # When no '---' is present, a second '###' header marks the formal part.

        _SEP = re.compile(r"\n[ \t]*---+[ \t]*\n")
        sep_m = _SEP.search(pt)
        if sep_m:
            # Take everything after the first --- separator
            formal = pt[sep_m.end():]
            # Strip any trailing standalone --- at the very end
            formal = re.sub(r"\n[ \t]*---+[ \t]*\s*$", "", formal)
        else:
            # No --- separator: look for a second ### header
            _HDR = re.compile(r"(?m)^#{1,3}\s+\S[^\n]*$")
            hdrs = list(_HDR.finditer(pt))
            if len(hdrs) >= 2:
                formal = pt[hdrs[1].end():].lstrip("\n")
            elif len(hdrs) == 1:
                # Only one header — take everything after it
                formal = pt[hdrs[0].end():].lstrip("\n")
            else:
                formal = pt  # no structure at all — use as-is

        pt = formal.strip()

        # ── Step 2: strip leading ### section header of the formal part ───────
        pt = re.sub(r"^#{1,3}[^\n]*\n", "", pt.lstrip()).strip()

        # ── Step 3: strip any remaining ### headers inside the proof ──────────
        pt = re.sub(r"(?m)^#{1,3}[^\n]*\n?", "", pt)

        # ── Step 4: convert numbered/bulleted list items ───────────────────────
        # "1.  **Title**: rest" or "1.  **Title.** rest" → \textit{Title.} rest
        # Prefix with \n\n so each item becomes its own LaTeX paragraph.
        pt = re.sub(
            r"(?m)^\s*\d+\.\s+\*\*([^*:]+?)\*\*[:.]\s*", r"\n\n\\textit{\1.}\\ ", pt
        )
        # "-  **Title**: rest" → \textit{Title.} rest
        pt = re.sub(
            r"(?m)^\s*[-*]\s+\*\*([^*:]+?)\*\*[:.]\s*", r"\n\n\\textit{\1.}\\ ", pt
        )
        # Plain "1.  text" or "-  text" — strip bullet/number prefix, ensure paragraph break.
        pt = re.sub(r"(?m)^\s*\d+\.\s{1,4}", "\n\n", pt)
        pt = re.sub(r"(?m)^\s*[-*]\s+", "\n\n", pt)

        # ── Step 5: convert remaining **bold** / *italic* ─────────────────────
        pt = re.sub(r"\*\*([^*\n]+)\*\*", r"\\textit{\1}", pt)
        pt = re.sub(r"\*([^*\n]+)\*",     r"\\textit{\1}", pt)

        # ── Step 6: "Cited from: <arxiv_id>." → \cite{key} ───────────────────
        def _cited_repl(m: re.Match) -> str:  # type: ignore[type-arg]
            raw = m.group(1).strip().rstrip(".")
            base = raw.split("v")[0]
            key = arxiv_to_citekey.get(base) or arxiv_to_citekey.get(raw) or ""
            return f"Refer to \\cite{{{key or base}}}.\n"
        pt = re.sub(r"(?m)^Cited from:\s*([^\n]+)\s*\n?", _cited_repl, pt)

        # ── Step 7: [lemma_id] / [lemma\_id] → Lemma~\ref{lem:lemma_id} ──────
        # Require at least one underscore to avoid matching normal math brackets.
        # Negative lookbehind for '\' and '{' to avoid \cite[...] and similar.
        def _ref_repl(m: re.Match) -> str:  # type: ignore[type-arg]
            lid = m.group(1).replace(r"\_", "_")
            return f"Lemma~\\ref{{lem:{lid}}}"
        pt = re.sub(
            r"(?<!\\)(?<!\{)\[([a-z][a-z0-9]*(?:(?:_|\\_)[a-z0-9]+)+)\]",
            _ref_repl, pt,
        )

        # ── Step 8: $$...$$ → \[...\] ─────────────────────────────────────────
        pt = re.sub(
            r"\$\$(.*?)\$\$",
            lambda m: "\\[\n" + m.group(1).strip() + "\n\\]",
            pt,
            flags=re.DOTALL,
        )

        # ── Step 9: collapse excessive blank lines ─────────────────────────────
        pt = re.sub(r"\n{3,}", "\n\n", pt)

        return pt.strip()

    @staticmethod
    def _replace_proof_placeholders(
        text: str,
        theory_state,  # type: ignore[override]
        arxiv_to_citekey: dict | None = None,
    ) -> str:
        """Pass 1: replace every %%PROOF:lemma_id%% with the full stored proof_text."""
        import re

        if not (theory_state and getattr(theory_state, "proven_lemmas", None)):
            return text

        arxiv_to_citekey = arxiv_to_citekey or {}

        prov_of: dict[str, str] = {}
        src_of:  dict[str, str] = {}
        for pp in getattr(theory_state, "proof_plan", None) or []:
            prov_of[pp.lemma_id] = pp.provenance
            src_of[pp.lemma_id]  = getattr(pp, "source", "") or ""

        def replacer(m: re.Match) -> str:  # type: ignore[type-arg]
            lid = m.group(1)
            rec = theory_state.proven_lemmas.get(lid)
            if rec and rec.proof_text:
                return WriterAgent._clean_proof_text(rec.proof_text, arxiv_to_citekey)
            prov = prov_of.get(lid, "new")
            src  = src_of.get(lid, "")
            if prov == "known" and src:
                src_base = src.split("v")[0]
                ckey = arxiv_to_citekey.get(src_base) or arxiv_to_citekey.get(src) or ""
                cite = f"\\cite{{{ckey}}}" if ckey else f"\\cite{{{src}}}"
                return f"Refer to {cite}."
            return "(Proof sketch — see supplementary material.)"

        return re.sub(r"%%PROOF:([A-Za-z0-9_]+)%%", replacer, text)

    @staticmethod
    def _inject_missing_proofs(text: str, theory_state) -> str:  # type: ignore[override]
        """Post-processing: ensure every lemma/auxlemma environment has a proof block.

        The LLM sometimes omits \\begin{proof}...\\end{proof} for low-confidence
        lemmas, placing the \\textcolor{orange} unverified marker directly after
        \\end{lemma} instead.  This method scans the extracted LaTeX body and,
        for each lemma that lacks a following proof, injects one using the stored
        proof_text from theory_state.proven_lemmas.
        """
        import re

        if not (theory_state and getattr(theory_state, "proven_lemmas", None)):
            return text

        # Build per-lemma proof text using the shared cleaner
        proof_map: dict[str, str] = {}
        verified_map: dict[str, bool] = {}
        for lid, rec in theory_state.proven_lemmas.items():
            pt = WriterAgent._clean_proof_text(rec.proof_text or "")
            if pt:
                proof_map[lid] = pt
            verified_map[lid] = bool(getattr(rec, "verified", False))

        prov_map: dict[str, str] = {}
        src_map:  dict[str, str] = {}
        for pp in getattr(theory_state, "proof_plan", None) or []:
            prov_map[pp.lemma_id] = pp.provenance
            src_map[pp.lemma_id]  = getattr(pp, "source", "") or ""

        _UNVERIFIED = r"\textcolor{orange}{\textbf{[Unverified step — see discussion]}}"

        def make_proof_block(lid: str) -> str:
            body = proof_map.get(lid, "")
            if not body:
                prov = prov_map.get(lid, "new")
                src  = src_map.get(lid, "")
                body = f"See {src}." if (prov == "known" and src) else \
                       "(Proof sketch — see supplementary material.)"
            suffix = f"\n{_UNVERIFIED}" if not verified_map.get(lid, True) else ""
            return f"\\begin{{proof}}\n{body}\n\\end{{proof}}{suffix}"

        LEMMA_BEGIN = re.compile(
            r"\\begin\{(?:lemma|auxlemma)\}"
            r"(?:\[([^\]]*)\])?"               # group 1: optional display name (may be pretty)
            r"(?:\\label\{lem:([^}]*)\})?"     # group 2: optional \label{lem:id}
        )
        LEMMA_END   = re.compile(r"\\end\{(?:lemma|auxlemma)\}")
        PROOF_BEGIN = re.compile(r"\\begin\{proof\}")
        # Noise between \end{lemma} and \begin{proof}:
        # whitespace, \textcolor{X}{\textbf{Y}}, \clearpage
        NOISE = re.compile(
            r"(?:\s+|\\textcolor\{[^}]*\}\{(?:[^{}]|\{[^{}]*\})*\}|\\clearpage\b)*"
        )

        parts: list[str] = []
        pos = 0
        while True:
            m_begin = LEMMA_BEGIN.search(text, pos)
            if not m_begin:
                parts.append(text[pos:])
                break

            # Prefer the \label{lem:id} (group 2) as the authoritative ID;
            # fall back to reverse-converting the display name (group 1) from
            # "Title Case" back to snake_case, for cases where the LLM wrote
            # \begin{lemma}[Pretty Name] without an explicit label.
            label_id    = (m_begin.group(2) or "").strip()
            display_name = (m_begin.group(1) or "").strip()
            lemma_id = label_id or display_name.lower().replace(" ", "_")

            m_end = LEMMA_END.search(text, m_begin.end())
            if not m_end:
                parts.append(text[pos:])
                break

            # Emit text up to and including \end{lemma}
            parts.append(text[pos : m_end.end()])
            pos = m_end.end()

            # Skip noise (whitespace + misplaced \textcolor markers)
            m_noise = NOISE.match(text, pos)
            scan_pos = m_noise.end() if (m_noise and m_noise.end() > pos) else pos

            if PROOF_BEGIN.match(text, scan_pos):
                # Proof already present — leave this lemma's trailing text intact
                continue

            # No proof: inject one and swallow the misplaced noise/markers
            parts.append(f"\n{make_proof_block(lemma_id)}\n")
            pos = scan_pos

        return "".join(parts)

    @staticmethod
    @staticmethod
    def _repair_brace_balance(text: str) -> str:
        """Append missing closing braces so that LaTeX brace depth never goes negative."""
        depth = 0
        for ch in text:
            if ch == "{":
                depth += 1
            elif ch == "}" and depth > 0:
                depth -= 1
        if depth > 0:
            text += "}" * depth
        return text

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

    @staticmethod
    def _looks_like_paper_latex(body: str) -> bool:
        """Return True if *body* contains real paper structure, not just a planning sentence."""
        markers = (r"\section", r"\begin{theorem}", r"\begin{proof}",
                   r"\begin{lemma}", r"\begin{abstract}", r"\maketitle")
        return any(m in body for m in markers)

    @staticmethod
    def _looks_like_paper_markdown(body: str) -> bool:
        """Return True if *body* contains real Markdown paper structure."""
        markers = ("## ", "**Theorem", "**Lemma", "**Proof", "# Introduction")
        return any(m in body for m in markers)

    async def _request_paper_body(
        self, task: "Task", original_user_message: str, fmt: str
    ) -> tuple[str, dict[str, int]]:
        """Make one final LLM call (no tools) to generate the actual paper body.

        Called when run_agent_loop exhausted its turns doing tool calls and
        never produced the paper content.  The session history already contains
        the citation tool results, so we append a follow-up user turn asking
        the LLM to write the paper now.
        """
        from eurekaclaw.config import settings

        follow_up = (
            "You have now gathered all the citation data you need. "
            "Write the COMPLETE paper body now — do not call any more tools. "
        )
        if fmt == "markdown":
            follow_up += (
                "Output the full Markdown document starting with the YAML front matter "
                "block (---) followed by all sections (## Abstract, ## Introduction, "
                "## Preliminaries, ## Main Results, ## Experiments, ## Related Work, "
                "## Conclusion)."
            )
        else:
            follow_up += (
                "Output the full LaTeX paper body (from \\section{Introduction} through "
                "\\section{Conclusion}) inside a ```latex code fence. "
                "Include all theorem environments, proofs, and \\cite{} references."
            )

        # Append the follow-up to the existing session so the LLM has the tool
        # results in context, then call without tools.
        self.session.add_user(follow_up)
        system = self.build_system_prompt(task)
        response = await self._call_model(
            system=system,
            messages=self.session.get_messages(),
            tools=None,  # no tools — force a text response
            max_tokens=settings.max_tokens_agent,
        )
        text_parts = [b.text for b in response.content if b.type == "text"]
        text = " ".join(text_parts)
        usage = {"input": 0, "output": 0}
        if response.usage:
            usage["input"] = response.usage.input_tokens
            usage["output"] = response.usage.output_tokens
        return text, usage

    def _extract_markdown(
        self,
        text: str,
        citekey_to_num: "dict[str, int] | None" = None,
        md_references: str = "",
    ) -> str:
        """Extract Markdown content, removing code fences if present, then
        strip LaTeX-only constructs that are not valid in Markdown and convert
        \\cite{key} references to numbered [N] citations."""
        import re

        for fence in ("```markdown", "```md"):
            if fence in text:
                start = text.index(fence) + len(fence)
                end = text.index("```", start) if "```" in text[start:] else len(text)
                text = text[start:end].strip()
                break

        # ── Citations: \cite{key} / \citet{key} / \citep{key} → [N] ──────────
        citekey_to_num = citekey_to_num or {}
        if citekey_to_num:
            def _cite_repl(m: re.Match) -> str:  # type: ignore[type-arg]
                key = m.group(1).strip()
                num = citekey_to_num.get(key)
                return f"[{num}]" if num is not None else f"[{key}]"
            text = re.sub(r"\\cite[tp]?\s*\{([^}]+)\}", _cite_repl, text)
        else:
            # No key map — at least strip the \cite command to bare brackets
            text = re.sub(r"\\cite[tp]?\s*\{([^}]+)\}", r"[\1]", text)

        # ── QED / proof-end markers ───────────────────────────────────────────
        # Replace \hfill\square / \hfill\blacksquare → □ (QED marker)
        text = re.sub(r"\\hfill\s*\\(?:square|blacksquare|Box)\b", "□", text)
        # \hfill\infty used erroneously as end marker → □ (before generic \hfill strip)
        text = re.sub(r"\\hfill\s*\\infty\b", "□", text)
        # Drop remaining \hfill, keep whatever follows
        text = re.sub(r"\\hfill\s*", "", text)
        # Bare \square or \blacksquare outside math delimiters → □
        text = re.sub(r"(?<!\$)\\(?:square|blacksquare|Box)\b(?!\$)", "□", text)

        # ── Layout-only LaTeX commands (no Markdown equivalent) ───────────────
        text = re.sub(
            r"\\(?:newpage|clearpage|linebreak|pagebreak|noindent|medskip|bigskip|smallskip)\b",
            "",
            text,
        )
        text = re.sub(r"\\[vh]space\s*\{[^}]*\}", "", text)

        # ── Text formatting outside math → Markdown equivalents ───────────────
        text = re.sub(r"\\textcolor\s*\{[^}]*\}\s*\{([^}]*)\}", r"\1", text)
        text = re.sub(r"\\textbf\s*\{([^}]*)\}", r"**\1**", text)
        text = re.sub(r"\\(?:textit|emph)\s*\{([^}]*)\}", r"*\1*", text)

        # ── References section ────────────────────────────────────────────────
        # Append a numbered references list if the LLM didn't write one and we
        # have references to list.
        if md_references:
            has_refs = bool(re.search(r"(?mi)^##\s+references?\s*$", text))
            if not has_refs:
                text = text.rstrip() + "\n\n## References\n\n" + md_references

        return text
