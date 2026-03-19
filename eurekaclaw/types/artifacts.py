"""Core research artifact types shared across all agents via the KnowledgeBus."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator


# ---------------------------------------------------------------------------
# Literature / Survey
# ---------------------------------------------------------------------------


class Paper(BaseModel):
    paper_id: str
    title: str
    authors: list[str]
    year: int | None = None
    abstract: str = ""
    venue: str = ""
    arxiv_id: str | None = None
    semantic_scholar_id: str | None = None
    citation_count: int = 0
    url: str = ""
    relevance_score: float = 0.0


class Bibliography(BaseModel):
    session_id: str
    papers: list[Paper] = Field(default_factory=list)
    citation_graph: dict[str, list[str]] = Field(default_factory=dict)  # id -> [citing_ids]
    bibtex: str = ""
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Research direction (output of Divergent-Convergent planner)
# ---------------------------------------------------------------------------


class ResearchDirection(BaseModel):
    direction_id: str
    title: str
    hypothesis: str
    approach_sketch: str = ""
    novelty_score: float = 0.0       # 0-1
    soundness_score: float = 0.0     # 0-1
    transformative_score: float = 0.0  # 0-1
    composite_score: float = 0.0

    def compute_composite(
        self,
        w_novelty: float = 0.4,
        w_soundness: float = 0.35,
        w_transformative: float = 0.25,
    ) -> float:
        self.composite_score = (
            w_novelty * self.novelty_score
            + w_soundness * self.soundness_score
            + w_transformative * self.transformative_score
        )
        return self.composite_score


# ---------------------------------------------------------------------------
# Research brief (top-level session artifact)
# ---------------------------------------------------------------------------


class ResearchBrief(BaseModel):
    session_id: str
    input_mode: Literal["detailed", "reference", "exploration"]
    domain: str
    query: str
    conjecture: str | None = None
    selected_skills: list[str] = Field(default_factory=list)
    reference_paper_ids: list[str] = Field(default_factory=list)
    open_problems: list[str] = Field(default_factory=list)
    key_mathematical_objects: list[str] = Field(default_factory=list)
    directions: list[ResearchDirection] = Field(default_factory=list)
    selected_direction: ResearchDirection | None = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Theory State (Theory Agent inner loop state machine)
# ---------------------------------------------------------------------------


class LemmaNode(BaseModel):
    lemma_id: str
    statement: str         # formal statement
    informal: str = ""     # human-readable version
    dependencies: list[str] = Field(default_factory=list)  # other lemma IDs this needs


class ProofRecord(BaseModel):
    lemma_id: str
    proof_text: str          # human-readable proof
    lean4_proof: str = ""    # Lean4 tactic proof (if available)
    coq_proof: str = ""      # Coq proof (if available)
    verification_method: Literal["lean4", "coq", "peer_review", "llm_check", "auto_high_confidence"] = "llm_check"
    verified: bool = False
    verifier_notes: str = ""
    proved_at: datetime = Field(default_factory=datetime.utcnow)


class FailedAttempt(BaseModel):
    lemma_id: str
    attempt_text: str
    failure_reason: str
    iteration: int
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class Counterexample(BaseModel):
    lemma_id: str
    counterexample_description: str
    falsifies_conjecture: bool = False
    suggested_refinement: str = ""
    discovered_at: datetime = Field(default_factory=datetime.utcnow)


class KnownResult(BaseModel):
    """A theorem, lemma, or technique extracted from an existing paper."""
    source_paper_id: str
    source_paper_title: str
    result_type: Literal["theorem", "lemma", "corollary", "algorithm", "technique"]
    statement: str
    informal: str = ""
    proof_technique: str = ""   # e.g. "Azuma-Hoeffding", "elliptical potential lemma"
    notation: dict[str, str] = Field(default_factory=dict)  # symbol -> definition


class ProofPlan(BaseModel):
    """One node in the proof plan produced by ProofArchitect."""
    lemma_id: str
    statement: str
    informal: str = ""
    provenance: Literal["known", "adapted", "new"]
    # For "known": paper citation key.  For "adapted": base result reference.
    source: str = ""
    adaptation_note: str = ""   # what to change relative to the source
    dependencies: list[str] = Field(default_factory=list)  # other lemma_ids


class TheoryState(BaseModel):
    session_id: str
    theorem_id: str
    informal_statement: str = ""
    formal_statement: str = ""    # LaTeX / Lean4 notation — set by TheoremCrystallizer
    # --- bottom-up proof pipeline fields ---
    known_results: list[KnownResult] = Field(default_factory=list)
    research_gap: str = ""          # output of GapAnalyst
    proof_plan: list[ProofPlan] = Field(default_factory=list)  # topological order
    assembled_proof: str = ""       # output of Assembler
    # --- lemma working state (populated during LemmaDeveloper stage) ---
    lemma_dag: dict[str, LemmaNode] = Field(default_factory=dict)  # lemma_id -> LemmaNode
    proven_lemmas: dict[str, ProofRecord] = Field(default_factory=dict)
    open_goals: list[str] = Field(default_factory=list)  # lemma_ids not yet proven
    failed_attempts: list[FailedAttempt] = Field(default_factory=list)
    counterexamples: list[Counterexample] = Field(default_factory=list)
    iteration: int = 0
    status: Literal["pending", "in_progress", "proved", "refuted", "abandoned"] = "pending"
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    def is_complete(self) -> bool:
        return (
            len(self.open_goals) == 0
            and len(self.proven_lemmas) > 0
            and self.status == "proved"
        )


# ---------------------------------------------------------------------------
# Experiment Result
# ---------------------------------------------------------------------------


class NumericalBound(BaseModel):
    name: str
    # Accept float, int, symbolic string (e.g. "Ω(k·d)", "O(n log n)"), or None.
    theoretical: float | str | None = None
    empirical: float | str | None = None
    unit: str = ""
    aligned: bool | None = None

    @field_validator("theoretical", "empirical", mode="before")
    @classmethod
    def _coerce_bound(cls, v: Any) -> float | str | None:
        if v is None:
            return None
        if isinstance(v, (int, float)):
            return float(v)
        if isinstance(v, str):
            # Try to parse as a plain number first; keep as string if it's symbolic.
            try:
                return float(v)
            except ValueError:
                return v.strip()
        return v


class ExperimentResult(BaseModel):
    session_id: str
    experiment_id: str
    description: str = ""
    code: str = ""
    outputs: dict[str, Any] = Field(default_factory=dict)
    bounds: list[NumericalBound] = Field(default_factory=list)
    alignment_score: float = 0.0     # 0-1, 1 = theory matches experiment exactly
    sandbox_log: str = ""
    execution_time_s: float = 0.0
    succeeded: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)
