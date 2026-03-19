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

    def _make_orchestrator(self, domain: str = "") -> MetaOrchestrator:
        domain_plugin = resolve_domain(domain) if domain else None
        if domain_plugin:
            logger.info("Auto-detected domain plugin: %s", domain_plugin.name)
        return MetaOrchestrator(bus=self.bus, domain_plugin=domain_plugin)

    @property
    def orchestrator(self) -> MetaOrchestrator:
        if not self._orchestrator:
            self._orchestrator = self._make_orchestrator()
        return self._orchestrator

    async def run(self, input_spec: InputSpec) -> ResearchOutput:
        """Run a complete research session from an InputSpec."""
        # Build orchestrator with domain plugin resolved from the spec's domain
        if not self._orchestrator:
            self._orchestrator = self._make_orchestrator(input_spec.domain or "")
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
    import subprocess

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Write references.bib BEFORE compiling so bibtex can find it
    if result.bibliography_json:
        import json as _json
        bib_data = _json.loads(result.bibliography_json)
        bibtex_str = bib_data.get("bibtex", "")
        if not bibtex_str:
            bibtex_str = _generate_bibtex(bib_data.get("papers", []))
        if bibtex_str:
            (out / "references.bib").write_text(bibtex_str, encoding="utf-8")
            logger.info("BibTeX saved to %s/references.bib", out)

    if result.latex_paper:
        if settings.output_format == "markdown":
            (out / "paper.md").write_text(result.latex_paper, encoding="utf-8")
            logger.info("Markdown paper saved to %s/paper.md", out)
        else:
            tex_path = out / "paper.tex"
            tex_path.write_text(result.latex_paper, encoding="utf-8")
            logger.info("LaTeX paper saved to %s/paper.tex", out)
            _compile_pdf(tex_path, settings.latex_bin)

    if result.theory_state_json:
        (out / "theory_state.json").write_text(result.theory_state_json, encoding="utf-8")

    if result.experiment_result_json:
        (out / "experiment_result.json").write_text(result.experiment_result_json, encoding="utf-8")

    if result.research_brief_json:
        (out / "research_brief.json").write_text(result.research_brief_json, encoding="utf-8")

    return out


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


def _compile_pdf(tex_path: Path, latex_bin: str = "pdflatex") -> None:
    """Compile LaTeX to PDF using the standard bibliography sequence:
    pdflatex → bibtex → pdflatex → pdflatex.

    bibtex is only invoked when a references.bib file exists next to paper.tex,
    preventing spurious errors on papers with no bibliography.
    """
    import subprocess

    out_dir = tex_path.parent.resolve()
    tex_abs = tex_path.resolve()
    pdf_path = out_dir / tex_path.with_suffix(".pdf").name
    bib_path = out_dir / "references.bib"

    latex_cmd = [
        latex_bin, "-interaction=nonstopmode",
        "-output-directory", str(out_dir),
        str(tex_abs),
    ]

    try:
        # Pass 1 — generate .aux
        subprocess.run(latex_cmd, capture_output=True, check=False, cwd=out_dir)

        # bibtex pass — only when references.bib is present
        if bib_path.exists():
            aux_stem = tex_path.stem  # "paper"
            bibtex_result = subprocess.run(
                ["bibtex", aux_stem],
                capture_output=True, check=False, cwd=out_dir,
            )
            if bibtex_result.returncode != 0:
                logger.warning(
                    "bibtex exited %d — bibliography may be incomplete:\n%s",
                    bibtex_result.returncode,
                    bibtex_result.stdout.decode(errors="replace")[-500:],
                )

        # Passes 2 & 3 — resolve citations and cross-references
        subprocess.run(latex_cmd, capture_output=True, check=False, cwd=out_dir)
        subprocess.run(latex_cmd, capture_output=True, check=False, cwd=out_dir)

        if pdf_path.exists():
            logger.info("PDF compiled: %s", pdf_path)
        else:
            logger.warning("pdflatex produced no PDF — check %s/paper.log", out_dir)
    except FileNotFoundError as e:
        logger.warning("PDF generation skipped: binary not found (%s)", e)


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
