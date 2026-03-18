"""Unit tests for Theory Agent inner loop components."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from eurekaclaw.agents.theory.decomposer import LemmaDecomposer
from eurekaclaw.agents.theory.prover import Prover, ProofAttempt
from eurekaclaw.types.artifacts import LemmaNode, TheoryState


@pytest.fixture
def simple_state():
    state = TheoryState(
        session_id="test",
        theorem_id="thm-test",
        informal_statement="For all n >= 1, sum(1..n) = n*(n+1)/2",
        formal_statement="\\forall n \\geq 1: \\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}",
        status="in_progress",
    )
    return state


def test_prover_parse_proof_with_qed():
    prover = Prover.__new__(Prover)
    attempt = prover._parse_proof_attempt(
        "l1",
        "We proceed by induction. Base case n=1: trivial. Inductive step: ... QED"
    )
    assert attempt.lemma_id == "l1"
    assert attempt.confidence > 0.5
    assert len(attempt.gaps) == 0


def test_prover_parse_proof_with_gap():
    prover = Prover.__new__(Prover)
    attempt = prover._parse_proof_attempt(
        "l2",
        "We prove the claim. [GAP: The bound on the tail sum is not tight here] Therefore..."
    )
    assert len(attempt.gaps) == 1
    assert "tail sum" in attempt.gaps[0]
    assert attempt.confidence < 0.6


def test_decomposer_topological_sort():
    decomposer = LemmaDecomposer.__new__(LemmaDecomposer)
    dag = {
        "l1": LemmaNode(lemma_id="l1", statement="S1", dependencies=[]),
        "l2": LemmaNode(lemma_id="l2", statement="S2", dependencies=["l1"]),
        "l3": LemmaNode(lemma_id="l3", statement="S3", dependencies=["l1", "l2"]),
    }
    order = decomposer._topological_sort(dag)
    assert order.index("l1") < order.index("l2")
    assert order.index("l2") < order.index("l3")


def test_decomposer_parse_lemmas():
    decomposer = LemmaDecomposer.__new__(LemmaDecomposer)
    text = '```json\n{"lemmas": [{"id": "base_case", "statement": "n=1 holds", "informal": "trivial", "dependencies": []}]}\n```'
    lemmas = decomposer._parse_lemmas(text)
    assert len(lemmas) == 1
    assert lemmas[0]["id"] == "base_case"
