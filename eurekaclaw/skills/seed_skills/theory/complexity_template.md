---
name: complexity_template
version: "1.0"
tags: [theory, complexity, sample-complexity, VC-dimension, PAC-learning, generalization, covering-numbers]
agent_roles: [theory]
pipeline_stages: [formalization, proof_attempt, lemma_decomposition]
description: "Template for sample complexity and generalization bound proofs in ML theory."
source: seed
usage_count: 0
success_rate: null
---

# Sample Complexity / Generalization Bound Template

## When to apply
Use when proving:
- PAC learning sample complexity bounds
- Generalization bounds (Rademacher complexity, VC dimension)
- Uniform convergence results
- Oracle complexity in optimization

## Standard PAC Bound Template

**Goal**: Show that `m = O(1/ε² · (d·log(1/ε) + log(1/δ)))` samples suffice for ε-accurate learning with probability 1-δ.

**Proof steps**:
1. **Define the hypothesis class** H and loss function ℓ
2. **Uniform convergence via ε-nets**: For each ε, construct an ε-net of H with |N| ≤ (1/ε)^O(d)
3. **Chernoff/Hoeffding per net element**: For any fixed h, P[|R̂(h) - R(h)| > ε] ≤ 2exp(-2mε²)
4. **Union bound over net**: P[∃h∈N: deviation > ε] ≤ |N|·2exp(-2mε²)
5. **Approximation argument**: extend from net to all of H using Lipschitz or smoothness
6. **Set δ = RHS, solve for m**

## Rademacher Complexity Template

1. Define Rademacher complexity: `Rₘ(H) = E[supₕ∈H (1/m)∑σᵢh(xᵢ)]`
2. McDiarmid's inequality: generalization error bounded by `2Rₘ(H) + O(√(log(1/δ)/m))`
3. Compute `Rₘ(H)` using either: contraction lemma, Massart finite-class lemma, or covering number bound

## Pitfalls to avoid
- **Forgetting the 1-δ confidence**: bounds hold only with probability ≥ 1-δ, not in expectation
- **Uniform vs. pointwise convergence**: uniform convergence is needed for ERM generalization
- **Infinite hypothesis classes**: VC dimension being finite doesn't mean the class is finite
