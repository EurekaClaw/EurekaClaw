---
name: concentration_inequalities
version: "1.0"
tags: [theory, probability, concentration, hoeffding, bernstein, mcdiarmid, tail-bounds, sample-complexity]
agent_roles: [theory]
pipeline_stages: [formalization, lemma_decomposition, proof_attempt]
description: "Apply basic concentration inequalities such as Hoeffding, Bernstein, and McDiarmid to derive tail bounds and sample complexity guarantees."
source: seed
usage_count: 0
success_rate: null
---

# Basic Concentration Inequalities

## When to apply
Use when proving:
- tail bounds for sums or averages of independent bounded random variables
- high-probability sample complexity guarantees
- deviation bounds where variance information matters
- generalization or uniform convergence arguments that need a concentration step
- stability or bounded-differences arguments for functions of independent inputs

## Fast selection guide

### Use Hoeffding when
- the random variables are independent and bounded
- only range information is available
- a clean sub-Gaussian bound is enough
- carrying variance terms would only clutter the argument

### Use Bernstein when
- the random variables are independent, centered, and bounded
- you know or can upper-bound the total variance
- you want a sharper bound in low-variance regimes
- the proof benefits from the interpolation between Gaussian and linear tails

### Use McDiarmid when
- the target is a function of many independent inputs
- changing one coordinate changes the function by at most `c_i`
- direct decomposition into an explicit sum is awkward

## Core statements

### Hoeffding
If `X_1, ..., X_n` are independent and `a_i <= X_i <= b_i` almost surely, then for
`S_n = sum_i (X_i - E[X_i])`,

`P(S_n >= t) <= exp(-2 t^2 / sum_i (b_i - a_i)^2)`.

Two-sided form:

`P(|S_n| >= t) <= 2 exp(-2 t^2 / sum_i (b_i - a_i)^2)`.

For iid `X_i in [a,b]` with empirical mean `\hat\mu = (1/n) sum_i X_i`,

`P(|\hat\mu - E[X_1]| >= eps) <= 2 exp(-2 n eps^2 / (b-a)^2)`.

### Bernstein
If `X_1, ..., X_n` are independent, centered, and satisfy `|X_i| <= M` almost surely, and
`v = sum_i E[X_i^2]`, then

`P(sum_i X_i >= t) <= exp(- t^2 / (2(v + Mt/3)))`.

Two-sided form:

`P(|sum_i X_i| >= t) <= 2 exp(- t^2 / (2(v + Mt/3)))`.

Useful confidence form: with probability at least `1-delta`,

`sum_i X_i <= sqrt(2 v log(1/delta)) + (M/3) log(1/delta)`,

up to the standard one-sided versus two-sided `log(2/delta)` adjustment.

### McDiarmid
If `f(X_1, ..., X_n)` depends on independent inputs and changing only coordinate `i`
can change `f` by at most `c_i`, then

`P(f - E[f] >= t) <= exp(-2 t^2 / sum_i c_i^2)`.

## Standard proof workflow
1. **Identify the random quantity** — write down exactly what needs a high-probability bound.
2. **Center when appropriate** — define `Y_i = X_i - E[X_i]` before applying Bernstein or sum-based Hoeffding.
3. **Record assumptions explicitly** — independence, bounded range, bounded increments, and variance proxy.
4. **Choose the cleanest sufficient inequality** — do not use Bernstein unless the variance term meaningfully helps.
5. **State the bound with constants visible** — avoid hiding the dependence on `delta`, `M`, or `v`.
6. **Convert to the desired form** — solve for `n`, `eps`, or `delta`.
7. **Check scaling** — verify the rate is dimensionally consistent and matches the expected `1/sqrt(n)` or variance-sensitive behavior.

## Common derivation templates

### Bounded sample mean
For iid `X_i in [0,1]`,

`P(|\hat\mu - \mu| >= eps) <= 2 exp(-2 n eps^2)`.

So it is enough to take

`n >= (1 / (2 eps^2)) log(2/delta)`

to guarantee `|\hat\mu - \mu| <= eps` with probability at least `1-delta`.

### Variance-sensitive sample mean
If `|X_i - E[X_i]| <= M` and `Var(X_i) <= sigma^2`, then

`P(|\hat\mu - \mu| >= eps) <= 2 exp(- n eps^2 / (2(sigma^2 + M eps/3)))`.

This is often better than Hoeffding when `sigma^2 << M^2`.

### Uniform convergence step
For a finite class `H`, combine a per-hypothesis tail bound with a union bound:
- apply Hoeffding or Bernstein to each fixed `h`
- multiply by `|H|` or add `log |H|` in the exponent
- solve the resulting inequality for the desired confidence level

## Pitfalls to avoid
- **Missing independence**: Hoeffding and Bernstein are not automatic under dependence.
- **Forgetting centering**: standard Bernstein is for centered variables.
- **Mixing up sum and mean**: keep track of whether the bound is for `sum_i X_i` or `(1/n) sum_i X_i`.
- **Dropping the two-sided factor**: remember the leading `2` when bounding absolute deviation.
- **Ignoring the variance proxy**: Bernstein only helps if the variance term is actually controlled.
- **Overcomplicating simple arguments**: prefer Hoeffding when range-only information suffices.

## Writing guidance
When using this skill in a proof:
- define the centered variables explicitly
- state the exact theorem being invoked
- show the substitution into the theorem parameters
- keep the confidence parameter visible until the final line
- if using a union bound, write it as a separate step rather than burying it
