---
name: overdamped_langevin_convergence
version: "1.0"
tags: [theory, sampling, langevin, overdamped-langevin, lmc, log-concave, wasserstein, kl-divergence, girsanov, convex-optimization]
agent_roles: [theory]
pipeline_stages: [formalization, lemma_decomposition, proof_attempt]
description: "Analyze convergence of overdamped Langevin diffusion and Langevin Monte Carlo using the Section 4 toolkit from Sinho Chewi's log-concave sampling notes."
source: seed
usage_count: 0
success_rate: null
---

# Overdamped Langevin Convergence Analysis

## Primary source

This skill is based on Section 4, “Analysis of Langevin Monte Carlo,” of Sinho Chewi's notes:
[Log-Concave Sampling](https://chewisinho.github.io/main.pdf)

Use this source as the default reference for:
- the standard overdamped Langevin setup
- the relationship between the diffusion and its Euler discretization
- the four canonical proof styles in Section 4

## When to apply

Use when proving:
- convergence of the overdamped Langevin diffusion to `pi propto exp(-V)`
- nonasymptotic convergence of Langevin Monte Carlo (LMC / ULA)
- discretization error bounds between LMC and the continuous Langevin diffusion
- Wasserstein or KL guarantees for log-concave sampling
- oracle complexity statements for sampling from a smooth strongly log-concave target

This skill is for the **overdamped** Langevin process, not HMC or underdamped Langevin.

## Standard setup

Assume the target density is

`pi(dx) propto exp(-V(x)) dx`

on `R^d`.

The overdamped Langevin diffusion is

`dX_t = - nabla V(X_t) dt + sqrt(2) dB_t`.

Its Euler discretization with step size `h` is Langevin Monte Carlo:

`X_{k+1} = X_k - h nabla V(X_k) + sqrt(2h) xi_k`,

where `xi_k` are iid standard Gaussians.

The usual assumptions in Section 4 are:
- `V` is `m`-strongly convex
- `nabla V` is `L`-Lipschitz
- sometimes the initialization is deterministic or Gaussian-like

Under these assumptions, the diffusion contracts exponentially, and LMC inherits convergence up to a discretization bias.

## The master decomposition

The cleanest high-level proof strategy is:

1. analyze convergence of the **continuous diffusion** to `pi`
2. compare the **discrete chain** to the diffusion over finite time
3. combine contraction plus discretization error

So most proofs have the form

`distance(Law(X_k), pi) <= distance(Law(X_k), Law(X_{kh}^{cont})) + distance(Law(X_{kh}^{cont}), pi)`.

The second term is the mixing term.
The first term is the discretization term.

## Four proof routes from Section 4

### 1. Wasserstein coupling

Use this route when:
- the target is strongly log-concave
- you want an intuitive contraction proof
- the desired metric is `W_2` or another Wasserstein distance

Core idea:
- drive two Langevin diffusions by the same Brownian motion
- use strong convexity to show synchronous coupling contracts
- bound the Euler discretization error by comparing the chain with the diffusion over one step

This is the most geometric and often the cleanest route for `W_2` bounds.

### 2. Interpolation argument

Use this route when:
- you want a more analytic proof of the discretization error
- you need a bridge between discrete time and continuous time
- you are controlling a divergence through a time interpolation of the chain

Core idea:
- define a continuous-time interpolation of LMC
- differentiate a suitable functional along the interpolation
- integrate the derivative bound over time

This route is especially useful when the proof should look like a stability argument rather than a direct coupling argument.

### 3. Convex optimization viewpoint

Use this route when:
- the audience or theorem is optimization-oriented
- you want to stress the analogy between sampling and gradient descent
- the convergence statement is expressed via KL, free energy, or Lyapunov decrease

Core idea:
- view the Langevin diffusion as gradient flow of the relative entropy in Wasserstein space
- interpret LMC as an inexact discretization of this descent
- use convexity of `V` and functional inequalities to derive convergence

This route is particularly good when connecting sampling proofs to optimization concepts such as smoothness, strong convexity, descent lemmas, and discretization stability.

### 4. Girsanov's theorem

Use this route when:
- the target metric is KL divergence
- you want a sharp comparison between interpolated LMC and the true diffusion
- the proof naturally proceeds through change of measure on path space

Core idea:
- construct an interpolated process whose drift is piecewise frozen
- compare its path law with the true Langevin path law using Girsanov
- upper-bound the terminal KL by path-space KL via data processing
- estimate the drift mismatch using Lipschitzness of `nabla V`

This route is often the cleanest for KL bounds and later total variation or Renyi consequences.

## What each route is good for

- **Wasserstein coupling**: best default for geometric contraction and `W_2`.
- **Interpolation**: best when proving discretization error through a continuous bridge.
- **Convex optimization**: best when the theorem should emphasize entropy dissipation or optimization structure.
- **Girsanov**: best when the proof target is KL or another information divergence.

## Canonical theorem shape

Under `m`-strong convexity and `L`-smoothness, the standard nonasymptotic LMC result has the form:

- exponential decay of the continuous-time error, roughly `exp(-m t)`
- plus a discretization term depending on `h`, `L`, `d`, and time horizon

So after `k` steps with `t = kh`, one gets

`error_k <= mixing_term + discretization_term`

with:
- `mixing_term` decreasing exponentially in `kh`
- `discretization_term` going to zero as `h -> 0`

This is the main structural fact to preserve in every proof.

## Proof workflow

1. **State the target measure and assumptions.**
   Write exactly: strong convexity parameter `m`, smoothness parameter `L`, dimension `d`, step size `h`.

2. **Choose the metric.**
   Decide up front whether the target statement is in:
   - `W_2`
   - KL divergence
   - total variation via Pinsker
   - a converted complexity guarantee

3. **Separate mixing and discretization.**
   Do not blur these two terms together.

4. **Pick the proof route.**
   - `W_2` -> coupling
   - KL -> Girsanov
   - optimization language -> convex optimization route
   - bridge argument -> interpolation

5. **Track constants by `m`, `L`, `d`, and `h`.**
   Most mistakes come from losing one of these parameters.

6. **Optimize the time horizon / number of steps.**
   Balance exponential mixing against discretization bias to get the final complexity.

## Typical lemmas to look for

When writing or checking a proof, expect some version of:
- contraction of the continuous diffusion under strong convexity
- one-step local truncation bound for Euler discretization
- control of the interpolation drift mismatch
- path-space KL formula from Girsanov
- conversion from KL to TV or Wasserstein if needed

## Common mistakes to avoid

- **Mixing diffusion and chain notation**: keep continuous-time and discrete-time processes separate.
- **Forgetting the bias floor**: LMC does not exactly track the target for fixed `h`; there is a discretization error.
- **Using the wrong metric conversion**: KL, TV, and Wasserstein require different comparison tools.
- **Ignoring strong convexity**: the clean exponential contraction statements in Section 4 rely on it.
- **Hiding the step-size restriction**: if the argument needs small `h`, state it explicitly.
- **Treating Girsanov as terminal-time change of measure**: it is fundamentally a path-space argument first.

## Response template

When using this skill, structure the proof or explanation as:

1. **Target**: diffusion convergence, LMC convergence, or complexity bound.
2. **Assumptions**: `m`-strong convexity, `L`-smoothness, initialization, and step size.
3. **Metric**: `W_2`, KL, TV, or another divergence.
4. **Route**: coupling, interpolation, convex optimization, or Girsanov.
5. **Decomposition**: mixing term plus discretization term.
6. **Conclusion**: explicit dependence on `m`, `L`, `d`, `h`, and the target error tolerance.

## Safe defaults

If the user does not specify a method:
- for Wasserstein convergence, default to **synchronous coupling**
- for KL convergence, default to **Girsanov's theorem**
- for conceptual exposition, default to the **convex optimization viewpoint**
- for proving LMC error from the chain to the diffusion, default to the **interpolation argument**
