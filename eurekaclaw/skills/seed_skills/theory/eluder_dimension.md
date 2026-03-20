---
name: eluder_dimension
version: "1.0"
tags: [theory, bandits, reinforcement-learning, online-learning, eluder-dimension, generalized-eluder-dimension, generalized-eluder-coefficient, function-class]
agent_roles: [theory]
pipeline_stages: [formalization, lemma_decomposition, proof_attempt]
description: "Reason about Eluder dimension, generalized Eluder dimension, and generalized Eluder-type coefficients in sequential learning and bandit proofs."
source: seed
usage_count: 0
success_rate: null
---

# Eluder Dimension and Generalized Eluder Geometry

## When to apply
Use when proving:
- regret bounds for bandits, contextual bandits, or model-based RL that depend on sequential uncertainty
- identifiability or exploration complexity statements for nonlinear function classes
- bounds stated in terms of Eluder dimension, generalized Eluder dimension, or an Eluder-type coefficient
- width-summation lemmas controlling the number of large-uncertainty rounds
- comparisons between complexity notions such as VC dimension, covering numbers, Bellman-Eluder quantities, and sequential disagreement measures

## First rule: lock the definition before doing any proof

The phrase **generalized Eluder dimension** or **generalized Eluder coefficient** is not fully standardized across the literature.
Before using the notion, explicitly record:
- the underlying function class or model class
- the prediction domain and action/context domain
- the notion of dependence or independence being used
- whether the parameter is exact, `eps`-dependent, scale-dependent, or distribution-dependent
- whether the quantity is a dimension, a coefficient, a width sum, or a complexity radius

If the user cites a paper, use that paper's exact definition. Do not silently substitute a nearby variant.

## Baseline intuition

Eluder-style quantities measure **sequential identifiability**:
- how long one can keep querying points whose values are not already determined by previous observations
- how many rounds of genuinely new information a learner may face
- how uncertainty propagates through a function class under adaptive data collection

This is different from ordinary covering-number or VC-style complexity:
- covering numbers measure global approximation richness
- Eluder-style quantities measure adaptive dependence structure

## NeurIPS 2024 reference point

This skill should explicitly accommodate the NeurIPS 2024 paper
*A Nearly Optimal and Low-Switching Algorithm for Reinforcement Learning with General Function Approximation* by Zhao, He, and Gu.

That paper uses the **Agarwal et al. (2022) generalized Eluder dimension** and then proves a connection back to the classical Russo-Van Roy Eluder dimension.

Use that paper for the following two points:
- the concrete weighted definition of generalized Eluder dimension via `D_F^2`
- the claim that this generalized quantity is upper bounded by classical Eluder dimension up to logarithmic factors

Source:
[NeurIPS 2024 paper](https://proceedings.neurips.cc/paper_files/paper/2024/file/ac3cea0be817ebac21299b77fd114ddf-Paper-Conference.pdf)

## Canonical Eluder dimension template

For a function class `F` over a domain `X`, the classical Eluder dimension controls the longest sequence
`x_1, ..., x_n` such that each `x_t` remains approximately independent of the previous points under `F`.

The proof pattern is:
1. define what it means for `x` to be dependent on a previous set `S`
2. define `eps`-independence or exact independence
3. show that any long sequence of independent points forces a structural contradiction
4. conclude a finite Eluder dimension bound

## Generalized Eluder dimension in Zhao-He-Gu (NeurIPS 2024)

Use the generalized Eluder dimension exactly as defined in Definition 2.4 of the NeurIPS 2024 paper.

For a function class `F : S x A -> [0, L]`, regularization `lambda >= 0`, a sequence of state-action pairs
`Z = {z_i}_{i in [T]}`, and a sequence of positive weights `sigma = {sigma_i}_{i in [T]}`, define

`dim(F, Z, sigma) = sum_{i=1}^T min(1, D_F^2(z_i; z[1:i-1], sigma[1:i-1]) / sigma_i^2)`.

Here

`D_F^2(z; z[1:t-1], sigma[1:t-1])`

is defined by

`sup_{f_1, f_2 in F} (f_1(z) - f_2(z))^2 / (sum_{s in [t-1]} (f_1(z_s) - f_2(z_s))^2 / sigma_s^2 + lambda)`.

Then the generalized Eluder dimension at scale `alpha` and horizon `T` is

`dim_{alpha,T}(F) = sup_{Z, sigma : |Z| = T, sigma >= alpha} dim(F, Z, sigma)`.

In the stage-wise RL setting where `F = {F_h}_{h in [H]}`, the paper writes

`dim_{alpha,T}(F) = H^{-1} sum_{h in [H]} dim_{alpha,T}(F_h)`.

This is the default meaning of **generalized Eluder dimension** for this skill.
It is a weighted cumulative uncertainty quantity built from `D_F^2`, not a longest independent-sequence definition.

## How to interpret this definition

- `D_F^2` measures how uncertain the value at a new point `z` can remain after controlling weighted discrepancies on previous points.
- The truncation `min(1, ...)` turns this into a per-round contribution capped at `1`.
- Summing these contributions gives a cumulative complexity of adaptive uncertainty.
- Taking the supremum over all admissible sequences and weights yields the generalized Eluder dimension.

When using this notion in proofs, preserve the weights `sigma_i`, the regularization `lambda`, and the truncation.
Do not replace it by an informal independence story unless you explicitly say you are giving only intuition.

## Generalized Eluder coefficient template

In many papers, a generalized Eluder coefficient is not a pure combinatorial dimension but a bound on how often large uncertainty can occur.
Typical forms include:
- a coefficient controlling a cumulative width sum
- a coefficient appearing in an elliptical-potential-style bound
- a scale-sensitive parameter that upper-bounds the number of `eps`-independent rounds

When using such a coefficient, make the statement operational:
- what sequence is being summed over
- what width, bonus, or disagreement quantity is being controlled
- what thresholding or scale parameter is present
- whether the conclusion is linear, logarithmic, or square-root in time

If the paper defines a coefficient `C_F`, `kappa_F`, or similar, keep that notation and copy the exact dependence statement before manipulating it.

### Important terminology note

The NeurIPS 2024 paper above does **not** introduce a separate object literally called a “generalized Eluder coefficient.”
Instead, it works with:
- the weighted uncertainty quantity `D_F^2`
- the generalized Eluder dimension built from the cumulative sum of truncated weighted uncertainties

So if the user asks about a “generalized Eluder coefficient” while citing that paper, do not invent a new paper-specific coefficient.
The safe move is:
- explain the paper's actual `D_F^2` and generalized Eluder dimension
- say that any “coefficient” language should be interpreted as a coefficient-like cumulative uncertainty control only if the user is using broader informal terminology

## Key result from Zhao-He-Gu (NeurIPS 2024)

The paper proves a connection between generalized Eluder dimension and classical Eluder dimension.
In its Appendix B/C, it states that for bounded function classes and weights `alpha <= sigma_i <= M`,
the cumulative generalized Eluder quantity

`sum_i min(1, D_G^2(z_i; z[1:i-1], sigma[1:i-1]) / sigma_i^2)`

is upper bounded by classical Eluder dimension at scale about `1 / sqrt(T)`, up to logarithmic factors and a `lambda^{-1}` term.

The proof implication to remember is:
- generalized weighted uncertainty can be controlled by classical Eluder dimension, modulo logs
- therefore regret bounds written with generalized Eluder dimension can often be reinterpreted in terms of standard Eluder dimension up to logarithmic loss

When discussing this result, be careful not to overstate it as equality or exact equivalence.
It is an **upper-bound relation up to log factors**, not an identity.

## Standard proof workflow
1. **Specify the class** — linear predictors, generalized linear models, Q-functions, model classes, or Bellman residual classes.
2. **Define dependence** — exact or approximate dependence on a history/set.
3. **Choose the scale** — many useful notions are really `eps`-Eluder quantities.
4. **Translate the learning argument** — convert optimism/posterior width/regret terms into a width or disagreement sum.
5. **Apply the Eluder-type complexity bound** — dimension bound, coefficient bound, or independence-counting lemma.
6. **Close the regret or sample complexity argument** — usually by combining with concentration and a confidence set argument.

## Common proof patterns

### Linear class
For linear predictors `f_theta(x) = <theta, phi(x)>` with bounded parameter and feature norms, the Eluder dimension is typically controlled by the ambient dimension up to logarithmic or scale factors.

Use this pattern:
- map dependence to near-linear dependence of feature vectors
- reduce approximate independence to a rank or determinant-growth argument
- conclude a dimension bound of order `d` or `d log(1/eps)` depending on the exact definition

### Width-sum lemma
Many regret proofs need:
- define a confidence width `w_t(x_t)`
- show only finitely many rounds can have `w_t(x_t)` above a threshold
- or sum `min(1, w_t(x_t))` / `min(1, w_t(x_t)^2)`

Eluder-style quantities enter exactly here: they turn adaptive uncertainty into a counting statement.

### Weighted uncertainty route in general RL
When following the NeurIPS 2024 paper:
- define the bonus or confidence width through an oracle approximating `D_F^2`
- convert regret or switching-cost analysis into sums of truncated weighted uncertainties
- bound those sums by the generalized Eluder dimension
- then, if needed, appeal to the Appendix B/C comparison theorem to replace generalized Eluder complexity by classical Eluder complexity up to logarithmic factors

### Generalized RL setting
In RL or model-based settings:
- the queried object may be a state-action pair, rollout, or Bellman update target
- the dependence notion may involve Bellman error, model prediction error, or value disagreement
- the generalized Eluder parameter often controls how quickly the learner can eliminate optimistic hypotheses

State clearly whether the complexity is attached to:
- reward models
- transition models
- Q-function classes
- Bellman-complete residual classes

## Writing guidance

When writing a proof:
- define the exact independence relation before citing any Eluder quantity
- keep the scale parameter visible if the notion is `eps`-dependent
- distinguish clearly between “dimension” and “coefficient”
- if using a theorem from a paper, reproduce the theorem assumptions before using its conclusion
- say whether the quantity is combinatorial, geometric, or cumulative

When explaining intuition:
- say “Eluder complexity measures how many adaptively chosen queries can remain genuinely informative”
- contrast it with covering-number complexity, which is global rather than sequential

## Common mistakes to avoid
- **Undefined dependence notion**: using “Eluder dimension” without defining what dependence means in the current setting.
- **Mixing variants**: importing a Bellman-Eluder or generalized coefficient theorem but reasoning as if it were the classical function-value definition.
- **Forgetting the scale**: many results are `eps`-dependent; dropping `eps` changes the statement.
- **Confusing dimension and coefficient**: one is often a maximal sequence length, the other may be a cumulative-width control parameter.
- **Skipping the confidence-set bridge**: Eluder quantities rarely appear alone; they usually work together with concentration and optimism/posterior arguments.
- **Misreading Zhao-He-Gu (2024)**: that paper gives a weighted generalized Eluder dimension and an upper-bound comparison to classical Eluder dimension, not a standalone generalized Eluder coefficient definition.

## Response template

When the user asks about one of these notions, structure the answer as:

1. **Object**: what function/model class is under study.
2. **Definition choice**: exact paper-specific definition of dependence, generalized dimension, or coefficient.
3. **Interpretation**: what kind of adaptive uncertainty it measures.
4. **Key lemma**: independence-counting lemma, width-sum lemma, or theorem being invoked.
5. **Consequence**: how it enters regret, sample complexity, or exploration guarantees.

## If the user does not specify a paper

Default to the following safe behavior:
- explain the classical Eluder dimension first
- state that generalized variants are paper-specific
- ask which generalized definition or theorem family they want
- if proceeding without a citation, write a local definition explicitly and reason only from that definition

If the user cites the NeurIPS 2024 paper by Zhao-He-Gu, default to:
- Definition 2.4 for generalized Eluder dimension
- the `D_F^2` weighted uncertainty interpretation
- Theorem B.3 / Appendix C for the comparison to classical Eluder dimension
