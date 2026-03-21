"""ScientistBenchEvaluator — composite evaluation across 5 dimensions."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ExperimentResult, ResearchBrief, TheoryState

logger = logging.getLogger(__name__)


@dataclass
class EvalReport:
    session_id: str
    scores: dict[str, float] = field(default_factory=dict)
    composite: float = 0.0
    dimension_notes: dict[str, str] = field(default_factory=dict)
    summary: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "session_id": self.session_id,
            "scores": self.scores,
            "composite": self.composite,
            "dimension_notes": self.dimension_notes,
            "summary": self.summary,
        }


# Dimension weights
WEIGHTS = {
    "formal_correctness": 0.35,
    "novelty": 0.25,
    "depth": 0.15,
    "citation_coverage": 0.10,
    "experimental_alignment": 0.15,
}


class ScientistBenchEvaluator:
    """Evaluates a completed research session on 5 Scientist-Bench dimensions."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def evaluate(self, bus: KnowledgeBus) -> EvalReport:
        state = bus.get_theory_state()
        brief = bus.get_research_brief()
        exp = bus.get_experiment_result()
        bib = bus.get_bibliography()

        report = EvalReport(session_id=bus.session_id)

        # 1. Formal correctness
        report.scores["formal_correctness"], report.dimension_notes["formal_correctness"] = \
            self._formal_correctness(state)

        # 2. Novelty (LLM-judged)
        report.scores["novelty"], report.dimension_notes["novelty"] = \
            await self._novelty(state, bib)

        # 3. Depth
        report.scores["depth"], report.dimension_notes["depth"] = \
            self._depth(state)

        # 4. Citation coverage
        report.scores["citation_coverage"], report.dimension_notes["citation_coverage"] = \
            self._citation_coverage(bib, brief)

        # 5. Experimental alignment
        report.scores["experimental_alignment"], report.dimension_notes["experimental_alignment"] = \
            self._experimental_alignment(exp)

        # Composite
        report.composite = sum(WEIGHTS[k] * v for k, v in report.scores.items())
        report.summary = self._generate_summary(report, state)

        return report

    def _formal_correctness(self, state: TheoryState | None) -> tuple[float, str]:
        if not state:
            return 0.0, "No theory state"
        verified = sum(1 for r in state.proven_lemmas.values() if r.verified)
        total = len(state.lemma_dag) or 1
        lean4_proofs = sum(1 for r in state.proven_lemmas.values() if r.lean4_proof)

        score = verified / total
        if lean4_proofs > 0:
            score = min(1.0, score * 1.2)  # Bonus for Lean4 verification
        note = (
            f"{verified}/{total} lemmas verified, {lean4_proofs} Lean4-verified. "
            f"Status: {state.status}"
        )
        return score, note

    async def _novelty(self, state: TheoryState | None, bib: Any | None) -> tuple[float, str]:
        if not state:
            return 0.0, "No theory state"
        # Simple LLM-based novelty judge
        try:
            paper_titles = ""
            if bib and bib.papers:
                paper_titles = "\n".join(f"- {p.title}" for p in bib.papers[:10])

            response = await self.client.messages.create(
                model=settings.active_fast_model,
                max_tokens=256,
                messages=[{
                    "role": "user",
                    "content": f"""\
Rate the novelty of this theorem (0.0-1.0) relative to these existing papers:

Theorem: {state.informal_statement}
Existing papers:
{paper_titles or "(none)"}

Return JSON: {{"novelty_score": 0.0-1.0, "reasoning": "..."}}
""",
                }],
            )
            if not response.content:
                raise ValueError("LLM returned empty content list")
            text = response.content[0].text
            data = json.loads(text[text.index("{"):text.rindex("}")+1])
            score = float(data.get("novelty_score", 0.5))
            return score, data.get("reasoning", "")[:200]
        except Exception as e:
            logger.debug("Novelty scoring failed: %s", e)
            return 0.5, "Auto-scored (scorer unavailable)"

    def _depth(self, state: TheoryState | None) -> tuple[float, str]:
        if not state:
            return 0.0, "No theory state"
        n_lemmas = len(state.lemma_dag)
        n_proven = len(state.proven_lemmas)
        total_proof_tokens = sum(len(r.proof_text.split()) for r in state.proven_lemmas.values())

        # Normalized: 8+ lemmas and 2000+ words = score 1.0
        lemma_score = min(1.0, n_lemmas / 8.0)
        depth_score = min(1.0, total_proof_tokens / 2000.0)
        score = 0.6 * lemma_score + 0.4 * depth_score
        return score, f"{n_lemmas} lemmas, {n_proven} proven, {total_proof_tokens} proof tokens"

    def _citation_coverage(self, bib: Any | None, brief: "ResearchBrief | None") -> tuple[float, str]:
        if not bib:
            return 0.0, "No bibliography"
        n_papers = len(bib.papers)
        # Normalize: 20+ papers = score 1.0
        score = min(1.0, n_papers / 20.0)
        return score, f"{n_papers} papers in bibliography"

    def _experimental_alignment(self, exp: ExperimentResult | None) -> tuple[float, str]:
        if not exp:
            return 0.0, "No experiment run"
        return exp.alignment_score, f"Alignment score: {exp.alignment_score:.2f}"

    def _generate_summary(self, report: EvalReport, state: TheoryState | None) -> str:
        status = state.status if state else "unknown"
        return (
            f"EvalReport | composite={report.composite:.2f} | "
            f"correctness={report.scores.get('formal_correctness', 0):.2f} | "
            f"novelty={report.scores.get('novelty', 0):.2f} | "
            f"depth={report.scores.get('depth', 0):.2f} | "
            f"theory_status={status}"
        )
