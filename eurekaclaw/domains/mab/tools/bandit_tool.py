"""BanditExperimentTool — LLM-callable tool for MAB simulations."""

from __future__ import annotations

import json
from typing import Any

from eurekaclaw.tools.base import BaseTool


class BanditExperimentTool(BaseTool):
    name = "run_bandit_experiment"
    description = (
        "Run multi-armed bandit (MAB) simulations to empirically validate theoretical bounds. "
        "Supports UCB1 and Thompson Sampling on Gaussian and Bernoulli bandits. "
        "Use T_sweep to measure log-log scaling slope and verify O(√(KT log T)) behaviour. "
        "Returns regret statistics as JSON."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "bandit_type": {
                    "type": "string",
                    "enum": ["gaussian", "bernoulli"],
                    "description": "Bandit environment type.",
                },
                "bandit_params": {
                    "type": "object",
                    "description": (
                        "gaussian → {\"means\": [0.0, -0.5, -1.0], \"std\": 1.0}  "
                        "bernoulli → {\"probs\": [0.7, 0.4, 0.2]}"
                    ),
                },
                "algorithm": {
                    "type": "string",
                    "enum": ["ucb1", "thompson"],
                    "description": "Algorithm to evaluate.",
                },
                "T": {
                    "type": "integer",
                    "description": "Horizon (rounds). Ignored when T_sweep is set.",
                    "default": 10000,
                },
                "T_sweep": {
                    "type": "array",
                    "items": {"type": "integer"},
                    "description": (
                        "List of horizon values to sweep. "
                        "Returns log_log_slope (≈0.5 for O(√T), ≈1 for O(T log T))."
                    ),
                },
                "n_seeds": {
                    "type": "integer",
                    "description": "Random seeds for averaging.",
                    "default": 20,
                },
            },
            "required": ["bandit_type", "bandit_params", "algorithm"],
        }

    async def call(  # type: ignore[override]
        self,
        bandit_type: str,
        bandit_params: dict[str, Any],
        algorithm: str,
        T: int = 10000,
        T_sweep: list[int] | None = None,
        n_seeds: int = 20,
    ) -> str:
        try:
            from eurekaclaw.domains.mab.envs import run_experiment, sweep_T
            from eurekaclaw.domains.mab.envs.stochastic import BernoulliBandit, GaussianBandit

            if T_sweep:
                return json.dumps(
                    sweep_T(bandit_type, bandit_params, algorithm, T_sweep, n_seeds),
                    indent=2,
                )

            bandit = GaussianBandit(**bandit_params) if bandit_type == "gaussian" else BernoulliBandit(**bandit_params)
            result = run_experiment(bandit, algorithm, T=T, n_seeds=n_seeds)

            # Downsample curve for LLM consumption
            curve = result.pop("regret_curve")
            result["regret_curve_sampled"] = curve[::max(1, len(curve) // 20)]

            return json.dumps({"bandit_type": bandit_type, "algorithm": algorithm, "T": T, **result}, indent=2)
        except Exception as e:
            return json.dumps({"error": str(e)})
