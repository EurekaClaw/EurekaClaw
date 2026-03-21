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

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.llm import LLMClient, create_client
from eurekaclaw.types.artifacts import KnownResult, TheoryState

logger = logging.getLogger(__name__)

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
                model=settings.fast_model,
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
                    continue
                try:
                    results.append(
                        KnownResult(
                            source_paper_id=paper_id,
                            source_paper_title=title,
                            result_type=_normalize_result_type(item.get("result_type", "lemma")),
                            statement=str(item.get("statement", "")),
                            informal=str(item.get("informal", "")),
                            proof_technique=str(item.get("proof_technique", "")),
                            notation=_normalize_notation(item.get("notation", {})),
                        )
                    )
                except Exception as item_exc:
                    logger.warning(
                        "PaperReader: skipping malformed result from '%s': %s",
                        title[:50],
                        item_exc,
                    )
            return results
        except Exception as e:
            logger.warning("PaperReader: extraction failed for '%s': %s", title[:50], e)
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
