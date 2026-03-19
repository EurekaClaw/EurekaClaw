"""ContinualLearningLoop: cross-run improvement.

Three modes:
- skills_only: skill distillation only (default, no GPU needed)
- rl: skills + PRM scoring + async cloud LoRA (GRPO)
- madmax: skills + OMLS-scheduled RL
"""

from __future__ import annotations

import logging
from typing import Literal

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.learning.failure_capture import FailureCapturer
from eurekaclaw.learning.prm_scorer import ProcessRewardModel
from eurekaclaw.skills.evolver import SkillEvolver
from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.types.artifacts import FailedAttempt, ProofRecord

logger = logging.getLogger(__name__)

# Minimum number of novel failures before skill distillation runs.
# Below this threshold there isn't enough new signal to warrant an LLM call.
_MIN_NOVEL_FAILURES = 2


def _deduplicate_failures(failures: list[FailedAttempt]) -> list[FailedAttempt]:
    """Return only unique failure instances (by lemma_id + first 80 chars of reason).

    EurekaClaw / ScienceClaw pattern: pass only novel signal to the skill
    evolver rather than every raw failure.  Repetitive failures with the same
    reason add no new information and waste evolver tokens.
    """
    seen: set[str] = set()
    unique: list[FailedAttempt] = []
    for f in failures:
        key = f"{f.lemma_id}::{f.failure_reason[:80]}"
        if key not in seen:
            seen.add(key)
            unique.append(f)
    return unique


def _compress_success(record: ProofRecord) -> ProofRecord:
    """Return a copy of the ProofRecord with the proof_text trimmed to 300 chars.

    The skill evolver needs to understand *what* was proved and *how* (strategy),
    not the full formal proof.  Keeping only the opening strategy + QED marker
    cuts evolver input tokens by ~60%.
    """
    if len(record.proof_text) <= 300:
        return record
    # Head (strategy) + tail (QED) compressed copy
    head = record.proof_text[:200]
    tail = record.proof_text[-80:]
    compressed_text = f"{head}\n...\n{tail}"
    # Return a shallow copy with modified proof_text
    import copy
    compressed = copy.copy(record)
    compressed.proof_text = compressed_text
    return compressed


class ContinualLearningLoop:
    """Intercepts run outputs and improves skills/weights for future runs."""

    def __init__(
        self,
        mode: Literal["skills_only", "rl", "madmax"] = "skills_only",
        skill_registry: SkillRegistry | None = None,
        client: LLMClient | None = None,
    ) -> None:
        self.mode = mode
        self.client: LLMClient = client or create_client()
        _registry = skill_registry or SkillRegistry()
        self.failure_capture = FailureCapturer()
        self.skill_evolver = SkillEvolver(registry=_registry, client=self.client)
        self.prm = ProcessRewardModel(client=self.client) if mode in ("rl", "madmax") else None

    async def post_run(self, pipeline: "TaskPipeline", bus: "KnowledgeBus") -> None:  # type: ignore[name-defined]
        """Run post-session learning. Called after the pipeline completes."""
        from eurekaclaw.knowledge_bus.bus import KnowledgeBus
        from eurekaclaw.types.tasks import TaskPipeline

        logger.info("Post-run learning (mode=%s)...", self.mode)

        # Extract theory state failures and successes
        theory_state = bus.get_theory_state()
        raw_failures: list[FailedAttempt] = theory_state.failed_attempts if theory_state else []
        raw_successes: list[ProofRecord] = list(theory_state.proven_lemmas.values()) if theory_state else []

        # --- Deduplicate failures (EurekaClaw pattern: only novel signal) ---
        failures = _deduplicate_failures(raw_failures)
        novel_count = len(failures)
        if novel_count < len(raw_failures):
            logger.info(
                "Deduplicated failures: %d → %d novel (removed %d duplicates)",
                len(raw_failures), novel_count, len(raw_failures) - novel_count,
            )

        # --- Compress success proof texts to reduce evolver input tokens ---
        successes = [_compress_success(r) for r in raw_successes]

        # Skill distillation: only run if there is enough novel signal
        if novel_count >= _MIN_NOVEL_FAILURES or len(successes) >= 5:
            new_skills = await self.skill_evolver.distill_from_session(
                session_id=bus.session_id,
                failures=failures,
                successes=successes,
            )
            if new_skills:
                logger.info("Distilled %d new skills", len(new_skills))
        elif failures or successes:
            logger.info(
                "Skipping skill distillation: only %d novel failure(s) and %d success(es) "
                "(threshold: %d failures or 5 successes)",
                novel_count, len(successes), _MIN_NOVEL_FAILURES,
            )

        # RL mode: PRM scoring — only for proved or novel-failure trajectories
        if self.mode in ("rl", "madmax") and self.prm:
            trajectories = self.failure_capture.get_proof_trajectories()
            if trajectories:
                logger.info("PRM scoring %d trajectories...", len(trajectories))
                scored = await self.prm.score(trajectories)
                avg_score = sum(t.score for t in scored) / len(scored) if scored else 0
                logger.info("Average PRM score: %.3f", avg_score)
                # Log scores for future LoRA training
                bus.put("prm_scores", [{"lemma_id": t.lemma_id, "score": t.score} for t in scored])

        # madmax: OMLS scheduler would defer training to idle windows
        # (stub — full implementation requires cloud training infrastructure)
        if self.mode == "madmax":
            logger.info("OMLS: Training deferred to next idle window (stub)")

        logger.info("Post-run learning complete")
