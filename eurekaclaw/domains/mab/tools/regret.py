"""Regret decomposition utilities for bandit theory analysis."""

from __future__ import annotations

import math


def decompose_regret(gaps: list[float], pull_counts: list[float]) -> dict:
    """Standard regret decomposition: R_T = sum_i Delta_i * E[N_i(T)]."""
    total = sum(g * n for g, n in zip(gaps, pull_counts))
    per_arm = [
        {"gap": g, "pulls": n, "contribution": g * n}
        for g, n in zip(gaps, pull_counts)
    ]
    return {"total_regret": total, "per_arm": per_arm}


def lai_robbins_lower_bound(gaps: list[float], T: int, kl_values: list[float]) -> float:
    """Asymptotic Lai-Robbins lower bound: sum_i (log T / KL(mu_i, mu*)).

    Args:
        gaps: Delta_i for each suboptimal arm
        T: horizon
        kl_values: KL(mu_i, mu*) for each suboptimal arm
    """
    lb = 0.0
    for delta, kl in zip(gaps, kl_values):
        if delta > 0 and kl > 0:
            lb += math.log(T) / kl
    return lb
