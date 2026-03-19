"""MAB-specific research workflow guidance for EurekaClaw agents."""

WORKFLOW_HINT = """\
## Domain: Stochastic Multi-Armed Bandits (MAB)

### Mathematical Notation
- K arms, horizon T, arm means μ₁ ≥ μ₂ ≥ … ≥ μ_K
- Optimal arm: i* = argmax_i μᵢ, optimal mean: μ* = μ_{i*}
- Sub-optimality gap: Δᵢ = μ* - μᵢ  (Δᵢ > 0 for suboptimal arms)
- Cumulative regret: R_T = Σ_t (μ* - μ_{A_t}) = Σᵢ Δᵢ · E[Nᵢ(T)]

### Key Proof Techniques
1. **Regret decomposition** — always start here: R_T = Σᵢ Δᵢ · E[Nᵢ(T)]
2. **Confidence interval argument** — arm i is "wrongly preferred" only when UCB_i ≥ μ*
   → pull count bounded by how long this can happen given Δᵢ
3. **Peeling / change-of-measure** — for lower bounds: KL(Pᵢ, Qᵢ) controls how hard
   it is to distinguish two instances
4. **Fano / Le Cam** — minimax lower bounds via hypothesis testing on hard instances

### Available Domain Tools
- `run_bandit_experiment` — run UCB1 / Thompson Sampling simulations, sweep T values
  → verify log-log slope (≈0.5 for O(√T·log T) minimax)
- `wolfram_alpha` — compute explicit constant values, solve for optimal ε in lower bound proofs
- `execute_python` — for custom experiments beyond the built-in algorithms

### Experiment-Theory Alignment Checklist
- [ ] Instance-dependent bound: regret_mean ≤ Σᵢ 8·log(T)/Δᵢ (within 2x for T=50k)
- [ ] Minimax scaling: log-log slope from T_sweep ∈ [0.45, 0.65] for standard UCB1
- [ ] Lower bound: reported lb ≤ empirical regret (lower bounds must be satisfied!)
- [ ] Thompson Sampling vs UCB1: TS should be ≤ 20% higher regret on Bernoulli instances

### Common Pitfalls
- Off-by-one in initial exploration (first K rounds: pull each arm once)
- Forgetting the additive Δ(1 + π²/3) term in instance-dependent UCB1 bound
- Confusing instance-dependent (O(log T / Δ)) with minimax (O(√(KT log T))) bounds
"""
