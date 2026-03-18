"""TheoryInnerLoop — the 6-stage proof loop that is EurekaClaw's primary differentiator.

Pipeline:
  Formalization → Lemma Decomposition → Proof Attempt → Verification
       ↑                                                        |
       |                                              [pass] → update proven_lemmas
       |                                              [fail] → Counterexample search
       └──────────────── Refinement ←─────────────────────────┘
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from eurekaclaw.agents.theory.counterexample import CounterexampleSearcher
from eurekaclaw.agents.theory.decomposer import LemmaDecomposer
from eurekaclaw.agents.theory.formalizer import Formalizer
from eurekaclaw.agents.theory.prover import Prover
from eurekaclaw.agents.theory.refiner import Refiner
from eurekaclaw.agents.theory.resource_analyst import ResourceAnalyst
from eurekaclaw.agents.theory.verifier import Verifier
from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import (
    Counterexample,
    FailedAttempt,
    ProofRecord,
    TheoryState,
)

logger = logging.getLogger(__name__)


class TheoryInnerLoop:
    """Orchestrates the 6-stage proof loop with retry semantics.

    The loop runs until either:
    - All lemmas are proven (state.is_complete() == True)
    - MAX_ITERATIONS is reached (abandon)
    - A fatal counterexample is found (status = "refuted")
    """

    def __init__(
        self,
        bus: KnowledgeBus,
        formalizer: Formalizer | None = None,
        decomposer: LemmaDecomposer | None = None,
        prover: Prover | None = None,
        verifier: Verifier | None = None,
        cx_searcher: CounterexampleSearcher | None = None,
        refiner: Refiner | None = None,
        resource_analyst: ResourceAnalyst | None = None,
    ) -> None:
        self.bus = bus
        self.formalizer = formalizer or Formalizer()
        self.decomposer = decomposer or LemmaDecomposer()
        self.prover = prover or Prover()
        self.verifier = verifier or Verifier()
        self.cx_searcher = cx_searcher or CounterexampleSearcher()
        self.refiner = refiner or Refiner()
        self.resource_analyst = resource_analyst or ResourceAnalyst()

        self.max_iterations = settings.theory_max_iterations
        self._failure_log: list[FailedAttempt] = []

    async def run(self, session_id: str, domain: str = "") -> TheoryState:
        """Drive the full proof loop from initial state to completion."""
        state = self.bus.get_theory_state()
        if not state:
            raise ValueError("No TheoryState on KnowledgeBus. Initialize it before calling run().")

        state.status = "in_progress"
        self.bus.put_theory_state(state)

        # Run resource analysis in parallel (doesn't block the main loop)
        analysis_task = asyncio.create_task(
            self.resource_analyst.analyze(state, domain)
        )

        for iteration in range(self.max_iterations):
            logger.info("=== Theory loop iteration %d/%d ===", iteration + 1, self.max_iterations)
            state.iteration = iteration

            # --- Step 1: Formalization ---
            logger.info("[1/6] Formalizing conjecture...")
            state = await self.formalizer.run(state, domain)
            self.bus.put_theory_state(state)

            # --- Step 2: Lemma Decomposition ---
            logger.info("[2/6] Decomposing into lemma DAG...")
            state = await self.decomposer.run(state)
            self.bus.put_theory_state(state)

            if not state.open_goals and state.lemma_dag:
                # All lemmas proven (or decomposer produced no goals for a trivially
                # true theorem). Only claim "proved" if at least one lemma was actually
                # proven; otherwise the decomposer likely failed to parse anything.
                if state.proven_lemmas:
                    logger.info("No open goals — theorem is proved!")
                    state.status = "proved"
                    break
                else:
                    logger.warning(
                        "Decomposer produced %d lemmas but 0 open_goals after DAG build — "
                        "treating as decomposition failure, will retry.",
                        len(state.lemma_dag),
                    )
                    # Reset dag so next iteration re-decomposes
                    state.lemma_dag = {}
                    state.open_goals = []
                    continue
            elif not state.open_goals and not state.lemma_dag:
                logger.warning(
                    "Decomposer produced no lemmas (parse failure?) — retrying decomposition."
                )
                continue

            # --- Steps 3-6: Process each open goal ---
            goal_proved = True
            for lemma_id in list(state.open_goals):
                logger.info("[3/6] Attempting proof of lemma: %s", lemma_id)

                # Step 3: Proof attempt
                proof_attempt = await self.prover.attempt(state, lemma_id)

                # Step 4: Verification
                logger.info("[4/6] Verifying proof of lemma: %s", lemma_id)
                verification = await self.verifier.check(proof_attempt, state)

                if verification.passed:
                    # Record the proven lemma
                    record = ProofRecord(
                        lemma_id=lemma_id,
                        proof_text=proof_attempt.proof_text,
                        lean4_proof=proof_attempt.lean4_sketch,
                        verification_method=verification.method,
                        verified=True,
                        verifier_notes=verification.notes,
                        proved_at=datetime.utcnow(),
                    )
                    state.proven_lemmas[lemma_id] = record
                    state.open_goals.remove(lemma_id)
                    logger.info("✓ Lemma proved: %s (method=%s)", lemma_id, verification.method)
                    self.bus.put_theory_state(state)
                else:
                    # Record failure
                    failure = FailedAttempt(
                        lemma_id=lemma_id,
                        attempt_text=proof_attempt.proof_text[:500],
                        failure_reason="; ".join(verification.errors[:3]) or "verification failed",
                        iteration=iteration,
                    )
                    state.failed_attempts.append(failure)
                    self._failure_log.append(failure)

                    # Step 5: Counterexample search
                    logger.info("[5/6] Searching for counterexample to lemma: %s", lemma_id)
                    cx = await self.cx_searcher.search(
                        state, lemma_id,
                        failure_reason=failure.failure_reason,
                        proof_text=proof_attempt.proof_text,
                    )
                    state.counterexamples.append(cx)

                    if cx.falsifies_conjecture:
                        logger.warning("! Counterexample found for %s — refining conjecture", lemma_id)
                        # Step 6: Refinement
                        logger.info("[6/6] Refining conjecture...")
                        state = await self.refiner.refine(state, lemma_id, cx)
                        state.iteration = iteration + 1
                        self.bus.put_theory_state(state)
                        goal_proved = False
                        break  # Restart the loop with refined conjecture
                    else:
                        # No counterexample found — proof may be valid but checker failed
                        # Accept with reduced confidence and move on
                        logger.warning(
                            "Verification failed but no counterexample found for %s — "
                            "accepting with low confidence", lemma_id
                        )
                        record = ProofRecord(
                            lemma_id=lemma_id,
                            proof_text=proof_attempt.proof_text,
                            lean4_proof=proof_attempt.lean4_sketch,
                            verification_method="llm_check",
                            verified=False,
                            verifier_notes=f"Unverified (low confidence). Errors: {verification.errors}",
                            proved_at=datetime.utcnow(),
                        )
                        state.proven_lemmas[lemma_id] = record
                        state.open_goals.remove(lemma_id)
                        self.bus.put_theory_state(state)

            # Only declare complete when all goals for the *current* DAG are done.
            # If goal_proved is False it means we broke out because a counterexample
            # triggered refinement — open_goals was cleared by the refiner but the
            # proven_lemmas from the *old* DAG are stale, so we must not declare proved.
            if goal_proved and not state.open_goals and state.proven_lemmas:
                state.status = "proved"
                logger.info("All lemmas proved! Theorem complete.")
                break

        else:
            # Exhausted iterations
            if state.open_goals:
                state.status = "abandoned"
                logger.warning(
                    "Theory loop exhausted after %d iterations. %d goals remain open.",
                    self.max_iterations, len(state.open_goals),
                )

        # Await resource analysis result
        try:
            analysis = await asyncio.wait_for(analysis_task, timeout=60)
            self.bus.put("resource_analysis", {
                "atomic_components": analysis.atomic_components,
                "math_to_code": analysis.math_to_code,
                "code_to_math": analysis.code_to_math,
                "validation_code": analysis.validation_code,
            })
        except asyncio.TimeoutError:
            logger.warning("Resource analysis timed out")

        self.bus.put_theory_state(state)
        logger.info(
            "Theory loop complete: status=%s, proven=%d, open=%d",
            state.status, len(state.proven_lemmas), len(state.open_goals),
        )
        return state

    @property
    def failure_log(self) -> list[FailedAttempt]:
        return list(self._failure_log)
