"""Bandit algorithm runners for empirical validation experiments."""

from __future__ import annotations

import math
from typing import Union

import numpy as np

from eurekaclaw.domains.mab.envs.stochastic import BernoulliBandit, GaussianBandit

BanditType = Union[GaussianBandit, BernoulliBandit]


def _ucb1(bandit: BanditType, T: int, rng: np.random.Generator) -> np.ndarray:
    """Run UCB1 for T rounds. Returns cumulative regret array."""
    K = bandit.n_arms
    counts = np.zeros(K)
    rewards = np.zeros(K)
    regret = np.zeros(T)
    gaps = np.array(bandit.gaps())

    for arm in range(min(K, T)):
        r = bandit.pull(arm)
        counts[arm] += 1
        rewards[arm] += r
        regret[arm] = gaps[arm]

    for t in range(K, T):
        ucb = rewards / counts + np.sqrt(2 * np.log(t + 1) / counts)
        arm = int(np.argmax(ucb))
        r = bandit.pull(arm)
        counts[arm] += 1
        rewards[arm] += r
        regret[t] = gaps[arm]

    return np.cumsum(regret)


def _thompson_bernoulli(bandit: BernoulliBandit, T: int, rng: np.random.Generator) -> np.ndarray:
    """Thompson Sampling for Bernoulli bandit."""
    K = bandit.n_arms
    alpha = np.ones(K)
    beta_params = np.ones(K)
    regret = np.zeros(T)
    gaps = np.array(bandit.gaps())

    for t in range(T):
        samples = rng.beta(alpha, beta_params)
        arm = int(np.argmax(samples))
        r = bandit.pull(arm)
        alpha[arm] += r
        beta_params[arm] += 1 - r
        regret[t] = gaps[arm]

    return np.cumsum(regret)


def _thompson_gaussian(bandit: GaussianBandit, T: int, rng: np.random.Generator) -> np.ndarray:
    """Thompson Sampling for Gaussian bandit (known variance)."""
    K = bandit.n_arms
    counts = np.zeros(K)
    means_est = np.zeros(K)
    regret = np.zeros(T)
    gaps = np.array(bandit.gaps())

    for t in range(T):
        precision = counts + 1.0
        posterior_means = means_est * counts / precision
        posterior_std = bandit.std / np.sqrt(precision)
        samples = rng.normal(posterior_means, posterior_std)
        arm = int(np.argmax(samples))
        r = bandit.pull(arm)
        counts[arm] += 1
        means_est[arm] += (r - means_est[arm]) / counts[arm]
        regret[t] = gaps[arm]

    return np.cumsum(regret)


def run_experiment(
    bandit: BanditType,
    algorithm: str,
    T: int,
    n_seeds: int = 20,
) -> dict:
    """Run algorithm on bandit for T rounds with n_seeds random seeds.

    Returns:
        {
            "regret_mean": float,   # mean final cumulative regret across seeds
            "regret_std": float,    # std across seeds
            "regret_curve": list[float],  # mean regret curve (length T)
        }
    """
    curves = []
    for seed in range(n_seeds):
        rng = np.random.default_rng(seed)
        bandit.rng = np.random.default_rng(seed + 10000)

        alg = algorithm.lower()
        if alg == "ucb1":
            curve = _ucb1(bandit, T, rng)
        elif alg in ("thompson", "ts"):
            if isinstance(bandit, BernoulliBandit):
                curve = _thompson_bernoulli(bandit, T, rng)
            else:
                curve = _thompson_gaussian(bandit, T, rng)
        else:
            raise ValueError(f"Unknown algorithm: {algorithm!r}. Choose 'ucb1' or 'thompson'.")
        curves.append(curve)

    curves_arr = np.array(curves)
    return {
        "regret_mean": float(curves_arr[:, -1].mean()),
        "regret_std": float(curves_arr[:, -1].std()),
        "regret_curve": curves_arr.mean(axis=0).tolist(),
    }


def sweep_T(
    bandit_type: str,
    bandit_params: dict,
    algorithm: str,
    T_values: list[int],
    n_seeds: int = 20,
) -> dict:
    """Sweep over horizon values T and return results + log-log slope.

    Args:
        bandit_type: "gaussian" or "bernoulli"
        bandit_params: {"means": [...], "std": 1.0} or {"probs": [...]}
        algorithm: "ucb1" or "thompson"
        T_values: list of horizon values to test
        n_seeds: seeds per T value

    Returns:
        {
            "results": [{"T": int, "regret_mean": float, "regret_std": float}, ...],
            "log_log_slope": float | None,  # ~0.5 for O(sqrt(T)), ~1.0 for O(T log T)
        }
    """
    results = []
    regret_finals = []

    for T in T_values:
        if bandit_type == "gaussian":
            bandit: BanditType = GaussianBandit(**bandit_params)
        else:
            bandit = BernoulliBandit(**bandit_params)

        res = run_experiment(bandit, algorithm, T=T, n_seeds=n_seeds)
        results.append({"T": T, "regret_mean": res["regret_mean"], "regret_std": res["regret_std"]})
        regret_finals.append((T, res["regret_mean"]))

    # Compute log-log slope via OLS
    slope = None
    valid = [(math.log(t), math.log(r)) for t, r in regret_finals if t > 0 and r > 0]
    if len(valid) >= 2:
        xs = [x for x, _ in valid]
        ys = [y for _, y in valid]
        x_mean = sum(xs) / len(xs)
        y_mean = sum(ys) / len(ys)
        num = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
        den = sum((x - x_mean) ** 2 for x in xs)
        if den > 0:
            slope = round(num / den, 4)

    return {"results": results, "log_log_slope": slope}
