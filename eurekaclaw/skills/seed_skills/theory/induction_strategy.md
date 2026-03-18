---
name: induction_strategy
version: "1.0"
tags: [theory, proof, induction, recursion, natural-numbers]
agent_roles: [theory]
pipeline_stages: [proof_attempt, lemma_decomposition, formalization]
description: "Apply mathematical induction to prove properties over structured objects."
source: seed
usage_count: 0
success_rate: null
---

# Induction Strategy

## When to apply
Use when the target object has recursive or hierarchical structure: natural numbers, lists, trees, graphs, or any inductively-defined type. Also applies to proofs by strong induction or structural induction.

## Strategy
1. **Identify the induction variable** — what varies across the claim? (e.g., `n`, tree depth, list length)
2. **State the induction hypothesis (IH)** — what you assume for `n=k` (or for all sub-structures)
3. **Prove the base case** — typically `n=0` or `n=1`, often trivial
4. **Prove the inductive step** — assuming IH, show the property holds for `n=k+1`
5. **Check boundary conditions** — verify the claim holds at edge cases (empty structures, maximal elements)

## Example application
To prove `∑_{i=1}^{n} i = n(n+1)/2`:
- Base case: `n=1`, LHS=1, RHS=1·2/2=1 ✓
- IH: assume `∑_{i=1}^{k} i = k(k+1)/2`
- Step: `∑_{i=1}^{k+1} i = IH + (k+1) = k(k+1)/2 + (k+1) = (k+1)(k+2)/2` ✓

## Pitfalls to avoid
- **Circular IH**: using the IH for a value _larger_ than you're trying to prove
- **Off-by-one errors**: forgetting to check base case n=0 separately from n=1
- **Missing strong induction**: when the IH for `k` alone isn't enough — assume for all `j ≤ k`
