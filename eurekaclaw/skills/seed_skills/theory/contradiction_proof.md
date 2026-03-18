---
name: contradiction_proof
version: "1.0"
tags: [theory, proof, contradiction, reductio-ad-absurdum, impossibility]
agent_roles: [theory]
pipeline_stages: [proof_attempt, formalization]
description: "Prove a statement by assuming its negation leads to a contradiction."
source: seed
usage_count: 0
success_rate: null
---

# Proof by Contradiction

## When to apply
Use when:
- The statement is an impossibility or irrationality result
- Direct proof seems intractable but the negation has exploitable structure
- You need to show non-existence of a counterexample
- The statement involves extremal properties (smallest, largest, first)

## Strategy
1. **Assume the negation** — explicitly write `¬P` and introduce it as a hypothesis
2. **Explore consequences** — derive what must follow from `¬P`; use existing lemmas freely
3. **Find a contradiction** — identify two derived statements that are mutually exclusive, OR derive something that violates a known axiom/theorem
4. **Conclude** — since `¬P → ⊥`, we have `P`
5. **Double-check** — ensure the contradiction genuinely follows and doesn't rely on another unproven assumption

## Example application
Proving `√2` is irrational:
- Assume `√2 = p/q` in lowest terms (¬P)
- Then `2q² = p²`, so `p²` is even, so `p` is even
- Write `p = 2k`, then `2q² = 4k²`, so `q² = 2k²`, so `q` is even
- But then `gcd(p,q) ≥ 2` contradicts "lowest terms" ⊥

## Pitfalls to avoid
- **Proof by cases confusion**: contradiction only works if `¬P` leads to a _universal_ contradiction, not just one in some cases
- **Hidden assumptions**: make sure you're not assuming `P` somewhere in the middle
- **Weak contradictions**: `a ≠ a` is a true contradiction; `a` is large contradicts nothing without a bound
