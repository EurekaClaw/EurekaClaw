---
name: thompson_sampling_analysis
description: Analyze Thompson Sampling regret via posterior concentration and information-theoretic lower bounds
tags: [bandit, thompson_sampling, bayesian, regret, lower_bound]
domain: stochastic_mab
---

# Thompson Sampling Analysis Skill

## Regret Bound
Thompson Sampling achieves the asymptotically optimal (Lai-Robbins) regret for exponential families:

$$R_T \leq (1 + \varepsilon) \sum_{i \neq i^*} \frac{\log T}{\text{KL}(\mu_i, \mu^*)} + O\left(\frac{K}{\varepsilon^2}\right)$$

For Bernoulli bandits, this matches the lower bound exactly.

## Proof Strategy (Bernoulli case)
1. **Posterior convergence:** After n pulls of arm i, Beta(α, β) posterior concentrates around μᵢ.
2. **Optimism in expectation:** E[θᵢ | history] ≈ μ̂ᵢ, but Thompson Sampling matches frequentist UCB in regret (not identically).
3. **Information-theoretic argument:** Use the divergence decomposition lemma — any algorithm that achieves sublinear regret on instance ν must also have sublinear regret on nearby instance ν'.
4. **KL-based bound:** E[N_i(T)] ≥ (log T / KL(μᵢ, μ*)) - O(1) by the Lai-Robbins argument.

## Key Tools
- `kl_bernoulli(p, q)` from `eurekaclaw.tools.information` for divergence
- `lai_robbins_lower_bound(gaps, T, kl_values)` from `eurekaclaw.tools.regret`
- `run_bandit_experiment` with algorithm="thompson" for empirical validation

## Concentration Ingredients
For Bernoulli(p): KL(p, q) = p log(p/q) + (1-p) log((1-p)/(1-q))
- When p > q: KL(p,q) ≥ 2(p-q)²  (Pinsker's inequality)
- Better bound: KL(p,q) ≥ (p-q)² / (2p(1-p))
