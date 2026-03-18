"""Information-theoretic utilities for bandit lower bound computation."""

from __future__ import annotations

import math


def kl_bernoulli(p: float, q: float) -> float:
    """KL divergence between Bernoulli(p) and Bernoulli(q)."""
    p = max(1e-12, min(1 - 1e-12, p))
    q = max(1e-12, min(1 - 1e-12, q))
    return p * math.log(p / q) + (1 - p) * math.log((1 - p) / (1 - q))


def kl_gaussian(mu1: float, mu2: float, sigma: float) -> float:
    """KL divergence between N(mu1, sigma^2) and N(mu2, sigma^2)."""
    return (mu1 - mu2) ** 2 / (2.0 * sigma ** 2)


def fano_lower_bound(n_hypotheses: int, mutual_info: float) -> float:
    """Fano's inequality based lower bound on error probability."""
    if n_hypotheses <= 1:
        return 0.0
    log_M = math.log(n_hypotheses)
    return max(0.0, 1.0 - (mutual_info + math.log(2)) / log_M)
