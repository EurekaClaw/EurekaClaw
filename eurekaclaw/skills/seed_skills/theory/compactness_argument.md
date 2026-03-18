---
name: compactness_argument
version: "1.0"
tags: [theory, proof, compactness, topology, analysis, covering, finite-subcover]
agent_roles: [theory]
pipeline_stages: [proof_attempt, formalization, lemma_decomposition]
description: "Apply compactness (finite subcover / sequential compactness) to reduce infinite problems to finite ones."
source: seed
usage_count: 0
success_rate: null
---

# Compactness Arguments

## When to apply
Use when:
- You have an infinite collection of objects and need to extract a finite or convergent sub-collection
- Proving uniform bounds from pointwise bounds (Heine-Borel style)
- Extracting convergent subsequences (Bolzano-Weierstrass)
- In logic/CS: showing a property of all finite structures implies the infinite version
- In learning theory: VC dimension arguments, covering numbers, epsilon-nets

## Strategy
1. **Identify the infinite cover** — what open sets / balls / conditions are you working with?
2. **Verify compactness** — check the space is compact (closed + bounded in ℝⁿ, or use Tychonoff for products)
3. **Extract finite subcover** — apply compactness to find a finite subcollection that still covers
4. **Take max/min over finite set** — exploit that finite collections have well-defined extrema
5. **Conclude the uniform bound** — the uniform statement follows from the finite case

## Example application
Proving uniform continuity on [a,b]:
- For each x, there exists δ(x) such that f is δ(x)-continuous around x
- The open balls B(x, δ(x)/2) cover [a,b]
- By compactness, finitely many x₁,...,xₙ suffice
- Let δ = min{δ(xᵢ)/2 : i=1,...,n} > 0 (finite minimum!)
- Then f is δ-uniformly continuous ✓

## Pitfalls to avoid
- **Non-compact spaces**: compactness fails on open intervals, unbounded sets — verify closedness and boundedness
- **Infinite minimums**: min over an infinite set may be 0; always reduce to finite minimum
- **Wrong covering lemma**: ensure the cover is truly open (or adapt to the topology at hand)
