---
name: underdamped_langevin_convergence
version: "1.0"
tags: [theory, sampling, langevin, underdamped-langevin, kinetic-langevin, hamiltonian, hypocoercivity, wasserstein, kl-divergence, log-concave]
agent_roles: [theory]
pipeline_stages: [formalization, lemma_decomposition, proof_attempt]
description: "Analyze convergence of underdamped Langevin diffusion and its discretizations using the Section 4 perspective from Sinho Chewi's log-concave sampling notes."
source: seed
usage_count: 0
success_rate: null
---

# Underdamped Langevin Convergence Analysis

## Primary source

This skill is based on the Section 4 convergence-analysis viewpoint in Sinho Chewi's notes:
[Log-Concave Sampling](https://chewisinho.github.io/main.pdf)

Use it as the default guide for:
- separating continuous-time mixing from discretization error
- choosing the right metric for convergence
- organizing proofs through coupling, interpolation, or Lyapunov-style arguments

This skill adapts that Section 4 style to the **underdamped / kinetic Langevin** setting.

## When to apply

Use when proving:
- convergence of underdamped Langevin diffusion to its invariant measure
- nonasymptotic convergence of kinetic Langevin discretizations
- acceleration-style improvements over overdamped Langevin
- Wasserstein, KL, or Lyapunov convergence for position-velocity dynamics
- sampling complexity for strongly log-concave targets using momentum

This skill is for **underdamped Langevin**, not overdamped Langevin, HMC, or pure deterministic Hamiltonian flow.

## Standard setup

Let the target on position space be

`pi(dx) propto exp(-V(x)) dx`

on `R^d`, with `V` typically `m`-strongly convex and `L`-smooth.

The underdamped Langevin diffusion augments position with velocity:

`dX_t = V_t dt`

`dV_t = - gamma V_t dt - nabla V(X_t) dt + sqrt(2 gamma) dB_t`

where `gamma > 0` is the friction parameter.

The invariant law on phase space is

`mu(dx, dv) propto exp(-V(x) - |v|^2 / 2) dx dv`.

The position marginal of `mu` is the desired target `pi`.

## Main structural difference from overdamped Langevin

Underdamped Langevin is **not directly contractive in the naive Euclidean metric** the same way overdamped Langevin often is.

The proof must account for:
- Hamiltonian transport in position-velocity space
- friction acting only on velocity
- noise injected only in the velocity coordinate
- transfer of dissipation from velocity to position

So the right keyword is usually:

- **hypocoercivity**

rather than plain coercivity.

## Master decomposition

The high-level strategy is still the same as in Section 4:

1. analyze the **continuous diffusion**
2. compare the **discretized chain** to the diffusion
3. combine mixing plus discretization

So the proof should still look like

`distance(Law(Z_k), mu) <= distance(Law(Z_k), Law(Z_{kh}^{cont})) + distance(Law(Z_{kh}^{cont}), mu)`

where `Z_t = (X_t, V_t)`.

The second term is the continuous-time mixing term.
The first term is the discretization term.

## Canonical proof routes

### 1. Phase-space coupling

Use this route when:
- the theorem is in Wasserstein distance
- the target is strongly log-concave
- you want a geometric contraction proof in phase space

Core idea:
- couple two underdamped diffusions with shared Brownian noise
- work in a modified quadratic metric on `(x, v)`
- use strong convexity plus friction to prove contraction in that metric

This is the most natural analogue of synchronous coupling for the kinetic setting, but the metric usually must mix position and velocity.

### 2. Hypocoercive Lyapunov method

Use this route when:
- the proof should explain why velocity dissipation implies full convergence
- the result is naturally written through a weighted energy or Lyapunov functional
- you want a robust continuous-time convergence proof

Core idea:
- define a modified energy or quadratic form in `(x, v)`
- differentiate it along the dynamics
- exploit cross terms between position and velocity
- prove exponential decay despite the noise acting only on velocity

This is the default conceptual route for underdamped convergence.

### 3. Interpolation / discretization bridge

Use this route when:
- the main challenge is comparing a discrete kinetic integrator to the continuous SDE
- you want a nonasymptotic bound for step-size bias
- the chain is defined by splitting or Euler-type updates

Core idea:
- build a continuous interpolation of the discretized process
- compare its drift and diffusion terms to the exact kinetic Langevin diffusion
- integrate the mismatch over time

This is the right route when the theorem is really about the algorithm, not just the diffusion.

### 4. Relative-entropy / KL route

Use this route when:
- the target statement is in KL divergence or entropy
- the proof uses Fokker-Planck structure
- the result is later converted to TV or Wasserstein

Core idea:
- study the evolution of relative entropy to the invariant law `mu`
- use a modified entropy / Fisher information functional suitable for hypocoercive dynamics
- combine transport and friction to obtain exponential decay

This route is subtler than in the overdamped case because plain entropy dissipation is not the full story.

## What to preserve in every proof

The key structural statement is:

- continuous underdamped Langevin mixes exponentially fast under strong convexity
- discretization introduces a bias depending on step size and smoothness
- the final nonasymptotic bound balances these two terms

So after `k` steps with `t = kh`, the theorem shape should be

`error_k <= mixing_term + discretization_term`

with:
- `mixing_term` decaying exponentially in `t`
- `discretization_term` shrinking as `h -> 0`

## Proof workflow

1. **Write the exact phase-space dynamics.**
   State the SDE in `(X_t, V_t)` and the invariant law `mu`.

2. **Record the assumptions.**
   Usually:
   - `m`-strong convexity of `V`
   - `L`-Lipschitz gradient
   - friction `gamma`
   - dimension `d`
   - step size `h` for the discretization

3. **Choose the metric or functional.**
   Decide whether the result is in:
   - Wasserstein distance on phase space
   - KL divergence
   - a Lyapunov / energy functional
   - a position-marginal metric derived from one of the above

4. **Use a modified geometry.**
   Avoid plain Euclidean contraction unless the theorem explicitly justifies it.
   Most correct proofs use:
   - a weighted quadratic form
   - a mixed `x-v` norm
   - or a hypocoercive entropy functional

5. **Separate mixing and discretization.**
   Keep the diffusion analysis and algorithmic bias analysis distinct.

6. **Optimize time horizon and step size.**
   Balance exponential decay against discretization bias to get the final complexity.

## Typical lemmas to look for

Expect some version of:
- exponential contraction of the continuous kinetic diffusion in a modified metric
- equivalence between the modified metric and Euclidean / Wasserstein control
- one-step local truncation bound for the discretization
- stability of the discretized update in phase space
- conversion from phase-space control to position-marginal control

## Common mistakes to avoid

- **Using overdamped intuition too literally**: underdamped Langevin is not just overdamped Langevin plus momentum.
- **Ignoring velocity**: convergence happens in phase space first; position-only statements usually come later.
- **Using the wrong metric**: naive Euclidean contraction often fails; use a modified metric or hypocoercive functional.
- **Forgetting friction dependence**: `gamma` is a core parameter, not a cosmetic one.
- **Blurring mixing and discretization**: keep the continuous-time theorem separate from the integrator error.
- **Claiming acceleration without assumptions**: faster behavior relies on the right strong-convexity and smoothness regime.

## Response template

When using this skill, structure the proof or explanation as:

1. **Target**: diffusion convergence, algorithmic convergence, or complexity bound.
2. **Dynamics**: exact underdamped Langevin SDE and invariant law.
3. **Assumptions**: `m`, `L`, `gamma`, `d`, initialization, step size.
4. **Route**: phase-space coupling, hypocoercive Lyapunov method, interpolation, or KL route.
5. **Decomposition**: mixing term plus discretization term.
6. **Conclusion**: explicit dependence on `m`, `L`, `gamma`, `d`, `h`, and the target tolerance.

## Safe defaults

If the user does not specify a proof method:
- for conceptual continuous-time convergence, default to the **hypocoercive Lyapunov route**
- for Wasserstein convergence, default to a **modified phase-space coupling**
- for discretized algorithm analysis, default to the **interpolation / discretization bridge**
- for entropy-based statements, default to the **relative-entropy route**
