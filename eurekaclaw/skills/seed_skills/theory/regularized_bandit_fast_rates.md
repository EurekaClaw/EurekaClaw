---
name: regularized_bandit_fast_rates
version: "1.0"
tags: [theory, bandits, contextual-bandits, offline-learning, online-learning, kl-regularization, f-divergence, fast-rates, sample-complexity, regret, rlhf]
agent_roles: [theory]
pipeline_stages: [formalization, lemma_decomposition, proof_attempt]
description: "Use regularized objectives in contextual bandits and RL to prove fast statistical rates, especially O(1/eps) offline sample complexity and logarithmic online regret under KL or f-divergence regularization."
source: seed
usage_count: 0
success_rate: null
---

# Fast Rates from Regularized Objectives in Bandits and RL

## When to apply
Use this skill when the proof target involves:
- KL-regularized or more general `f`-divergence-regularized contextual bandits
- offline policy learning evaluated against a regularized objective rather than raw reward
- online regret for KL-regularized contextual bandits or MDPs
- RLHF-style objectives with a reference policy and Gibbs / Boltzmann policy form
- claims that regularization yields faster rates than the usual `1 / eps^2` or `sqrt(T)` behavior

This skill is specifically about proving improved rates **because the objective is regularized**.
Do not use it if the objective is still plain reward maximization.

## Core papers behind this skill

This skill is based on the following papers:
- [Sharp Analysis for KL-Regularized Contextual Bandits and RLHF](https://arxiv.org/pdf/2411.04625)
- [Towards a Sharp Analysis of Offline Policy Learning for f-Divergence-Regularized Contextual Bandits](https://arxiv.org/pdf/2502.06051)
- [Logarithmic Regret for Online KL-Regularized Reinforcement Learning](https://arxiv.org/pdf/2502.07460)

## Main message

The key insight in all three papers is:

- once performance is measured by a **regularized objective**, the geometry changes
- the objective acquires curvature or a self-bounding structure
- this lets the statistical or online error scale with the objective gap itself
- therefore one can obtain **fast rates**, such as `O(1 / eps)` offline sample complexity or `O(log T)` online regret

This is different from the standard unregularized analysis, where the same problems often yield only:
- `O(1 / eps^2)` sample complexity
- `O(sqrt(T))` regret

## Canonical objective forms

### Reverse-KL regularized contextual bandits
The standard objective is

`J(pi) = E[r(x,a)] - eta^{-1} KL(pi || pi_ref)`.

The optimizer has Gibbs form:

`pi_R^eta(a|x) propto pi_ref(a|x) exp(eta R(x,a))`.

This closed form is central to all three papers.

### General f-divergence regularization
The offline paper studies contextual bandits with objective

`J_f(pi) = E[r(x,a)] - eta^{-1} D_f(pi || pi_ref)`.

The sharp rate depends on the curvature of `f`:
- reverse KL is important but not strongly convex in the relevant parametrization
- strongly convex `f` yields even cleaner fast-rate behavior

## Paper-specific takeaways

### 1. Zhao-Ye-Gu-Zhang (2024/2025): online KL-regularized contextual bandits and RLHF

Use this paper when the setting is **online** and the target is sample complexity or fast learning under good reference-policy coverage.

Key takeaways:
- KL-regularized contextual bandits can achieve `O(1 / eps)` sample complexity
- the algorithm uses a **two-stage mixed sampling** strategy
- the dependence on coverage is additive through a coverage coefficient, rather than destroying the fast rate
- the proof uses a fine-grained decomposition of the regularized suboptimality gap instead of reducing everything to a standard bandit objective

This is the right paper when the user wants:
- online fast rates
- RLHF-style contextual bandits
- a reference policy with good coverage
- a proof that online data helps even without explicit exploration-heavy machinery

### 2. Zhao-Ji-Zhao-Zhang-Gu (2025/2026): offline f-divergence-regularized contextual bandits

Use this paper when the setting is **offline** and the objective itself is regularized.

Key takeaways:
- for reverse KL, they get `O(1 / eps)` sample complexity under **single-policy concentrability**
- they show this dependence is essentially sharp via a near-matching lower bound
- the proof is **pessimism-based**
- for strongly convex `f`, they show the sharp `Theta(eta / eps)`-type fast rate without needing pessimism or single-policy concentrability

This is the right paper when the user asks:
- what is the weakest coverage condition for regularized offline learning?
- why reverse KL still needs coverage while strongly convex `f` may not?
- how pessimism interacts with curvature in offline regularized learning?

### 3. Zhao-Ye-Xiong-Gu-Zhang (2025/2026): logarithmic regret for online KL-regularized RL

Use this paper when the target is **online regret** in contextual bandits or MDPs.

Key takeaways:
- KL-regularized contextual bandits admit `O(log T)` regret
- KL-regularized MDPs also admit logarithmic regret
- the analysis does not just upper bound reward-estimation error in the standard way
- instead it rewrites the regularized suboptimality as a gap involving the normalization term `Z_R`
- then it studies the shape and derivative of a function gap `Delta(x, R)`
- optimism plus this refined decomposition makes the uncertainty summable, leading to logarithmic regret

This is the right paper when the user wants:
- a regret result instead of pure sample complexity
- a proof that KL regularization fundamentally changes online efficiency
- a bridge from contextual bandits to KL-regularized MDPs

## Decision guide

### Use reverse KL when
- the objective is exactly `reward - eta^{-1} KL(pi || pi_ref)`
- the optimizer should have a Gibbs / Boltzmann closed form
- you want the standard RLHF-aligned objective
- you are proving fast rates specifically tied to the normalization term or log-partition structure

### Use strongly convex f-divergence when
- the paper or conjecture concerns a more general regularizer
- you want cleaner curvature-based fast-rate arguments
- you want to explain why coverage assumptions can disappear in offline learning

### Use online-gap decomposition when
- the quantity of interest is regret over time
- the proof must exploit the regularized objective directly
- the standard optimism or UCB analysis seems too loose

### Use pessimism when
- the setting is offline
- reverse KL is the regularizer
- the analysis must exploit single-policy concentrability sharply

## Standard proof workflow

1. **Write the exact regularized objective.**
   Do not say “bandit objective” loosely. Show the reward term and the divergence term.

2. **Record the closed-form optimizer or policy map.**
   For KL, use the Gibbs policy induced by a reward proxy `R`.

3. **Choose the regime.**
   Separate clearly:
   - online vs offline
   - reverse KL vs general strongly convex `f`
   - sample complexity vs regret

4. **Use a regularized gap decomposition.**
   Avoid reducing immediately to plain reward estimation.
   The whole point is that the regularizer changes the local geometry.

5. **Exploit curvature / self-bounding structure.**
   Fast rates arise because the suboptimality gap can be controlled more sharply than in unregularized learning.

6. **Insert the right uncertainty control.**
   Depending on the paper, this may be:
   - pessimistic reward estimation
   - two-stage mixed-policy sampling
   - optimistic confidence bonuses
   - an eluder-dimension-based width bound

7. **Close the rate in the correct metric.**
   Be explicit whether the result is:
   - `O(1 / eps)` sample complexity for regularized suboptimality
   - `O(log T)` regret under the regularized objective
   - or only a conversion to sample complexity through regret-to-gap arguments

## The most important proof habit

Never replace the regularized objective by a plain reward objective too early.

That is exactly where earlier analyses lose the fast rate.
In these papers, the improved rates come from:
- preserving the log-partition / normalization structure for KL
- preserving curvature in the divergence term
- analyzing the regularized gap itself, not only the reward estimation error

## Useful recurring objects

### Gibbs policy
For KL regularization and reward proxy `R`,

`pi_R^eta(a|x) propto pi_ref(a|x) exp(eta R(x,a))`.

### Normalization / partition function
Define

`Z_R(x) = E_{a ~ pi_ref(.|x)}[exp(eta R(x,a))]`.

This object is central in the logarithmic-regret analysis and often should remain explicit.

### Function gap
In the online KL paper, the suboptimality is analyzed through a function such as

`Delta(x, R)`

built from:
- a negative log-normalization term
- plus an expectation under the Gibbs policy induced by `R`

When trying to reproduce that style of proof, keep `Delta` symbolic until the derivative argument is complete.

## Common mistakes to avoid

- **Collapsing to unregularized analysis**: this usually loses the fast rate and gives only `1 / eps^2` or `sqrt(T)`.
- **Ignoring the reference policy**: coverage and Gibbs normalization depend on `pi_ref`.
- **Mixing offline and online arguments**: pessimism and mixed sampling play different roles in the offline and online papers.
- **Confusing reward optimality with regularized optimality**: the guarantees are often with respect to the regularized objective.
- **Assuming all f-divergences behave like reverse KL**: the strongly convex `f` case is materially different.
- **Forgetting the coverage regime**: reverse-KL offline fast rates still depend on the right concentrability notion.

## Response template

When using this skill in a proof or explanation, structure the answer as:

1. **Objective**: write the exact regularized objective.
2. **Regime**: online/offline and KL/general `f`.
3. **Geometry**: what curvature or normalization structure is being exploited.
4. **Estimator or policy construction**: pessimism, mixed sampling, or optimism.
5. **Complexity statement**: `O(1 / eps)`, `Theta(1 / eps)`, or `O(log T)` as appropriate.
6. **Assumptions**: coverage, single-policy concentrability, strong convexity, metric entropy, or eluder dimension.

## Safe defaults

If the user cites:
- `2411.04625`, default to online KL-regularized contextual bandits / RLHF and two-stage mixed sampling.
- `2502.06051`, default to offline `f`-divergence-regularized contextual bandits, pessimism for reverse KL, and strong-convexity-based fast rates.
- `2502.07460`, default to logarithmic online regret and the normalization-term / function-gap decomposition.

If the user says “fast rate from regularization” without more detail:
- first ask whether they mean offline sample complexity or online regret
- then ask whether the regularizer is reverse KL or a more general strongly convex `f`
- if they do not specify, start from reverse-KL contextual bandits because that is the common core across the papers
