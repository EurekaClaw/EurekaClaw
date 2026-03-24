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
from collections import Counter

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import KnownResult, TheoryState

logger = logging.getLogger(__name__)

def _chunk_markdown(markdown: str, max_chunk_chars: int = 3500, max_chunks: int = 24) -> list[str]:
    """Split full-paper markdown into reasonably sized chunks for LLM reading.

    Preference order:
      1. Keep explicit heading-delimited sections intact when they fit.
      2. Split oversized sections on paragraph boundaries.
      3. Fall back to raw slicing only when needed.
    """
    if not markdown.strip():
        return []

    sections = [part.strip() for part in re.split(r"(?=^#{1,3}\s)", markdown, flags=re.MULTILINE) if part.strip()]
    if not sections:
        sections = [markdown.strip()]

    chunks: list[str] = []

    def _append_with_split(text: str) -> None:
        if len(chunks) >= max_chunks:
            return
        if len(text) <= max_chunk_chars:
            chunks.append(text)
            return

        paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
        current = ""
        for para in paragraphs:
            candidate = f"{current}\n\n{para}".strip() if current else para
            if len(candidate) <= max_chunk_chars:
                current = candidate
                continue
            if current:
                chunks.append(current)
                if len(chunks) >= max_chunks:
                    return
            if len(para) <= max_chunk_chars:
                current = para
            else:
                for i in range(0, len(para), max_chunk_chars):
                    chunks.append(para[i:i + max_chunk_chars].strip())
                    if len(chunks) >= max_chunks:
                        return
                current = ""
        if current and len(chunks) < max_chunks:
            chunks.append(current)

    current = ""
    for section in sections:
        if len(chunks) >= max_chunks:
            break
        candidate = f"{current}\n\n{section}".strip() if current else section
        if len(candidate) <= max_chunk_chars:
            current = candidate
            continue
        if current:
            _append_with_split(current)
            if len(chunks) >= max_chunks:
                break
        if len(section) <= max_chunk_chars:
            current = section
        else:
            _append_with_split(section)
            current = ""
    if current and len(chunks) < max_chunks:
        _append_with_split(current)

    return [chunk for chunk in chunks if chunk.strip()][:max_chunks]


def _dedupe_results(results: list[KnownResult]) -> list[KnownResult]:
    seen: set[str] = set()
    deduped: list[KnownResult] = []
    for item in results:
        key = re.sub(r"\s+", " ", item.statement).strip().lower()
        key = key[:240]
        if not key or key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


_SOFT_RESULT_CUES = (
    "theorem", "lemma", "corollary", "proposition", "claim", "result",
    "analysis", "proof", "bound", "regret", "sample complexity",
    "convergence", "upper bound", "lower bound", "concentration",
    "eluder", "width", "appendix", "technical", "confidence",
)


def _score_chunk(chunk: str, direction: str) -> int:
    text = chunk.lower()
    score = 0

    # Headings and theorem-environment style markers are strong signals.
    if re.search(r"^#{1,3}\s", chunk, flags=re.MULTILINE):
        score += 2
    if re.search(r"\b(theorem|lemma|corollary|proposition|claim)\b", text):
        score += 5
    if re.search(r"\*\*(theorem|lemma|corollary|proposition|claim)\b", text):
        score += 4

    # Broad theory-paper cues.
    for cue in _SOFT_RESULT_CUES:
        if cue in text:
            score += 1

    # Math density is a weak but useful signal.
    score += min(text.count("$$"), 3) * 2
    score += min(text.count("\\(") + text.count("\\["), 6)

    # Reward overlap with the current research direction.
    direction_tokens = re.findall(r"[a-zA-Z]{4,}", direction.lower())
    if direction_tokens:
        counts = Counter(direction_tokens)
        for token, _ in counts.most_common(12):
            if token in text:
                score += 2

    return score


def _select_candidate_chunks(
    chunks: list[str],
    direction: str,
    *,
    max_selected: int = 8,
) -> list[str]:
    """Soft-select the most promising chunks for result extraction.

    This is intentionally a broad ranking, not a hard theorem-only filter:
    chunks with headings, theorem cues, math density, or direction overlap rise
    to the top, but prose-heavy analysis sections can still survive.
    """
    if len(chunks) <= max_selected:
        return chunks

    ranked = sorted(
        enumerate(chunks),
        key=lambda item: (_score_chunk(item[1], direction), -item[0]),
        reverse=True,
    )
    keep_indices = sorted(idx for idx, _ in ranked[:max_selected])
    return [chunks[idx] for idx in keep_indices]

EXTRACT_SYSTEM = """\
You are an expert mathematician and ML theorist reading a research paper.
Your task is to extract every key result that could be cited or reused in
a new proof — theorems, lemmas, corollaries, core algorithms, and named
proof techniques.

For each result output a JSON object with:
  "result_type": one of "theorem" | "lemma" | "corollary" | "algorithm" | "technique"
  "theorem_content": the core theorem/lemma/result statement (LaTeX notation where appropriate)
  "assumptions": the main assumptions or scope conditions needed for the result
  "proof_idea":  a short description of the main proof idea / analytical route
  "reuse_judgment": one of:
                    "direct_reusable" — likely can be cited almost as-is
                    "adaptable" — useful but needs modification for our setting
                    "background_only" — conceptual context, not a direct ingredient
                    "unclear" — not enough evidence to decide
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

Also include a legacy "statement" field only if helpful; if omitted, the
system will fall back to "theorem_content".

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

# How many full-paper chunks to send to the extractor after soft screening
_MAX_PDF_CHUNKS_TO_EXTRACT = 8


def _normalize_result_type(raw: object) -> str:
    value = str(raw or "lemma").strip().lower()
    aliases = {
        "theorem": "theorem",
        "lemma": "lemma",
        "corollary": "corollary",
        "algorithm": "algorithm",
        "technique": "technique",
        "definition": "technique",
        "def": "technique",
        "method": "technique",
        "remark": "technique",
        "assumption": "technique",
        "proposition": "theorem",
        "claim": "lemma",
        "fact": "lemma",
        "observation": "lemma",
    }
    return aliases.get(value, "lemma")


def _normalize_notation(raw: object) -> dict[str, str]:
    if isinstance(raw, dict):
        return {str(k): str(v) for k, v in raw.items()}
    return {}


def _normalize_reuse_judgment(raw: object) -> str:
    value = str(raw or "unclear").strip().lower()
    aliases = {
        "direct_reusable": "direct_reusable",
        "direct": "direct_reusable",
        "cite": "direct_reusable",
        "adaptable": "adaptable",
        "adapted": "adaptable",
        "background_only": "background_only",
        "background": "background_only",
        "context_only": "background_only",
        "unclear": "unclear",
        "unknown": "unclear",
    }
    return aliases.get(value, "unclear")


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
        # Sort by relevance, take top _MAX_PAPERS for lightweight abstract pass
        papers = sorted(bib.papers, key=lambda p: p.relevance_score, reverse=True)
        target_abstract_papers = max(1, min(settings.paper_reader_abstract_papers, len(papers)))
        papers = papers[:target_abstract_papers]

        all_results: list[KnownResult] = []
        state.known_results = []
        self.bus.put_theory_state(state)
        pdf_successes = 0
        target_pdf_papers = max(0, min(settings.paper_reader_pdf_papers, len(papers)))
        for paper in papers:
            abstract_results = await self._extract_from_paper(
                paper.paper_id, paper.title, paper.abstract, direction
            )
            results = abstract_results

            if settings.paper_reader_use_pdf and pdf_successes < target_pdf_papers and paper.arxiv_id:
                pdf_results = await self._extract_from_paper_pdf(
                    paper.paper_id,
                    paper.title,
                    paper.arxiv_id,
                    direction,
                )
                if pdf_results:
                    results = pdf_results
                    pdf_successes += 1
                    logger.info(
                        "PaperReader: using PDF-derived results for '%s' (%d results, %d/%d PDF reads)",
                        paper.title,
                        len(pdf_results),
                        pdf_successes,
                        target_pdf_papers,
                    )
                else:
                    logger.info(
                        "PaperReader: PDF extraction failed for '%s'; falling back to abstract-derived results and continuing PDF search (see preceding PDF-specific warning for root cause)",
                        paper.title,
                    )

            all_results.extend(results)
            state.known_results = list(all_results)
            self.bus.put_theory_state(state)
            logger.info(
                "PaperReader: extracted %d results from '%s'",
                len(results), paper.title,
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
            results: list[KnownResult] = []
            for item in items:
                if not item.get("statement"):
                    item["statement"] = item.get("theorem_content", "")
                if not item.get("statement"):
                    continue
                try:
                    statement = str(item.get("theorem_content") or item.get("statement", ""))
                    results.append(
                        KnownResult(
                            source_paper_id=paper_id,
                            source_paper_title=title,
                            result_type=_normalize_result_type(item.get("result_type", "lemma")),
                            extraction_source="abstract_summary",
                            statement=statement,
                            theorem_content=statement,
                            assumptions=str(item.get("assumptions", "")),
                            proof_idea=str(item.get("proof_idea", "")),
                            reuse_judgment=_normalize_reuse_judgment(item.get("reuse_judgment", "unclear")),
                            informal=str(item.get("informal", "")),
                            proof_technique=str(item.get("proof_technique", "")),
                            notation=_normalize_notation(item.get("notation", {})),
                        )
                    )
                except Exception as item_exc:
                    logger.warning(
                        "PaperReader: skipping malformed result from '%s': %s",
                        title,
                        item_exc,
                    )
            return results
        except Exception as e:
            logger.warning("PaperReader: extraction failed for '%s': %s", title, e)
            return []

    async def _extract_from_paper_pdf(
        self,
        paper_id: str,
        title: str,
        arxiv_id: str,
        direction: str,
    ) -> list[KnownResult]:
        """Fetch the full paper PDF from arXiv, parse it with Docling, and run
        chunked full-paper extraction over the resulting Markdown.

        Unlike the old theorem-section heuristic, this reads the full converted
        paper in chunks so common section titles like "Analysis", "Upper Bounds",
        or prose-style theorem statements are still visible to the LLM.

        Pipeline:
          1. Build the arXiv PDF URL from *arxiv_id*.
          2. Pass the URL directly to Docling — it handles the HTTP fetch,
             PDF layout analysis, and exports clean Markdown.
          3. Split the full markdown into manageable chunks.
          4. Run the existing extraction prompt over each chunk.
          5. Merge and deduplicate extracted results.

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
                "PaperReader: no arxiv_id for '%s', skipping PDF extraction", title
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
                title, arxiv_id, e,
            )
            return []
        finally:
            if "converter" in locals():
                try:
                    # aggressively clear internals
                    if hasattr(converter, "initialized_pipelines"):
                        for k in list(converter.initialized_pipelines.keys()):
                            converter.initialized_pipelines[k] = None
                        converter.initialized_pipelines.clear()
                except Exception:
                    pass
                for var in vars(converter).values():
                    del var
                del converter
            import gc
            gc.collect()
            try:
                import torch
                if torch.cuda.is_available():
                    torch.cuda.synchronize()
                    torch.cuda.empty_cache()
                if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                    torch.mps.empty_cache()
            except ImportError:
                pass

        chunks = _chunk_markdown(markdown)
        if not chunks:
            logger.warning(
                "PaperReader: Docling produced no usable markdown chunks for '%s' (arxiv_id=%s, markdown_chars=%d)",
                title,
                arxiv_id,
                len(markdown),
            )
            return []

        selected_chunks = _select_candidate_chunks(
            chunks,
            direction,
            max_selected=_MAX_PDF_CHUNKS_TO_EXTRACT,
        )

        logger.info(
            "PaperReader: %d markdown chunks prepared from '%s' (markdown_chars=%d); extracting from %d soft-selected chunks",
            len(chunks), title, len(markdown), len(selected_chunks),
        )
        results: list[KnownResult] = []
        parseable_chunks = 0
        for idx, chunk in enumerate(selected_chunks, 1):
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
                            abstract=(
                                f"[Full-paper chunk {idx}/{len(selected_chunks)} of {len(chunks)} selected chunks]\n"
                                f"{chunk[:6000]}"
                            ),
                        ),
                    }],
                )
                text = response.content[0].text
                items = self._parse_json_array(text)
                if not items:
                    logger.debug(
                        "PaperReader: no parseable results from PDF chunk %d/%d for '%s'",
                        idx,
                        len(selected_chunks),
                        title,
                    )
                    continue
                parseable_chunks += 1
                for item in items:
                    if not item.get("statement"):
                        item["statement"] = item.get("theorem_content", "")
                    if not item.get("statement"):
                        continue
                    try:
                        statement = str(item.get("theorem_content") or item.get("statement", ""))
                        results.append(
                            KnownResult(
                                source_paper_id=paper_id,
                                source_paper_title=title,
                                result_type=_normalize_result_type(item.get("result_type", "theorem")),
                                extraction_source="pdf_result_sections",
                                statement=statement,
                                theorem_content=statement,
                                assumptions=str(item.get("assumptions", "")),
                                proof_idea=str(item.get("proof_idea", "")),
                                reuse_judgment=_normalize_reuse_judgment(item.get("reuse_judgment", "unclear")),
                                informal=str(item.get("informal", "")),
                                proof_technique=str(item.get("proof_technique", "")),
                                notation=_normalize_notation(item.get("notation", {})),
                            )
                        )
                    except Exception as item_exc:
                        logger.warning(
                            "PaperReader: skipping malformed PDF-derived result from '%s': %s",
                            title,
                            item_exc,
                        )
            except Exception as e:
                logger.warning(
                    "PaperReader: LLM extraction failed on PDF chunk %d/%d for '%s': %s",
                    idx,
                    len(selected_chunks),
                    title,
                    e,
                )

        results = _dedupe_results(results)
        if not results:
            logger.warning(
                "PaperReader: PDF full-paper extraction produced no reusable results for '%s' (arxiv_id=%s, chunks=%d, parseable_chunks=%d)",
                title,
                arxiv_id,
                len(selected_chunks),
                parseable_chunks,
            )
        else:
            logger.info(
                "PaperReader: PDF full-paper extraction produced %d deduped results for '%s' from %d/%d parseable selected chunks",
                len(results),
                title,
                parseable_chunks,
                len(selected_chunks),
            )
        return results

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
