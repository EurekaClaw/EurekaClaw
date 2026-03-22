"""Stochastic bandit environments — Gaussian and Bernoulli."""

from __future__ import annotations

from typing import Optional

import numpy as np


class GaussianBandit:
    def __init__(
        self,
        means: list[float],
        std: float = 1.0,
        rng: Optional[np.random.Generator] = None,
    ):
        self.means = np.array(means)
        self.std = std
        self.rng = rng or np.random.default_rng()
        self.best_mean = float(np.max(self.means))

    def pull(self, arm: int) -> float:
        return float(self.rng.normal(self.means[arm], self.std))

    def gaps(self) -> list[float]:
        return [float(self.best_mean - m) for m in self.means]

    @property
    def n_arms(self) -> int:
        return len(self.means)


class BernoulliBandit:
    def __init__(
        self,
        probs: list[float],
        rng: Optional[np.random.Generator] = None,
    ):
        self.probs = np.array(probs)
        self.rng = rng or np.random.default_rng()
        self.best_prob = float(np.max(self.probs))

    def pull(self, arm: int) -> float:
        return float(self.rng.random() < self.probs[arm])

    def gaps(self) -> list[float]:
        return [float(self.best_prob - p) for p in self.probs]

    @property
    def n_arms(self) -> int:
        return len(self.probs)
