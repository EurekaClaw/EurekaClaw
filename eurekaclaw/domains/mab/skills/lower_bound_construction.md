---
name: lower_bound_construction
description: Construct minimax and instance-dependent lower bounds for bandit problems using KL-divergence and Fano's inequality
tags: [bandit, lower_bound, fano, minimax, information_theory]
domain: stochastic_mab
---

# Lower Bound Construction Skill

## Minimax Lower Bound (Ω(√(KT)))
**Setup:** K arms, horizon T, any algorithm A.

**Step 1 — Hard instance family:** Construct 2^K Bernoulli instances where one arm has mean 1/2 + ε and all others have mean 1/2.

**Step 2 — Le Cam / Fano argument:**
$$R_T^* \geq \frac{\varepsilon T}{4} \cdot \exp\left(-\frac{T \cdot \text{KL}(1/2 + \varepsilon, 1/2)}{K}\right)$$

**Step 3 — Optimize ε:** Set ε = √(K log 2 / T) to balance the two factors, giving:
$$R_T \geq \Omega\left(\sqrt{KT}\right)$$

## Instance-Dependent Lower Bound (Lai-Robbins)
For any consistent algorithm (subpolynomial regret on all instances):
$$\liminf_{T \to \infty} \frac{R_T}{\log T} \geq \sum_{i \neq i^*} \frac{\Delta_i}{\text{KL}(\mu_i, \mu^*)}$$

**Proof sketch:** If arm i is pulled o(log T) times on instance ν, there exists instance ν' differing only in arm i where this leads to linear regret. KL-divergence bounds the total variation.

## Key Formula Checklist
- [ ] Identify the hard instance pair (ν, ν') differing in one parameter
- [ ] Compute KL(ν, ν') — use `kl_bernoulli` or `kl_gaussian`
- [ ] Apply Bretagnolle-Huber or Pinsker to bound TV distance
- [ ] Use Fano / Le Cam to get lower bound on error probability
- [ ] Convert error probability to regret via gap Δ
