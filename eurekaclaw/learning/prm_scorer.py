"""ProcessRewardModel — scores proof trajectories for RL training."""

from __future__ import annotations

import json
import logging

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.learning.failure_capture import ProofTrajectory

logger = logging.getLogger(__name__)

PRM_SYSTEM = """\
You are a Process Reward Model for mathematical proof trajectories. Score each proof step.

For each step, assign a score from -1 (harmful/incorrect) to +1 (helpful/correct).
The overall trajectory score is the product of step scores.
"""


class ProcessRewardModel:
    """Scores proof trajectories for GRPO fine-tuning."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def score(self, trajectories: list[ProofTrajectory]) -> list[ProofTrajectory]:
        """Score each trajectory and return with updated scores."""
        scored = []
        for traj in trajectories:
            traj.score = await self._score_trajectory(traj)
            scored.append(traj)
        return scored

    async def _score_trajectory(self, traj: ProofTrajectory) -> float:
        """Assign a scalar reward score to a proof trajectory."""
        if traj.outcome == "proved":
            return 1.0
        if traj.outcome == "counterexample":
            return -0.5  # Falsified — negative but informative

        # For failed trajectories, use LLM to estimate quality
        try:
            steps_text = "\n".join(f"Step {i+1}: {s[:200]}" for i, s in enumerate(traj.steps[:5]))
            response = await self.client.messages.create(
                model=settings.eurekaclaw_fast_model,
                max_tokens=128,
                system=PRM_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": f"Lemma: {traj.lemma_id}\nOutcome: {traj.outcome}\nSteps:\n{steps_text}\n\nReturn JSON: {{\"score\": -1.0 to 1.0}}"
                }],
            )
            text = response.content[0].text
            if "score" in text:
                data = json.loads(text[text.index("{"):text.rindex("}")+1])
                return float(data.get("score", 0.0))
        except Exception as e:
            logger.debug("PRM scoring failed: %s", e)
        return 0.0
