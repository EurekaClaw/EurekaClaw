---
name: bandit_simulation
description: Run bandit simulations with parameter sweeps to empirically validate theoretical regret bounds
tags: [bandit, simulation, empirical_validation, ucb1, thompson_sampling]
domain: stochastic_mab
---

# Bandit Simulation Skill

## When to Use
Use the `run_bandit_experiment` tool to empirically validate theoretical bounds before or after proving them formally.

## Key Checks

### 1. Verify log-log scaling (minimax)
```json
{
  "bandit_type": "gaussian",
  "bandit_params": {"means": [0.0, -0.5, -1.0], "std": 1.0},
  "algorithm": "ucb1",
  "T_sweep": [1000, 3000, 10000, 30000, 100000],
  "n_seeds": 30
}
```
Expected: `log_log_slope` ≈ 0.5 (for O(√(KT log T)) bounds).

### 2. Verify instance-dependent bound
For UCB1 with gaps [0.5, 1.0], theoretical bound is ≈ 8 log(T) / Δᵢ.
```json
{
  "bandit_type": "gaussian",
  "bandit_params": {"means": [0.0, -0.5, -1.0], "std": 1.0},
  "algorithm": "ucb1",
  "T": 50000,
  "n_seeds": 50
}
```
Compare `regret_mean` to sum_i (8 log T / Δᵢ).

### 3. Compare UCB1 vs Thompson Sampling
Run both on same bandit and report ratio of final regrets.

## Interpretation Guide
- `log_log_slope` ≈ 0.5 → O(√T) scaling ✓
- `log_log_slope` ≈ 1.0 → O(T) scaling (linear regret!) ✗
- `log_log_slope` ≈ 0.55-0.6 → O(√(T log T)) scaling (acceptable)
- `regret_mean / theoretical_bound` should be ≤ 1.0 (upper bound holds)
