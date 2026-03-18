"""Integration tests for the Theory Agent (require ANTHROPIC_API_KEY)."""

import os
import pytest

# Skip all integration tests if no API key
pytestmark = pytest.mark.skipif(
    not os.getenv("ANTHROPIC_API_KEY"),
    reason="ANTHROPIC_API_KEY not set",
)


@pytest.mark.asyncio
async def test_formalizer_runs(theory_state):
    """Test that the Formalizer can process a real informal statement."""
    from eurekaclaw.agents.theory.formalizer import Formalizer

    formalizer = Formalizer()
    result = await formalizer.run(theory_state, domain="mathematical analysis")

    assert result.formal_statement  # Should produce some formal output
    assert len(result.formal_statement) > 10


@pytest.mark.asyncio
async def test_decomposer_runs(theory_state):
    """Test that the LemmaDecomposer builds a non-empty DAG."""
    from eurekaclaw.agents.theory.formalizer import Formalizer
    from eurekaclaw.agents.theory.decomposer import LemmaDecomposer

    formalizer = Formalizer()
    state = await formalizer.run(theory_state)

    decomposer = LemmaDecomposer()
    state = await decomposer.run(state)

    assert len(state.lemma_dag) >= 1
    assert len(state.open_goals) >= 1


@pytest.mark.asyncio
async def test_prover_attempt(theory_state):
    """Test that the Prover generates a proof attempt."""
    from eurekaclaw.agents.theory.formalizer import Formalizer
    from eurekaclaw.agents.theory.decomposer import LemmaDecomposer
    from eurekaclaw.agents.theory.prover import Prover
    from eurekaclaw.types.artifacts import LemmaNode

    # Setup a simple state with one known lemma
    theory_state.formal_statement = "\\forall n \\geq 1: \\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}"
    theory_state.lemma_dag["base_case"] = LemmaNode(
        lemma_id="base_case",
        statement="For n=1: sum = 1 = 1*(1+1)/2",
        informal="base case",
        dependencies=[],
    )
    theory_state.open_goals = ["base_case"]

    prover = Prover()
    attempt = await prover.attempt(theory_state, "base_case")

    assert attempt.lemma_id == "base_case"
    assert len(attempt.proof_text) > 50  # Should produce some text
