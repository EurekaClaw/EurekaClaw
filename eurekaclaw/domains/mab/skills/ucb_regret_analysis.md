---
name: ucb_regret_analysis
description: Prove instance-dependent and minimax regret bounds for UCB-style algorithms
tags: [bandit, ucb, regret, concentration]
domain: stochastic_mab
---

# UCB Regret Analysis Skill

## Core Decomposition
For UCB1 on a K-arm stochastic bandit with gaps Δᵢ = μ* - μᵢ:

**Regret decomposition:**
$$R_T = \sum_{i \neq i^*} \Delta_i \cdot \mathbb{E}[N_i(T)]$$

**UCB1 pull count bound (instance-dependent):**
$$\mathbb{E}[N_i(T)] \leq \frac{8 \log T}{\Delta_i^2} + 1 + \frac{\pi^2}{3}$$

**Instance-dependent bound:**
$$R_T \leq \sum_{i \neq i^*} \left(\frac{8 \log T}{\Delta_i} + \Delta_i\left(1 + \frac{\pi^2}{3}\right)\right)$$

**Minimax bound** (optimize over gap Δ):
$$R_T = O\left(\sqrt{KT \log T}\right)$$

## Proof Strategy
1. **UCB guarantee:** Arm i is pulled at time t only if UCB_i(t) ≥ UCB_{i*}(t).
2. **Confidence interval:** With probability ≥ 1 - t^{-4}, |μ̂ᵢ(t) - μᵢ| ≤ √(2 log t / Nᵢ(t)).
3. **Key event:** If arm i is suboptimal and N_i(t) > 8 log T / Δᵢ², then the UCB for i is below μ* with high probability.
4. **Union bound** over rounds.

## Validation
Use `run_bandit_experiment` with T_sweep=[1000,3000,10000,30000] to verify:
- log-log slope ≈ 0.5 for minimax (Gaussian, equal gaps)
- Absolute regret matches theoretical formula (within constant factor)
