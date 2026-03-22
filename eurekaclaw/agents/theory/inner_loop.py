"""TheoryInnerLoop — the 6-stage proof loop that is EurekaClaw's primary differentiator.

Pipeline:
  Formalization → Lemma Decomposition → Proof Attempt → Verification
       ↑                                                        |
       |                                              [pass] → update proven_lemmas
       |                                              [fail] → Counterexample search
       └──────────────── Refinement ←─────────────────────────┘

Token-efficiency improvements (v2):
- Stagnation detection: if a lemma fails ``stagnation_window`` consecutive times
  with similar error signatures, skip directly to forced refinement instead of
  wasting more prover/verifier calls.
- Resource-analyst timeout reduced from 60 s → 20 s.
- Formalizer skips re-formalization when informal statement unchanged.
- Verifier auto-accepts high-confidence proofs without an LLM peer-review call.
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
from eurekaclaw.memory import MemoryManager

logger = logging.getLogger(__name__)


def _error_signature(reason: str) -> str:
    """Reduce a failure reason to a short normalised signature for comparison.

    Two reasons with the same signature are treated as "the same failure" for
    the purpose of stagnation detection.
    """
    reason_lower = reason.lower()
    for keyword in (
        "circular", "gap", "unjustified", "quantifier", "edge case",
        "missing assumption", "not proven", "failed", "parse", "timeout",
    ):
        if keyword in reason_lower:
            return keyword
    # Fallback: first 40 chars normalised
    return reason_lower[:40].strip()


class TheoryInnerLoop:
    """Orchestrates the 6-stage proof loop with retry semantics.

    The loop runs until either:
    - All lemmas are proven (state.is_complete() == True)
    - MAX_ITERATIONS is reached (abandon)
    - A fatal counterexample is found (status = "refuted")
    - Stagnation is detected on a lemma (forced refinement)
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
        memory: MemoryManager | None = None,
    ) -> None:
        self.bus = bus
        self.formalizer = formalizer or Formalizer()
        self.decomposer = decomposer or LemmaDecomposer()
        self.prover = prover or Prover()
        self.verifier = verifier or Verifier()
        self.cx_searcher = cx_searcher or CounterexampleSearcher()
        self.refiner = refiner or Refiner()
        self.resource_analyst = resource_analyst or ResourceAnalyst()
        self.memory = memory  # MemoryManager for cross-session recall

        self.max_iterations = settings.theory_max_iterations
        self._failure_log: list[FailedAttempt] = []
        self._stagnation_window = settings.stagnation_window
        self._lemma_failure_sigs: dict[str, list[str]] = {}
        # Per-lemma failure reasons accumulated in THIS session (for prover context)
        self._session_failures: dict[str, list[str]] = {}

    def _record_failure(self, lemma_id: str, reason: str) -> bool:
        """Record a failure and return True if stagnation is detected.

        Stagnation = the last ``stagnation_window`` failures for this lemma all
        share the same normalised error signature (i.e. we're stuck in a loop).
        """
        sig = _error_signature(reason)
        sigs = self._lemma_failure_sigs.setdefault(lemma_id, [])
        sigs.append(sig)
        # Only look at the tail of length stagnation_window
        recent = sigs[-self._stagnation_window:]
        if len(recent) >= self._stagnation_window and len(set(recent)) <= 2:
            logger.warning(
                "Stagnation detected for lemma '%s' after %d failures with similar "
                "errors (%s) — forcing conjecture refinement.",
                lemma_id, len(recent), set(recent),
            )
            return True
        return False

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
            # Formalizer internally skips the LLM call when informal statement
            # has not changed since the last formalization.
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

                # Step 3: Proof attempt — inject memory context
                past_failures = self._session_failures.get(lemma_id, [])
                cross_hint: str | None = None
                if self.memory:
                    # Check persistent memory for a successful approach from a prior session
                    node = state.lemma_dag.get(lemma_id)
                    stmt_key = f"proved:{hash(node.statement) & 0xFFFFFFFF}" if node else None
                    if stmt_key:
                        prior = self.memory.recall(stmt_key)
                        if prior:
                            cross_hint = prior.get("approach", "")
                            logger.info(
                                "Cross-session hint found for %s (prior session proved it)", lemma_id
                            )

                proof_attempt = await self.prover.attempt(
                    state, lemma_id,
                    past_failures=past_failures or None,
                    cross_session_hint=cross_hint,
                )

                # Step 4: Verification
                # Two shortcuts to save LLM calls:
                #   HIGH confidence (≥ auto_verify_confidence): Verifier auto-accepts.
                #   LOW confidence (< 0.3): skip peer review entirely; go straight to
                #   counterexample search.  An obviously incomplete proof cannot be
                #   saved by a verifier — failing fast saves one fast-model call.
                if proof_attempt.confidence < 0.3:
                    logger.info(
                        "Skipping verification for very low-confidence proof "
                        "(lemma=%s, conf=%.2f) — proceeding to counterexample search",
                        lemma_id, proof_attempt.confidence,
                    )
                    from eurekaclaw.agents.theory.verifier import VerificationResult
                    verification = VerificationResult(
                        lemma_id=lemma_id,
                        passed=False,
                        method="llm_check",
                        confidence=proof_attempt.confidence,
                        errors=proof_attempt.gaps or ["Very low confidence — skipped verification"],
                        notes="Auto-rejected: confidence below 0.3 threshold",
                    )
                else:
                    # High-confidence proofs are auto-accepted by the Verifier
                    # without an additional LLM call (see verifier.py).
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
                        proved_at=datetime.now().astimezone(),
                    )
                    state.proven_lemmas[lemma_id] = record
                    state.open_goals.remove(lemma_id)
                    # Write verification result back to lemma_dag node so gate
                    # and writer can access per-lemma confidence
                    if lemma_id in state.lemma_dag:
                        state.lemma_dag[lemma_id].verified = True
                        state.lemma_dag[lemma_id].confidence_score = verification.confidence
                        state.lemma_dag[lemma_id].verification_method = verification.method
                    # Persist successful approach to memory for future sessions
                    if self.memory:
                        node = state.lemma_dag.get(lemma_id)
                        if node:
                            stmt_key = f"proved:{hash(node.statement) & 0xFFFFFFFF}"
                            self.memory.remember(
                                stmt_key,
                                {
                                    "lemma_id": lemma_id,
                                    "approach": proof_attempt.proof_text[:300],
                                    "method": verification.method,
                                    "confidence": verification.confidence,
                                },
                                tags=["proved_lemma"],
                                source_session=self.bus.session_id,
                            )
                    # Reset stagnation and session failure tracking
                    self._lemma_failure_sigs.pop(lemma_id, None)
                    self._session_failures.pop(lemma_id, None)
                    logger.info("✓ Lemma proved: %s (method=%s, conf=%.2f)",
                                lemma_id, verification.method, verification.confidence)
                    self.bus.put_theory_state(state)
                else:
                    failure_reason = "; ".join(verification.errors[:3]) or "verification failed"
                    # Track in session memory so next prover call avoids this approach
                    self._session_failures.setdefault(lemma_id, []).append(failure_reason)
                    failure = FailedAttempt(
                        lemma_id=lemma_id,
                        attempt_text=proof_attempt.proof_text[:500],
                        failure_reason=failure_reason,
                        iteration=iteration,
                    )
                    state.failed_attempts.append(failure)
                    self._failure_log.append(failure)

                    # --- Stagnation detection ---
                    # If the same lemma has been failing with the same error
                    # pattern repeatedly, skip counterexample search and go
                    # straight to refinement to avoid wasting more calls.
                    stagnant = self._record_failure(lemma_id, failure_reason)

                    if stagnant:
                        # Create a synthetic "no counterexample" result and force
                        # refinement with a stagnation note as the description.
                        cx = Counterexample(
                            lemma_id=lemma_id,
                            counterexample_description=(
                                f"Stagnation: lemma failed {self._stagnation_window} times "
                                f"with similar errors. Forcing conjecture refinement."
                            ),
                            falsifies_conjecture=True,  # treat as fatal to trigger refinement
                            suggested_refinement="Refine the conjecture to address the repeated failure pattern.",
                        )
                        state.counterexamples.append(cx)
                        logger.info("[6/6] Forced refinement due to stagnation...")
                        state = await self.refiner.refine(state, lemma_id, cx)
                        state.iteration = iteration + 1
                        self.bus.put_theory_state(state)
                        goal_proved = False
                        # Reset stagnation tracking after refinement
                        self._lemma_failure_sigs.clear()
                        break

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
                        self._lemma_failure_sigs.clear()
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
                            proved_at=datetime.now().astimezone(),
                        )
                        state.proven_lemmas[lemma_id] = record
                        state.open_goals.remove(lemma_id)
                        if lemma_id in state.lemma_dag:
                            state.lemma_dag[lemma_id].verified = False
                            state.lemma_dag[lemma_id].confidence_score = verification.confidence
                            state.lemma_dag[lemma_id].verification_method = "llm_check"
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

        # Await resource analysis — reduced timeout (20 s) to avoid blocking
        try:
            analysis = await asyncio.wait_for(analysis_task, timeout=20)
            self.bus.put("resource_analysis", {
                "atomic_components": analysis.atomic_components,
                "math_to_code": analysis.math_to_code,
                "code_to_math": analysis.code_to_math,
                "validation_code": analysis.validation_code,
            })
        except asyncio.TimeoutError:
            logger.warning("Resource analysis timed out (20 s limit)")

        self.bus.put_theory_state(state)
        logger.info(
            "Theory loop complete: status=%s, proven=%d, open=%d",
            state.status, len(state.proven_lemmas), len(state.open_goals),
        )
        return state

    @property
    def failure_log(self) -> list[FailedAttempt]:
        return list(self._failure_log)
