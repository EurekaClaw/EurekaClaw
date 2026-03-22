"""EurekaSession — top-level entry point for a research session."""

from __future__ import annotations

import asyncio
import logging
import uuid
from pathlib import Path

from eurekaclaw.config import settings
from eurekaclaw.domains import resolve_domain
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
from eurekaclaw.types.tasks import InputSpec, ResearchOutput

logger = logging.getLogger(__name__)


class EurekaSession:
    """A complete EurekaClaw research session.

    Usage:
        session = EurekaSession()
        result = asyncio.run(session.run_detailed("Prove that sample complexity of transformers..."))
        result = asyncio.run(session.run_exploration("sample complexity of transformers"))
    """

    def __init__(self, session_id: str | None = None) -> None:
        self.session_id = session_id or str(uuid.uuid4())
        self.bus = KnowledgeBus(self.session_id)
        self._orchestrator: MetaOrchestrator | None = None

    def _make_orchestrator(self, domain: str = "", selected_skills: list[str] | None = None) -> MetaOrchestrator:
        domain_plugin = resolve_domain(domain) if domain else None
        if domain_plugin:
            logger.info("Auto-detected domain plugin: %s", domain_plugin.name)
        return MetaOrchestrator(bus=self.bus, domain_plugin=domain_plugin, selected_skills=selected_skills)

    @property
    def orchestrator(self) -> MetaOrchestrator:
        if not self._orchestrator:
            self._orchestrator = self._make_orchestrator()
        return self._orchestrator

    async def run(self, input_spec: InputSpec) -> ResearchOutput:
        """Run a complete research session from an InputSpec."""
        # Infer domain from conjecture/query when the caller left it empty.
        # This ensures resolve_domain() can match a domain plugin (e.g. MABDomainPlugin)
        # regardless of which entry point (CLI, Python API, UI) was used.
        if not input_spec.domain:
            text = input_spec.conjecture or input_spec.query or ""
            inferred = _infer_domain(text)
            input_spec = input_spec.model_copy(update={"domain": inferred})
            logger.info("Domain inferred from query: %r → %r", text[:60], inferred)

        if not self._orchestrator:
            self._orchestrator = self._make_orchestrator(input_spec.domain, selected_skills=input_spec.selected_skills)
        return await self._orchestrator.run(input_spec)

    async def run_detailed(self, conjecture: str, domain: str = "") -> ResearchOutput:
        """Level 1 mode: user provides a specific conjecture."""
        resolved_domain = domain or _infer_domain(conjecture)
        spec = InputSpec(
            mode="detailed",
            conjecture=conjecture,
            domain=resolved_domain,
            query=conjecture,
        )
        return await self.run(spec)

    async def run_from_papers(self, paper_ids: list[str], domain: str) -> ResearchOutput:
        """Level 2 mode: user provides reference papers for gap exploration."""
        spec = InputSpec(
            mode="reference",
            paper_ids=paper_ids,
            domain=domain,
            query=f"Identify research gaps in {domain}",
        )
        return await self.run(spec)

    async def run_exploration(self, domain: str, query: str = "") -> ResearchOutput:
        """Level 3 mode: open exploration of a domain."""
        spec = InputSpec(
            mode="exploration",
            domain=domain,
            query=query or f"Survey the frontier of {domain} and propose novel directions",
        )
        return await self.run(spec)


def run_research(conjecture: str, domain: str = "") -> ResearchOutput:
    """Synchronous entry point. Blocks until the session completes."""
    session = EurekaSession()
    return asyncio.run(session.run_detailed(conjecture, domain))


def save_artifacts(result: ResearchOutput, out_dir: str | Path) -> Path:
    """Write research artifacts to disk and compile a PDF if applicable.

    Shared by the CLI and the UI server so both produce identical output
    layouts without circular imports.

    Returns the resolved output directory path.
    """
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Write references.bib for user reference (not used for compilation —
    # the paper uses an inline \begin{thebibliography} block instead).
    if result.bibliography_json:
        import json as _json
        bib_data = _json.loads(result.bibliography_json)
        bibtex_str = bib_data.get("bibtex", "")
        if not bibtex_str:
            bibtex_str = _generate_bibtex(bib_data.get("papers", []))
        if bibtex_str:
            (out / "references.bib").write_text(bibtex_str, encoding="utf-8")
            logger.info("BibTeX saved to %s/references.bib (reference only)", out)

    if result.latex_paper:
        if settings.output_format == "markdown":
            (out / "paper.md").write_text(result.latex_paper, encoding="utf-8")
            logger.info("Markdown paper saved to %s/paper.md", out)
        else:
            # Copy eureka.cls, logo-claw.png, smile.sty, and fonts/ so pdflatex can find them
            _copy_template_assets(out)
            tex_path = out / "paper.tex"
            tex_path.write_text(result.latex_paper, encoding="utf-8")
            logger.info("LaTeX paper saved to %s/paper.tex", out)
            # Insert stubs for any \ref{sec:*} labels the LLM referenced but never wrote
            _stub_missing_sections(tex_path)
            # Fix any cite keys that don't have a matching \bibitem in the tex file
            _fix_missing_citations(tex_path)
            try:
                _compile_pdf(tex_path, settings.latex_bin)
            except Exception as exc:
                logger.warning("PDF generation skipped: %s", exc)

    if result.theory_state_json:
        (out / "theory_state.json").write_text(result.theory_state_json, encoding="utf-8")

    if result.experiment_result_json:
        (out / "experiment_result.json").write_text(result.experiment_result_json, encoding="utf-8")

    if result.research_brief_json:
        (out / "research_brief.json").write_text(result.research_brief_json, encoding="utf-8")

    return out


def _copy_template_assets(out_dir: Path) -> None:
    """Copy eureka.cls, logo-claw.png, and fonts/ into the output directory.

    These files must sit next to paper.tex so pdflatex can find them during
    compilation.  The template directory lives at eurekaclaw/eurekatemplate/.
    """
    import shutil

    template_dir = Path(__file__).parent / "eurekatemplate"
    if not template_dir.exists():
        logger.warning("Template directory not found: %s", template_dir)
        return

    for filename in ("eureka.cls", "logo-claw.png", "smile.sty"):
        src = template_dir / filename
        if src.exists():
            shutil.copy2(src, out_dir / filename)
        else:
            logger.warning("Template asset missing: %s", src)

    fonts_src = template_dir / "fonts"
    if fonts_src.exists():
        fonts_dst = out_dir / "fonts"
        if fonts_dst.exists():
            shutil.rmtree(fonts_dst)
        shutil.copytree(fonts_src, fonts_dst)


def _stub_missing_sections(tex_path: Path) -> None:
    r"""Insert minimal stub sections for \ref{sec:*} labels not defined in the file.

    When the LLM writes "Section~\ref{sec:related_work} discusses..." in the
    Introduction but never actually writes that section, pdflatex renders the
    cross-reference as "??".  This function detects dangling sec: refs and inserts
    a one-line stub \section{} before \end{document} so all refs resolve cleanly.
    """
    import re as _re

    text = tex_path.read_text(encoding="utf-8")

    defined_labels = set(_re.findall(r"\\label\{([^}]+)\}", text))
    referenced_sec = set(_re.findall(r"\\(?:ref|cref|Cref|autoref)\{(sec:[^}]+)\}", text))
    missing = referenced_sec - defined_labels
    if not missing:
        return

    _LABEL_TO_TITLE = {
        "sec:introduction":  "Introduction",
        "sec:related_work":  "Related Work",
        "sec:related":       "Related Work",
        "sec:preliminaries": "Preliminaries",
        "sec:background":    "Background",
        "sec:main_results":  "Main Results",
        "sec:results":       "Results",
        "sec:experiments":   "Experiments",
        "sec:experiment":    "Experiments",
        "sec:limitations":   "Limitations",
        "sec:limitation":    "Limitations",
        "sec:conclusion":    "Conclusion",
        "sec:conclusions":   "Conclusion",
        "sec:discussion":    "Discussion",
        "sec:proofs":        "Proofs",
        "sec:proof":         "Proofs",
        "sec:appendix":      "Appendix",
    }
    _ORDER = [
        "sec:related_work", "sec:related",
        "sec:limitations", "sec:limitation",
        "sec:conclusion", "sec:conclusions",
        "sec:discussion",
        "sec:experiments", "sec:experiment",
        "sec:proofs", "sec:proof",
        "sec:appendix",
    ]

    ordered_missing = sorted(
        missing,
        key=lambda lbl: (_ORDER.index(lbl) if lbl in _ORDER else len(_ORDER), lbl),
    )

    stubs = []
    for label in ordered_missing:
        title = _LABEL_TO_TITLE.get(label)
        if not title:
            key = label[4:] if label.startswith("sec:") else label
            title = " ".join(w.capitalize() for w in key.split("_"))
        stubs.append(
            f"\\section{{{title}}}\\label{{{label}}}\n"
            f"% This section stub was inserted automatically because the LLM\n"
            f"% referenced \\label{{{label}}} but never wrote the section.\n"
        )
        logger.info("_stub_missing_sections: inserted stub for \\label{%s}", label)

    stub_block = "\n".join(stubs) + "\n"
    text = text.replace(r"\end{document}", stub_block + r"\end{document}", 1)
    tex_path.write_text(text, encoding="utf-8")


def _fix_missing_citations(tex_path: Path) -> None:
    r"""Remove \cite{} keys that have no matching \bibitem in the same .tex file.

    Since the paper uses an inline \begin{thebibliography} block (generated by
    WriterAgent._generate_thebibliography), the valid cite keys are the \bibitem
    keys defined inside that block.  Any \cite{key} referencing a non-existent
    bibitem would render as [?] in the PDF.

    If no \begin{thebibliography} block exists (no references at all), all
    \cite{} commands are removed.
    """
    import re as _re

    tex_src = tex_path.read_text(encoding="utf-8", errors="replace")

    # Extract defined \bibitem keys from the tex file
    defined_keys: set[str] = set(_re.findall(r"\\bibitem\{([^}]+)\}", tex_src))

    _CITE_RE = _re.compile(r"\\(cite[a-z]*)(\[[^\]]*\]){0,2}\{([^}]*)\}")

    def _rebuild_cite(m: _re.Match) -> str:
        cmd = m.group(1)
        opts = m.group(2) or ""
        surviving = [k.strip() for k in m.group(3).split(",")
                     if k.strip() and k.strip() in defined_keys]
        if not surviving:
            return ""
        return f"\\{cmd}{opts}{{{', '.join(surviving)}}}"

    cleaned = _CITE_RE.sub(_rebuild_cite, tex_src)

    if cleaned != tex_src:
        tex_path.write_text(cleaned, encoding="utf-8")
        logger.info("_fix_missing_citations: removed unresolved \\cite{} keys in %s", tex_path.name)


def _generate_bibtex(papers: list[dict]) -> str:
    """Generate a BibTeX file string from a list of paper dicts."""
    entries: list[str] = []
    seen_keys: set[str] = set()
    for p in papers:
        title = p.get("title", "Unknown Title")
        authors = p.get("authors") or []
        year = p.get("year") or ""
        venue = p.get("venue") or ""
        arxiv_id = p.get("arxiv_id") or ""

        first_author = (authors[0].split()[-1] if authors else "unknown").lower()
        # Remove non-alphanumeric chars from key
        import re as _re
        base_key = _re.sub(r"[^a-z0-9]", "", first_author) + str(year)
        key = base_key
        suffix = 1
        while key in seen_keys:
            key = f"{base_key}{chr(ord('a') + suffix - 1)}"
            suffix += 1
        seen_keys.add(key)

        if arxiv_id:
            entry_type = "@article"
            venue_field = f"  journal = {{arXiv preprint arXiv:{arxiv_id}}},\n"
        elif venue:
            entry_type = "@inproceedings"
            venue_field = f"  booktitle = {{{venue}}},\n"
        else:
            entry_type = "@misc"
            venue_field = ""

        author_str = " and ".join(authors) if authors else "Unknown"
        entry = (
            f"{entry_type}{{{key},\n"
            f"  title = {{{{{title}}}}},\n"
            f"  author = {{{author_str}}},\n"
            f"  year = {{{year}}},\n"
            f"{venue_field}"
            f"}}"
        )
        entries.append(entry)
    return "\n\n".join(entries)


def _resolve_latex_bin(latex_bin: str = "pdflatex") -> str:
    """Find pdflatex binary, searching common TeX installation paths on macOS/Linux."""
    import shutil

    # If the configured value is an absolute path that exists, use it directly
    if Path(latex_bin).is_absolute() and Path(latex_bin).is_file():
        return latex_bin

    # Check if it's on PATH
    found = shutil.which(latex_bin)
    if found:
        return found

    # Search common TeX installation directories (macOS)
    _common_paths = [
        "/Library/TeX/texbin",
        "/usr/local/texlive/2025/bin/universal-darwin",
        "/usr/local/texlive/2024/bin/universal-darwin",
        "/usr/local/texlive/2023/bin/universal-darwin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        # Linux
        "/usr/bin",
        "/usr/local/texlive/2025/bin/x86_64-linux",
        "/usr/local/texlive/2024/bin/x86_64-linux",
    ]
    bin_name = Path(latex_bin).name
    for d in _common_paths:
        candidate = Path(d) / bin_name
        if candidate.is_file():
            logger.info("Found %s at %s", bin_name, candidate)
            return str(candidate)

    raise FileNotFoundError(
        f"'{bin_name}' not found on PATH or in common TeX directories. "
        f"Install TeX: brew install --cask basictex (macOS) or apt install texlive (Linux)"
    )


def _compile_pdf(tex_path: Path, latex_bin: str = "pdflatex") -> None:
    """Compile LaTeX to PDF using the eureka template.

    The paper uses an inline \\begin{thebibliography} block, so bibtex is not
    needed.  Two pdflatex passes are sufficient to resolve all cross-references
    (toc, cleveref, hyperref).
    """
    import subprocess

    resolved_bin = _resolve_latex_bin(latex_bin)

    out_dir = tex_path.parent.resolve()
    tex_abs = tex_path.resolve()
    pdf_path = out_dir / tex_path.with_suffix(".pdf").name

    latex_cmd = [
        resolved_bin, "-interaction=nonstopmode",
        "-output-directory", str(out_dir),
        str(tex_abs),
    ]

    # Pass 1 — full compile, generate .aux and .toc
    result1 = subprocess.run(latex_cmd, capture_output=True, check=False, cwd=out_dir)
    if result1.returncode != 0:
        log_tail = result1.stdout.decode(errors="replace")[-800:]
        logger.warning("pdflatex pass 1 warnings/errors:\n%s", log_tail)

    # Pass 2 — resolve cross-references (cleveref, hyperref, toc page numbers)
    subprocess.run(latex_cmd, capture_output=True, check=False, cwd=out_dir)

    if pdf_path.exists():
        logger.info("PDF compiled: %s", pdf_path)
    else:
        logger.warning("pdflatex produced no PDF — check %s/paper.log", out_dir)


def _infer_domain(query: str) -> str:
    """Heuristically infer the research domain from a query string."""
    query_lower = query.lower()
    domain_keywords = {
        # MAB / bandit theory
        "bandit": "mab",
        "multi-armed": "mab",
        "UCB": "mab",
        "ucb1": "mab",
        "thompson sampling": "mab",
        "regret bound": "mab",
        "exploration-exploitation": "mab",
        # ML theory
        "sample complexity": "machine learning theory",
        "generalization": "machine learning theory",
        "VC dimension": "machine learning theory",
        "PAC learning": "machine learning theory",
        "transformer": "deep learning theory",
        "attention": "deep learning theory",
        "graph": "graph theory",
        "topology": "topology",
        "probability": "probability theory",
        "concentration": "probability theory",
        "complexity": "computational complexity",
        "NP": "computational complexity",
        "optimization": "optimization theory",
        "convex": "convex optimization",
    }
    for kw, domain in domain_keywords.items():
        if kw.lower() in query_lower:
            return domain
    return "theoretical mathematics"
