"""TheoryInnerLoopYaml — YAML-driven bottom-up proof pipeline.

Replaces the hardcoded 6-stage TheoryInnerLoop with a configurable
7-stage bottom-up pipeline loaded from a YAML spec file.

Key design differences from inner_loop.py:
  1. Bottom-up: reads existing literature first (PaperReader), identifies
     the gap (GapAnalyst), plans provenance-annotated proof structure
     (ProofArchitect), proves only what is genuinely new (LemmaDeveloper),
     assembles the result (Assembler), and only then crystallizes the
     formal theorem statement (TheoremCrystallizer + ConsistencyChecker).
  2. No upfront theorem statement: formal_statement is an *output* of the
     pipeline, not an input.  This avoids committing to notation and
     constants before the proof determines them.
  3. Citation-aware: known lemmas from existing papers are cited, not
     reproved.  Only "adapted" and "new" lemmas go through the proof loop.
  4. Configurable: swap in a different .yaml spec to change the stage
     sequence without touching Python code.

Selecting this loop vs. the original:
  Pass inner_loop_cls=TheoryInnerLoopYaml to TheoryAgent, or set
  THEORY_LOOP=yaml in .env (requires wiring in TheoryAgent.execute).
"""

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped]

from eurekaclaw.agents.theory.assembler import Assembler
from eurekaclaw.agents.theory.analysis_stages import (
    MemoryGuidedAnalyzer,
    ProofSkeletonBuilder,
    TemplateSelector,
)
from eurekaclaw.agents.theory.consistency_checker import ConsistencyChecker
from eurekaclaw.agents.theory.counterexample import CounterexampleSearcher
from eurekaclaw.agents.theory.gap_analyst import GapAnalyst
from eurekaclaw.agents.theory.key_lemma_extractor import KeyLemmaExtractor
from eurekaclaw.agents.theory.paper_reader import PaperReader
from eurekaclaw.agents.theory.proof_architect import ProofArchitect
from eurekaclaw.agents.theory.prover import Prover
from eurekaclaw.agents.theory.refiner import Refiner
from eurekaclaw.agents.theory.theorem_crystallizer import TheoremCrystallizer
from eurekaclaw.agents.theory.verifier import Verifier
from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.memory.manager import MemoryManager
from eurekaclaw.skills.injector import SkillInjector
from eurekaclaw.types.artifacts import (
    Counterexample,
    FailedAttempt,
    ProofRecord,
    TheoryState,
)

logger = logging.getLogger(__name__)

_PIPELINE_DIR = Path(__file__).parent / "proof_pipelines"
_DEFAULT_SPEC = _PIPELINE_DIR / "default_proof_pipeline.yaml"
_SPEC_BY_NAME = {
    "default": _PIPELINE_DIR / "default_proof_pipeline.yaml",
    "memory_guided": _PIPELINE_DIR / "memory_guided_proof_pipeline.yaml",
}

# ---------------------------------------------------------------------------
# Stage registry — maps YAML "class" names to Python classes
# ---------------------------------------------------------------------------

# Populated below after LemmaDeveloper is defined.
STAGE_REGISTRY: dict[str, Any] = {}


# ---------------------------------------------------------------------------
# LemmaDeveloper — the iterative inner-inner loop (stages 3-6 of old loop)
# ---------------------------------------------------------------------------

def _error_signature(reason: str) -> str:
    reason_lower = reason.lower()
    for keyword in (
        "circular", "gap", "unjustified", "quantifier", "edge case",
        "missing assumption", "not proven", "failed", "parse", "timeout",
    ):
        if keyword in reason_lower:
            return keyword
    return reason_lower[:40].strip()


class LemmaDeveloper:
    """Iterative proof loop for 'adapted' and 'new' lemmas.

    Reuses Prover / Verifier / CounterexampleSearcher / Refiner from the
    existing stage files unchanged.  Only lemmas with provenance 'adapted'
    or 'new' (as set by ProofArchitect) enter this loop; 'known' lemmas are
    recorded as proven-by-citation automatically.
    """

    def __init__(
        self,
        bus: KnowledgeBus,
        prover: Prover | None = None,
        verifier: Verifier | None = None,
        cx_searcher: CounterexampleSearcher | None = None,
        refiner: Refiner | None = None,
        skill_injector: SkillInjector | None = None,
        memory: MemoryManager | None = None,
    ) -> None:
        self.bus = bus
        self.prover = prover or Prover()
        self.verifier = verifier or Verifier()
        self.cx_searcher = cx_searcher or CounterexampleSearcher()
        self.refiner = refiner or Refiner()
        self.skill_injector = skill_injector
        self.memory = memory
        self._failure_log: list[FailedAttempt] = []
        self._lemma_failure_sigs: dict[str, list[str]] = {}

    async def run_iterative(
        self,
        state: TheoryState,
        max_iterations: int,
        stagnation_window: int,
        domain: str = "",
    ) -> TheoryState:
        """Drive the iterative proof loop for all open goals."""
        # First: auto-record all "known" lemmas as proven-by-citation
        state = self._record_known_lemmas(state)
        self.bus.put_theory_state(state)

        # Retrieve skill block once for the whole loop (skills don't change
        # between lemmas within a session).  Falls back to "" if no injector.
        skill_context = self._build_skill_context()

        for iteration in range(max_iterations):
            logger.info(
                "=== LemmaDeveloper iteration %d/%d — %d open goals ===",
                iteration + 1, max_iterations, len(state.open_goals),
            )
            state.iteration = iteration

            if not state.open_goals:
                if state.proven_lemmas:
                    state.status = "proved"
                    logger.info("No open goals — all extracted lemmas proved.")
                else:
                    logger.info(
                        "No open goals — continuing with skeleton-driven assembly without independent lemmas."
                    )
                break

            goal_proved = True
            for lemma_id in list(state.open_goals):
                logger.info("Attempting proof of lemma: %s", lemma_id)

                # --- Tier 1: collect in-session past failures for this lemma ---
                past_failures = [
                    f.failure_reason for f in self._failure_log
                    if f.lemma_id == lemma_id
                ][-3:]

                # --- Tier 2: recall cross-session hint from persistent memory ---
                cross_session_hint: str | None = None
                if self.memory:
                    cross_session_hint = self.memory.recall(
                        f"proof_hint.{domain}.{lemma_id}"
                    )
                    if cross_session_hint:
                        logger.debug(
                            "Recalled cross-session hint for %s (%d chars)",
                            lemma_id, len(cross_session_hint),
                        )

                # --- Proof attempt (skills + memory injected into system prompt) ---
                proof_attempt = await self.prover.attempt(
                    state, lemma_id,
                    past_failures=past_failures or None,
                    cross_session_hint=cross_session_hint,
                    skill_context=skill_context,
                )

                # --- Verification (fast-path skip for very low confidence) ---
                if proof_attempt.confidence < 0.3:
                    logger.info(
                        "Skipping verification (conf=%.2f < 0.3) for %s",
                        proof_attempt.confidence, lemma_id,
                    )
                    from eurekaclaw.agents.theory.verifier import VerificationResult
                    verification = VerificationResult(
                        lemma_id=lemma_id,
                        passed=False,
                        method="llm_check",
                        confidence=proof_attempt.confidence,
                        errors=proof_attempt.gaps or ["Very low confidence"],
                        notes="Auto-rejected: confidence < 0.3",
                    )
                else:
                    verification = await self.verifier.check(proof_attempt, state)

                if verification.passed:
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
                    self._lemma_failure_sigs.pop(lemma_id, None)
                    logger.info("✓ Lemma proved: %s (method=%s)", lemma_id, verification.method)

                    # --- Tier 2: persist proof hint for future sessions ---
                    if self.memory:
                        self.memory.remember(
                            key=f"proof_hint.{domain}.{lemma_id}",
                            value=proof_attempt.proof_text[:400],
                            tags=[domain, "proof_hint"],
                            source_session=state.session_id,
                        )

                    self.bus.put_theory_state(state)
                    continue

                # --- Failure handling ---
                failure_reason = "; ".join(verification.errors[:3]) or "verification failed"
                failure = FailedAttempt(
                    lemma_id=lemma_id,
                    attempt_text=proof_attempt.proof_text[:500],
                    failure_reason=failure_reason,
                    iteration=iteration,
                )
                state.failed_attempts.append(failure)
                self._failure_log.append(failure)

                # Stagnation detection
                sig = _error_signature(failure_reason)
                sigs = self._lemma_failure_sigs.setdefault(lemma_id, [])
                sigs.append(sig)
                recent = sigs[-stagnation_window:]
                stagnant = (
                    len(recent) >= stagnation_window and len(set(recent)) <= 2
                )

                if stagnant:
                    logger.warning(
                        "Stagnation on lemma '%s' after %d similar failures — forcing refinement",
                        lemma_id, len(recent),
                    )
                    cx = Counterexample(
                        lemma_id=lemma_id,
                        counterexample_description=(
                            f"Stagnation: {stagnation_window} failures with same error pattern."
                        ),
                        falsifies_conjecture=True,
                        suggested_refinement="Refine the proof plan to address the repeated failure.",
                    )
                    state.counterexamples.append(cx)
                    state = await self.refiner.refine(state, lemma_id, cx)
                    state.iteration = iteration + 1
                    self.bus.put_theory_state(state)
                    goal_proved = False
                    self._lemma_failure_sigs.clear()
                    break

                # Counterexample search
                cx = await self.cx_searcher.search(
                    state, lemma_id,
                    failure_reason=failure.failure_reason,
                    proof_text=proof_attempt.proof_text,
                )
                state.counterexamples.append(cx)

                if cx.falsifies_conjecture:
                    logger.warning("Counterexample for %s — refining proof plan", lemma_id)
                    state = await self.refiner.refine(state, lemma_id, cx)
                    state.iteration = iteration + 1
                    self.bus.put_theory_state(state)
                    goal_proved = False
                    self._lemma_failure_sigs.clear()
                    break
                else:
                    # No counterexample — accept with low confidence and move on
                    logger.warning(
                        "No counterexample for %s — accepting with low confidence", lemma_id
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

            if goal_proved and not state.open_goals and state.proven_lemmas:
                state.status = "proved"
                logger.info("All lemmas proved!")
                break
        else:
            if state.open_goals:
                state.status = "abandoned"
                logger.warning(
                    "LemmaDeveloper exhausted %d iterations; %d goals remain open.",
                    max_iterations, len(state.open_goals),
                )

        return state

    def _build_skill_context(self) -> str:
        """Retrieve theory skills and render them as an XML block for the prover.

        Uses the injector's tag-based retrieval filtered to the "theory" role,
        which matches any skill with ``agent_roles: [theory]`` in its frontmatter.
        Returns an empty string when no injector is configured.
        """
        if self.skill_injector is None:
            return ""
        skills = self.skill_injector.registry.get_by_role("theory")
        if not skills:
            return ""
        block = self.skill_injector.render_for_prompt(skills)
        logger.debug("LemmaDeveloper: injecting %d theory skills into prover", len(skills))
        return block

    def _record_known_lemmas(self, state: TheoryState) -> TheoryState:
        """Auto-record 'known' lemmas as citation-proven without an LLM call."""
        for pp in state.proof_plan:
            if pp.provenance == "known" and pp.lemma_id not in state.proven_lemmas:
                state.proven_lemmas[pp.lemma_id] = ProofRecord(
                    lemma_id=pp.lemma_id,
                    proof_text=f"Cited from: {pp.source or 'existing literature'}.\n{pp.statement}",
                    verification_method="peer_review",
                    verified=True,
                    verifier_notes=f"Known result — cited from: {pp.source}",
                    proved_at=datetime.utcnow(),
                )
                logger.info("Recorded known lemma by citation: %s ← %s", pp.lemma_id, pp.source)
        return state

    @property
    def failure_log(self) -> list[FailedAttempt]:
        return list(self._failure_log)


# Populate registry now that all classes are defined
STAGE_REGISTRY = {
    "PaperReader": PaperReader,
    "GapAnalyst": GapAnalyst,
    "MemoryGuidedAnalyzer": MemoryGuidedAnalyzer,
    "TemplateSelector": TemplateSelector,
    "ProofSkeletonBuilder": ProofSkeletonBuilder,
    "KeyLemmaExtractor": KeyLemmaExtractor,
    "ProofArchitect": ProofArchitect,
    "LemmaDeveloper": LemmaDeveloper,
    "Assembler": Assembler,
    "TheoremCrystallizer": TheoremCrystallizer,
    "ConsistencyChecker": ConsistencyChecker,
}


# ---------------------------------------------------------------------------
# TheoryInnerLoopYaml — the YAML-driven outer executor
# ---------------------------------------------------------------------------

class TheoryInnerLoopYaml:
    """Loads a proof pipeline spec from YAML and executes its stages.

    Usage:
        loop = TheoryInnerLoopYaml(bus)
        state = await loop.run(session_id, domain)

    To use a custom pipeline spec:
        loop = TheoryInnerLoopYaml(bus, spec_path=Path("my_pipeline.yaml"))
    """

    def __init__(
        self,
        bus: KnowledgeBus,
        spec_path: Path | None = None,
        skill_injector: SkillInjector | None = None,
        memory: MemoryManager | None = None,
    ) -> None:
        self.bus = bus
        self.spec_path = spec_path or _SPEC_BY_NAME.get(settings.theory_pipeline, _DEFAULT_SPEC)
        self._spec: list[dict] = self._load_spec()
        self._skill_injector = skill_injector
        self._memory = memory
        # Shared sub-components injected into stages that need them
        self._prover = Prover()
        self._verifier = Verifier()
        self._cx_searcher = CounterexampleSearcher()
        self._refiner = Refiner()

    def _load_spec(self) -> list[dict]:
        with self.spec_path.open() as fh:
            data = yaml.safe_load(fh)
        stages = data.get("stages", [])
        logger.info(
            "TheoryInnerLoopYaml: loaded %d stages from %s",
            len(stages), self.spec_path.name,
        )
        return stages

    def _instantiate(self, class_name: str) -> Any:
        cls = STAGE_REGISTRY.get(class_name)
        if cls is None:
            raise ValueError(
                f"Unknown stage class '{class_name}'. "
                f"Available: {list(STAGE_REGISTRY.keys())}"
            )
        # Stages that need the bus or sub-components receive them here
        if cls is PaperReader:
            return PaperReader(bus=self.bus)
        if cls is GapAnalyst:
            return GapAnalyst(bus=self.bus)
        if cls is MemoryGuidedAnalyzer:
            return MemoryGuidedAnalyzer(memory=self._memory)
        if cls is TemplateSelector:
            return TemplateSelector()
        if cls is ProofSkeletonBuilder:
            return ProofSkeletonBuilder()
        if cls is KeyLemmaExtractor:
            return KeyLemmaExtractor()
        if cls is LemmaDeveloper:
            return LemmaDeveloper(
                bus=self.bus,
                prover=self._prover,
                verifier=self._verifier,
                cx_searcher=self._cx_searcher,
                refiner=self._refiner,
                skill_injector=self._skill_injector,
                memory=self._memory,
            )
        return cls()

    async def run(self, session_id: str, domain: str = "") -> TheoryState:
        """Execute the proof pipeline from start to completion."""
        state = self.bus.get_theory_state()
        if not state:
            raise ValueError(
                "No TheoryState on KnowledgeBus. Initialize it before calling run()."
            )

        state.status = "in_progress"
        self.bus.put_theory_state(state)

        # Outer iteration: the consistency_checker may fail and require
        # re-running TheoremCrystallizer.  We loop at most max_outer times.
        max_outer = settings.theory_max_iterations
        for outer_iter in range(max_outer):
            logger.info("=== Proof pipeline outer iteration %d/%d ===", outer_iter + 1, max_outer)

            for stage_spec in self._spec:
                name = stage_spec["name"]
                class_name = stage_spec["class"]
                mode = stage_spec.get("mode", "once")
                description = stage_spec.get("description", name)

                logger.info("[%s] %s", name, description)
                instance = self._instantiate(class_name)

                if mode == "iterative":
                    max_iter = int(stage_spec.get("max_iterations", settings.theory_max_iterations))
                    stagnation = int(stage_spec.get("stagnation_window", settings.stagnation_window))
                    state = await instance.run_iterative(
                        state,
                        max_iterations=max_iter,
                        stagnation_window=stagnation,
                        domain=domain,
                    )
                else:
                    max_retries = int(stage_spec.get("max_retries", 1))
                    state = await self._run_once(instance, state, domain, max_retries)

                self.bus.put_theory_state(state)

                # Early exit if the proof loop was abandoned or refuted
                if state.status in ("abandoned", "refuted"):
                    logger.warning(
                        "Pipeline halted after stage '%s': status=%s", name, state.status
                    )
                    return state

            # After a full pass: if consistency_checker set status=in_progress,
            # we need another outer iteration (only for theorem_crystallizer + checker).
            # If status=proved, we're done.
            if state.status == "proved":
                logger.info("Pipeline complete: theorem proved and consistent.")
                break

            # On retry: decide which stages to re-run based on the failure type.
            # Uncited-lemma failures require re-running the assembler (it needs to
            # add [lemma_id] citations); other failures only need re-crystallization.
            last_failure = state.failed_attempts[-1] if state.failed_attempts else None
            uncited_issue = last_failure and any(
                kw in last_failure.failure_reason.lower()
                for kw in ("never cited", "uncited", "missing citation", "not cited")
            )
            if uncited_issue:
                retry_stages = ("assembler", "theorem_crystallizer", "consistency_checker")
                logger.info(
                    "Consistency check failed (uncited lemmas) — re-running assembler + crystallizer (outer iter %d)",
                    outer_iter + 1,
                )
            else:
                retry_stages = ("theorem_crystallizer", "consistency_checker")
                logger.info(
                    "Consistency check failed — re-running crystallizer (outer iter %d)",
                    outer_iter + 1,
                )
            self._spec = [s for s in self._spec if s["name"] in retry_stages]
        else:
            if state.status != "proved":
                state.status = "abandoned"
                logger.warning("Proof pipeline exhausted outer iterations without consistency.")

        self.bus.put_theory_state(state)
        return state

    async def _run_once(
        self,
        instance: Any,
        state: TheoryState,
        domain: str,
        max_retries: int,
    ) -> TheoryState:
        """Run a once-mode stage with simple retry on exception."""
        for attempt in range(max(1, max_retries + 1)):
            try:
                return await instance.run(state, domain=domain)
            except Exception as e:
                logger.warning(
                    "Stage %s attempt %d/%d failed: %s",
                    type(instance).__name__, attempt + 1, max_retries + 1, e,
                )
                if attempt >= max_retries:
                    logger.error("Stage %s failed permanently.", type(instance).__name__)
                    return state  # return unchanged state; pipeline continues
        return state

    @property
    def failure_log(self) -> list[FailedAttempt]:
        # Collect from the LemmaDeveloper instance if it was run
        # (not directly accessible post-run; kept for API compatibility)
        return []
