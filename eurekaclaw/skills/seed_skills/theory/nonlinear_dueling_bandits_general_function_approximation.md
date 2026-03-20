---
name: nonlinear_dueling_bandits_general_function_approximation
version: "1.0"
tags: [theory, bandits, dueling-bandits, contextual-bandits, nonlinear-function-approximation, bradley-terry, sigmoid-link, regularized-policy-optimization, eluder-dimension, preference-learning]
agent_roles: [theory]
pipeline_stages: [formalization, lemma_decomposition, proof_attempt]
description: "Prove regret and uncertainty bounds for nonlinear contextual dueling bandits under the Bradley-Terry preference model, with general reward classes, regularized policy optimization, and preference-based Eluder dimensions."
source: seed
usage_count: 0
success_rate: null
---

# Proof Skills for Nonlinear Dueling Bandits with General Function Approximation

This skill is a proof-oriented LaTeX template for **nonlinear contextual dueling bandits** under the Bradley--Terry (sigmoid) preference model, with **general reward function classes** and **general regularized policy optimization**.

It is written to be **appendix-ready**. Most blocks below can be adapted directly into a NeurIPS-style paper. The emphasis is on the **key mathematical proofs** needed for papers involving:

- nonlinear / general function approximation
- two-policy dueling feedback
- regularized reward regret
- optimistic competitor selection
- finite-class or finite-covering-number analysis
- generalized preference-based Eluder dimension

## When to apply

Use this skill when the proof target involves:

- contextual dueling bandits with binary preference feedback
- a Bradley--Terry or sigmoid-link preference model
- a realizable reward class `r^* in R`
- regularized policy optimization against a reference policy
- optimism-based competitor selection
- finite-class, covering-number, or Eluder-style regret analysis
- converting preference prediction error into pairwise reward-difference control

This skill is especially useful when the proof needs to explain how a **strong competitor** removes a coverage-ratio or exponential barrier from the leading term.

## First rule: clean up notation before proving anything

The notation must be stabilized first, or the proof will accumulate sign and parameter mistakes.

Recommended conventions:

- use `tau > 0` for the policy regularization coefficient
- use `beta_t` for the confidence radius
- use `Omega_x^r(pi)` for the regularized value
- use `Delta_r(x; pi, pi') := r(x,pi) - r(x,pi')`
- define the two-arm regret in a way that keeps the regularizer signs consistent

Canonical regularized value:

`Omega_x^r(pi) := r(x,pi) - tau D(pi(.|x) || pi_ref(.|x))`

Canonical regret:

`R_t := 2 Omega_{x_t}^{r^*}(pi_*^t) - Omega_{x_t}^{r^*}(pi_1^t) - Omega_{x_t}^{r^*}(pi_2^t)`

## Pasteable LaTeX macros

```latex
\newcommand{\cX}{\mathcal X}
\newcommand{\cA}{\mathcal A}
\newcommand{\cR}{\mathcal R}
\newcommand{\Conf}{\widehat{\mathcal R}}
\newcommand{\Reg}{\mathrm{Reg}}
\newcommand{\Ber}{\mathrm{Ber}}
\newcommand{\KL}{\mathrm{KL}}
\newcommand{\Hell}{\mathrm{H}^2}
\newcommand{\prefdim}{\mathrm{dim}^{\mathrm{pref}}}
\newcommand{\EE}{\mathbb E}
\newcommand{\PP}{\mathbb P}
\newcommand{\ind}{\mathbf 1}
\newcommand{\RR}{\mathbb R}
\newcommand{\argmax}{\mathop{\rm argmax}}
\newcommand{\argmin}{\mathop{\rm argmin}}
\newcommand{\piref}{\pi_{\mathrm{ref}}}
\newcommand{\Del}{\Delta}

\newcommand{\RegVal}[3]{\Omega_{#1}^{#2}\!\left(#3\right)}
\newcommand{\Gap}[4]{\Delta_{#1}\!\left(#2;#3,#4\right)}
```

## Problem setup template

Use the following theorem-ready setup:

```latex
\paragraph{Environment.}
At each round $t\in[T]$, the learner observes a context $x_t\in\cX$, chooses two policies
$\pi_1^t,\pi_2^t\in\Pi$, draws actions
$a_1^t\sim \pi_1^t(\cdot\mid x_t)$ and
$a_2^t\sim \pi_2^t(\cdot\mid x_t)$,
and receives a preference outcome
$o_t\in\{0,1\}$, where $o_t=1$ means $a_1^t \succ a_2^t$.

We assume a realizable reward class $\cR \subseteq \{r:\cX\times\cA\to[-B,B]\}$ and a ground-truth reward
$r^*\in\cR$ such that
\begin{align}
\PP(o_t=1\mid x_t,a_1^t,a_2^t)
= \sigma\bigl(r^*(x_t,a_1^t)-r^*(x_t,a_2^t)\bigr),
\qquad
\sigma(z)=\frac{1}{1+e^{-z}}.
\end{align}

For a policy $\pi$, define
\begin{align}
r(x,\pi):=\EE_{a\sim\pi(\cdot\mid x)}[r(x,a)],
\qquad
\Omega_x^r(\pi)
:= r(x,\pi)-\tau D\bigl(\pi(\cdot\mid x)\|\piref(\cdot\mid x)\bigr).
\end{align}
Let
\begin{align}
\pi_*^t \in \argmax_{\pi\in\Pi} \Omega_{x_t}^{r^*}(\pi).
\end{align}
The two-arm regret is
\begin{align}
\Reg(T):=\sum_{t=1}^T R_t,
\qquad
R_t:=2\Omega_{x_t}^{r^*}(\pi_*^t)-\Omega_{x_t}^{r^*}(\pi_1^t)-\Omega_{x_t}^{r^*}(\pi_2^t).
\end{align}
```

## Confidence-set construction

Use online MLE under the Bradley--Terry model:

```latex
\paragraph{MLE estimator.}
Given the data up to round $t-1$, define the negative log-likelihood
\begin{align}
L_t(r)
:= \sum_{s=1}^{t-1} \ell_s(r),
\qquad
\ell_s(r)
:= - o_s \log p_s(r) - (1-o_s)\log\bigl(1-p_s(r)\bigr),
\end{align}
where
\begin{align}
p_s(r)
:= \sigma\bigl(r(x_s,a_1^s)-r(x_s,a_2^s)\bigr).
\end{align}
Let the MLE be
\begin{align}
r_1^t \in \argmin_{r\in\cR} L_t(r).
\end{align}
Define the confidence set
\begin{align}
\Conf_t := \Bigl\{r\in\cR:
L_t(r)\le L_t(r_1^t)+\beta_t\Bigr\}.
\end{align}
```

For a finite class, a convenient choice is:

`beta_t = 2 log(|R| T / delta)`

## Target policy and optimistic competitor

The target policy:

```latex
\pi_1^t
\in
\argmax_{\pi\in\Pi} \RegVal{x_t}{r_1^t}{\pi}.
```

The competitor objective should make the later regret decomposition transparent:

```latex
\paragraph{Competitor policy.}
For any $r\in\cR$ and $\pi,\pi'\in\Pi$, define
\begin{align}
b_t(r,\pi; r_1^t,\pi')
:= \bigl(r-r_1^t\bigr)(x_t,\pi)-\bigl(r-r_1^t\bigr)(x_t,\pi').
\end{align}
Then choose
\begin{align}
(\pi_2^t,r_2^t)
\in
\argmax_{\pi\in\Pi,\, r\in\Conf_t}
\Bigl\{
\RegVal{x_t}{r_1^t}{\pi}
+2 b_t(r,\pi;r_1^t,\pi_1^t)
\Bigr\}.
\end{align}
```

## Main proof modules

The recommended proof architecture has the following modules.

### 1. Sigmoid mean-value / curvature conversion

Use a mean-value theorem argument to convert differences in sigmoid probabilities into differences in reward gaps.

Key identities:

- `sigma(u) - sigma(v) = m(u,v) (u-v)`
- on `[-2B, 2B]`, `sigma'(z) >= (1/4) e^{-2B}`
- hence `|u-v| <= 4 e^{2B} |sigma(u)-sigma(v)|`
- and `(u-v)^2 <= 16 e^{4B} (sigma(u)-sigma(v))^2`

Use this module whenever you need to connect:
- pairwise preference probabilities
- reward-gap estimation
- local curvature weights

Important message:

- the crude global curvature lower bound introduces an `e^{4B}` factor after squaring
- the whole point of a strong competitor is to make the compared pair locally close enough that the effective curvature is often constant-order

### 2. Hellinger-supermartingale MLE concentration

For finite classes, the cleanest route is a Bernoulli Hellinger supermartingale.

Core lemma:

- uniformly over `r in R` and times `t`,
  `sum_s Hell(Ber(p_s(r^*)), Ber(p_s(r))) <= L_t(r) - L_t(r^*) + 2 log(|R|T/delta)`

Then use:

- `(p-q)^2 <= 2 Hell(Ber(p), Ber(q))`

This produces:

- a confidence-set validity lemma
- squared preference-gap control
- a bridge from likelihood geometry to regret analysis

### 3. Confidence set contains the truth

Always include the simple lemma:

- if `beta_t >= 2 log(|R|T/delta)`, then `r^* in Conf_t` for all `t`

This is what licenses using `r^*` as a feasible comparator in the optimistic competitor argument.

### 4. Competitor-induced regret decomposition

This is the structural heart of the paper.

Under `r^* in Conf_t`, decompose the regret into:

- `I_{1,t}`: target-model error on the sampled duel
- `I_{2,t}`: residual optimism inside the confidence set

The key advantage is:

- both terms depend only on the actual duel `(pi_1^t, pi_2^t)`
- the proof avoids an importance-weighting comparison from `pi_2^t` to the unknown optimal policy `pi_*^t`

This is exactly where the strong competitor removes a coverage-ratio barrier from the leading term.

### 5. Preference-based Eluder dimension

The right uncertainty notion is built on pairwise reward differences, not single-action rewards.

The duel reveals information about:

`r(x,a) - r(x,b)`

not about each reward separately.

So the uncertainty measure should be defined over pairwise differences, with weights `w_t`.

Use this as the preference-learning analogue of standard Eluder dimension.

### 6. Weighted pairwise uncertainty

Convert a model difference into a bound controlled by the generalized preference Eluder quantity:

- numerator: the squared gap difference on the current duel
- denominator: a weighted history of past pairwise-difference information

This is the module that lets you plug concentration into Eluder-style uncertainty summation.

### 7. Local curvature weights

Define the local weights using the line-integrated sigmoid derivative between two pairwise gaps.

Then obtain the identity:

- squared preference-gap difference
  equals
- local curvature weight times squared reward-gap difference

This is the clean bridge from preference prediction error to pairwise reward uncertainty.

Also record the crude global bound:

- `w^{r, r~}(x,a,b) >= (1/16) e^{-4B}`

### 8. Bounds on `I_{1,t}` and `I_{2,t}`

Apply weighted uncertainty with the local curvature weights.

The pattern is:

- `I_{1,t}` is controlled by the Eluder-style uncertainty times a concentration term
- `I_{2,t}` is handled similarly, with an extra `beta_t` contribution because `r_2^t` only lies in the confidence set

This is where likelihood concentration, local curvature, and optimism all meet.

### 9. Summing uncertainty by preference Eluder dimension

Use the usual elliptical-potential style logic:

- define a normalized uncertainty ratio `q_t`
- bound `sum_t min(1, q_t)` by the preference Eluder dimension
- split into `q_t <= 1` and `q_t > 1`
- apply Cauchy--Schwarz on the good part

This is the standard route for turning per-round uncertainty control into total regret.

### 10. Good-round / bad-round split

This is the conceptual step that removes the exponential barrier from the **leading** term.

Split rounds into:

- good rounds: target and competitor are close enough that local curvature is constant-order
- bad rounds: curvature may be globally tiny, but these rounds consume enough uncertainty that they can only happen a limited number of times

Resulting pattern:

- good rounds contribute the square-root leading term
- bad rounds contribute a lower-order `e^{4B}` term

Be honest here:

- the exact constants depend on the threshold, the exact local-curvature event, the bonus factor, and whether weights are round-wise or sample-wise

### 11. Main theorem pattern

The standard finite-class regret theorem should look like:

- leading term:
  `B sqrt(prefdim * log(|R|T/delta) * T)`
- lower-order term:
  `B e^{4B} prefdim log(|R|T/delta)`

Then state the large-`T` regime where the leading term dominates.

### 12. Linear specialization

For linear reward classes:

`r_theta(x,a) = <phi(x,a), theta>`

the preference uncertainty reduces to an elliptical norm over:

`phi(x,a_1) - phi(x,a_2)`

and the preference Eluder dimension collapses to:

`O(d log(1 + T L^2 / (lambda d alpha)))`

This recovers a corollary of the form:

`Reg(T) = O~(B sqrt(dT) + B e^{4B} d)`

## Recommended appendix structure

Use a structure like:

```latex
\appendix

\section{Additional Notation and Preliminaries}
\section{MLE Concentration Under Bradley--Terry Feedback}
\subsection{Hellinger supermartingale argument}
\subsection{Confidence set validity}
\section{Proof of the Regret Decomposition}
\section{Preference-based Eluder Dimension and Uncertainty Control}
\subsection{Weighted pairwise uncertainty lemma}
\subsection{Local curvature weights}
\subsection{Summation by generalized Eluder dimension}
\section{Proof of the Main Regret Bound}
\subsection{Good-round analysis}
\subsection{Bad-round analysis}
\subsection{Completion of the proof}
\section{Linear Specialization}
```

## Common mistakes to avoid

### 1. Reusing `beta`
Do not use the same symbol for:

- regularization temperature
- confidence radius

Use `tau` and `beta_t` separately.

### 2. Regularizer sign inconsistency
If the policy objective is:

`r(x,pi) - tau D(pi || pi_ref)`

then every optimization and regret decomposition must keep the same minus sign.

### 3. Regret formula typo
Do not accidentally repeat `pi_1^t` twice inside the regularizer part of the regret.
The second term should involve `pi_2^t`.

### 4. Overclaiming explicit constants
The proof architecture is stable, but the exact constants depend on:

- the threshold in the good/bad split
- whether the proof uses `H^2`, KL, or squared preference gap
- the bonus factor
- whether the weights are sample-wise or round-wise

Use universal constants `C_1, C_2` unless there is a strong reason to chase constants.

## Short main-text proof sketch

When writing the main paper body, a short proof sketch should emphasize:

1. the optimistic competitor yields a regret decomposition depending only on the sampled duel
2. MLE concentration under Bradley--Terry feedback comes from a Hellinger supermartingale argument
3. local curvature plus preference-based Eluder dimension yields the square-root leading term
4. the bad rounds only contribute a lower-order `e^{4B}` term

## Limitations paragraph

The natural limitations are:

- realizability of the reward class
- Bradley--Terry / sigmoid link assumption
- no model misspecification or adversarial corruption
- lower-order term still depends on worst-case global curvature `e^{4B}`

## What this skill gives you

This skill gives you:

- clean notation
- MLE concentration via Hellinger supermartingale
- confidence-set validity
- competitor-induced regret decomposition
- weighted uncertainty lemma
- local curvature identity
- preference-Eluder definition
- main theorem skeleton
- linear specialization

The parts that still need project-specific tuning are:

- exact constants in the lower-order `e^{4B}` term
- the precise good-round threshold
- whether the class is finite, net-based, or parameterized
- whether the regularizer is KL specifically or a more general divergence
