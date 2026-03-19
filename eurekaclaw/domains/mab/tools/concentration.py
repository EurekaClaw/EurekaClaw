"""Concentration inequality utilities for theoretical bound computation."""

from __future__ import annotations

import math


def hoeffding_bound(n: int, range_: float, delta: float) -> float:
    """Returns t such that P(|mean - mu| >= t) <= delta, via Hoeffding's inequality."""
    return range_ * math.sqrt(math.log(2.0 / delta) / (2.0 * n))


def bernstein_bound(n: int, variance: float, range_: float, delta: float) -> float:
    """Bernstein's inequality. Tighter than Hoeffding when variance is small."""
    log_term = math.log(2.0 / delta)
    return math.sqrt(2.0 * variance * log_term / n) + (2.0 * range_ * log_term) / (3.0 * n)


def subgaussian_bound(n: int, sigma: float, delta: float) -> float:
    """Sub-Gaussian tail bound: P(|mean - mu| >= t) <= delta."""
    return sigma * math.sqrt(2.0 * math.log(2.0 / delta) / n)


def ucb_confidence_radius(t: int, s: int, delta: float) -> float:
    """UCB confidence radius: sqrt(2 * log(1/delta) / s)."""
    if s <= 0:
        return float("inf")
    return math.sqrt(2.0 * math.log(1.0 / delta) / s)
