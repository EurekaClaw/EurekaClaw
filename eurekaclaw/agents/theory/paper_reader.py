"""PaperReader — Stage 1 of the bottom-up proof pipeline.

Reads the bibliography from the KnowledgeBus and, for each paper,
extracts key theorems, lemmas, algorithms, and proof techniques that
are relevant to the research gap.  Results are stored as KnownResult
objects on TheoryState so later stages can cite them rather than
reproving them from scratch.
"""

from __future__ import annotations

import json
import logging
import re

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import KnownResult, TheoryState

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Regex patterns for math-section filtering
# ---------------------------------------------------------------------------

# Headings that almost certainly contain results (case-insensitive)
_RESULT_HEADING_RE = re.compile(
    r"^#+\s*("
    r"main\s+results?|key\s+results?|our\s+results?|"
    r"theorem|lemma|corollary|proposition|claim|"
    r"preliminar|background|notation|"
    r"technical\s+lemma|proof\s+(sketch\s+)?of|"
    r"appendix"
    r")",
    re.IGNORECASE | re.MULTILINE,
)

# Bold-label markers that Docling emits for theorem environments
_RESULT_BODY_RE = re.compile(
    r"\*\*(theorem|lemma|corollary|proposition|claim|remark|algorithm|definition)\b",
    re.IGNORECASE,
)


def _extract_math_sections(markdown: str, max_chars: int = 8000) -> str:
    """Return the subset of Docling Markdown that contains mathematical results.

    Strategy:
      1. Split on any heading (# / ## / ###).
      2. Keep a section if its heading matches known result-section names OR
         if its body contains bold theorem/lemma labels (Docling renders
         LaTeX theorem environments as **Theorem X.Y** ...).
      3. Concatenate kept sections up to *max_chars* so the LLM prompt stays
         tractable even for long papers.
    """
    # Split at every heading boundary, keeping the heading with its body.
    sections = re.split(r"(?=^#{1,3}\s)", markdown, flags=re.MULTILINE)

    kept: list[str] = []
    total = 0
    for section in sections:
        if total >= max_chars:
            break
        heading_line = section.split("\n", 1)[0]
        is_relevant = (
            _RESULT_HEADING_RE.search(heading_line)
            or _RESULT_BODY_RE.search(section)
        )
        if is_relevant:
            chunk = section.strip()
            kept.append(chunk)
            total += len(chunk)

    return "\n\n".join(kept)

EXTRACT_SYSTEM = """\
You are an expert mathematician and ML theorist reading a research paper.
Your task is to extract every key result that could be cited or reused in
a new proof — theorems, lemmas, corollaries, core algorithms, and named
proof techniques.

For each result output a JSON object with:
  "result_type": one of "theorem" | "lemma" | "corollary" | "algorithm" | "technique"
  "statement":   the mathematical statement (LaTeX notation where appropriate)
  "informal":    a one-sentence plain-language summary
  "proof_technique": the main technique or analytical tool used.  Examples span
                     many domains — bandit/RL theory: "self-normalized martingale
                     inequality", "elliptical potential lemma", "Freedman's
                     inequality"; optimization: "Lyapunov function argument",
                     "descent lemma", "proximal gradient analysis"; sampling /
                     diffusion: "Fokker-Planck equation", "log-Sobolev inequality",
                     "Langevin dynamics coupling"; probability: "Azuma-Hoeffding
                     inequality", "union bound", "coupling argument",
                     "Stein's method"; information theory: "data-processing
                     inequality", "KL divergence bound", "Fano's inequality"
  "notation":    a dict mapping non-standard symbols to their definitions

Return a JSON array of such objects (empty array if none found).
"""

EXTRACT_USER = """\
Paper title: {title}
Paper ID: {paper_id}
Research direction we are working on: {direction}

Abstract / excerpt:
{abstract}

Extract all key results that could be cited or reused in a proof about
the above research direction.  Return ONLY valid JSON (array).
"""

# How many papers to read in detail (most relevant first)
_MAX_PAPERS = 5


class PaperReader:
    """Stage 1: extract KnownResult objects from the session bibliography."""

    def __init__(self, bus: KnowledgeBus, client: LLMClient | None = None) -> None:
        self.bus = bus
        self.client: LLMClient = client or create_client()

    async def run(self, state: TheoryState, domain: str = "") -> TheoryState:
        """Populate state.known_results from the bibliography on the bus."""
        bib = self.bus.get_bibliography()
        if not bib or not bib.papers:
            logger.warning("PaperReader: no bibliography on bus — skipping")
            return state

        brief = self.bus.get_research_brief()
        direction = (
            brief.selected_direction.hypothesis
            if brief and brief.selected_direction
            else state.informal_statement or domain
        )
        # Sort by relevance, take top _MAX_PAPERS
        papers = sorted(bib.papers, key=lambda p: p.relevance_score, reverse=True)
        papers = papers[:_MAX_PAPERS]

        all_results: list[KnownResult] = []
        for paper in papers:
            results = await self._extract_from_paper(
                paper.paper_id, paper.title, paper.abstract, direction
            )
            all_results.extend(results)
            logger.info(
                "PaperReader: extracted %d results from '%s'",
                len(results), paper.title[:60],
            )

        state.known_results = all_results
        logger.info(
            "PaperReader: %d known results total from %d papers",
            len(all_results), len(papers),
        )
        return state

    async def _extract_from_paper(
        self,
        paper_id: str,
        title: str,
        abstract: str,
        direction: str,
    ) -> list[KnownResult]:
        if not abstract:
            return []
        try:
            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=settings.max_tokens_formalizer,
                system=EXTRACT_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": EXTRACT_USER.format(
                        title=title,
                        paper_id=paper_id,
                        direction=direction[:300],
                        abstract=abstract[:1500],
                    ),
                }],
            )
            text = response.content[0].text
            items = self._parse_json_array(text)
            return [
                KnownResult(
                    source_paper_id=paper_id,
                    source_paper_title=title,
                    result_type=item.get("result_type", "lemma"),
                    statement=item.get("statement", ""),
                    informal=item.get("informal", ""),
                    proof_technique=item.get("proof_technique", ""),
                    notation=item.get("notation", {}),
                )
                for item in items
                if item.get("statement")
            ]
        except Exception as e:
            logger.warning("PaperReader: extraction failed for '%s': %s", title[:50], e)
            return []

    async def _extract_from_paper_pdf(
        self,
        paper_id: str,
        title: str,
        arxiv_id: str,
        direction: str,
    ) -> list[KnownResult]:
        """Fetch the full paper PDF from arXiv, parse it with Docling, filter
        to theorem/lemma-bearing sections, then run the LLM extractor over
        that rich excerpt.

        This replaces the abstract-only path in ``_extract_from_paper`` and
        typically yields far more extracted results because theorems and proof
        sketches appear in the body, not the abstract.

        Pipeline:
          1. Build the arXiv PDF URL from *arxiv_id*.
          2. Pass the URL directly to Docling — it handles the HTTP fetch,
             PDF layout analysis, and exports clean Markdown with bold theorem
             labels preserved (e.g. ``**Theorem 3.1**``).
          3. ``_extract_math_sections`` filters the Markdown down to sections
             that contain mathematical results (≤ 8 000 chars).
          4. The existing LLM prompt (EXTRACT_SYSTEM / EXTRACT_USER) runs over
             the filtered excerpt and returns a JSON array of KnownResult dicts.

        Falls back gracefully if docling is not installed or the fetch fails.
        """
        try:
            from docling.document_converter import DocumentConverter
        except ImportError:
            logger.warning(
                "PaperReader: 'docling' not installed — cannot do PDF extraction. "
                "Install with: pip install 'eurekaclaw[pdf]'"
            )
            return []

        if not arxiv_id:
            logger.debug(
                "PaperReader: no arxiv_id for '%s', skipping PDF extraction", title[:50]
            )
            return []

        pdf_url = f"https://arxiv.org/pdf/{arxiv_id}"
        logger.info("PaperReader: fetching PDF via Docling — %s", pdf_url)
        try:
            # DocumentConverter.convert() accepts a URL string directly;
            # Docling downloads the PDF, runs its layout pipeline, and returns
            # a structured DoclingDocument.
            converter = DocumentConverter()
            result = converter.convert(pdf_url)
            markdown = result.document.export_to_markdown()
        except Exception as e:
            logger.warning(
                "PaperReader: Docling conversion failed for '%s' (%s): %s",
                title[:50], arxiv_id, e,
            )
            return []

        excerpt = _extract_math_sections(markdown)
        if not excerpt.strip():
            logger.debug(
                "PaperReader: no theorem sections found in '%s' after Docling parse",
                title[:50],
            )
            return []

        logger.info(
            "PaperReader: %d chars of theorem sections extracted from '%s'",
            len(excerpt), title[:60],
        )
        try:
            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=4096,
                system=EXTRACT_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": EXTRACT_USER.format(
                        title=title,
                        paper_id=paper_id,
                        direction=direction[:300],
                        # Pass the theorem-section excerpt in place of the
                        # abstract; EXTRACT_USER labels this field
                        # "Abstract / excerpt" so the prompt still reads well.
                        abstract=excerpt[:6000],
                    ),
                }],
            )
            text = response.content[0].text
            items = self._parse_json_array(text)
            return [
                KnownResult(
                    source_paper_id=paper_id,
                    source_paper_title=title,
                    result_type=item.get("result_type", "theorem"),
                    statement=item.get("statement", ""),
                    informal=item.get("informal", ""),
                    proof_technique=item.get("proof_technique", ""),
                    notation=item.get("notation", {}),
                )
                for item in items
                if item.get("statement")
            ]
        except Exception as e:
            logger.warning(
                "PaperReader: LLM extraction failed for '%s': %s", title[:50], e
            )
            return []

    def _parse_json_array(self, text: str) -> list[dict]:
        for start_delim, end_delim in [("```json", "```"), ("[", None)]:
            try:
                if start_delim in text:
                    start = text.index(start_delim) + len(start_delim)
                    if end_delim:
                        end = text.index(end_delim, start)
                        data = json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("]") + 1
                        data = json.loads(text[text.index("["):end])
                    return data if isinstance(data, list) else []
            except (json.JSONDecodeError, ValueError):
                continue
        return []
