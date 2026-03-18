"""ContinualLearningLoop — MetaClaw-style cross-run improvement.

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
        failures: list[FailedAttempt] = theory_state.failed_attempts if theory_state else []
        successes: list[ProofRecord] = list(theory_state.proven_lemmas.values()) if theory_state else []

        # Always: skill distillation
        if failures or successes:
            new_skills = await self.skill_evolver.distill_from_session(
                session_id=bus.session_id,
                failures=failures,
                successes=successes,
            )
            if new_skills:
                logger.info("Distilled %d new skills", len(new_skills))

        # RL mode: PRM scoring
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
