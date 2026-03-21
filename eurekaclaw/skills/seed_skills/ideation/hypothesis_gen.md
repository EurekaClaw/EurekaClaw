---
agent_roles:
- ideation
created_at: '2026-03-20T03:24:14.077445'
description: Generate novel research hypotheses by combining cross-domain insights
  and unexplored gaps.
name: hypothesis_gen
pipeline_stages:
- ideation
source: seed
success_rate: 0.6366789999999999
tags:
- ideation
- hypothesis
- novelty
- cross-domain
- divergent-thinking
usage_count: 0
version: '1.0'
---

# Hypothesis Generation

## When to apply
Use during the ideation phase to generate candidate research directions from a literature survey.

## Strategy
1. **Gap identification**: List the top-3 open problems from the literature. What theorems are missing?
2. **Analogy hunting**: For each open problem, ask: "Has this problem been solved in a different domain?" (e.g., results from statistical physics applied to ML theory)
3. **Conjecture weakening/strengthening**: Take an existing theorem and ask: "What if we relax assumption X? What if we strengthen conclusion Y?"
4. **Dual formulation**: Every upper bound suggests a lower bound. Every constructive proof suggests an algorithmic implementation.
5. **Combination hypothesis**: Take two unrelated results and ask: "What if both apply simultaneously?"

## Scoring hypotheses
For each candidate hypothesis, score on:
- **Novelty** (0-1): Distance from nearest known result
- **Feasibility** (0-1): Can this be proved with existing mathematical tools?
- **Impact** (0-1): Would this result be cited? Would it unlock other results?

## Example
From a survey on transformer generalization:
- Gap: No tight sample complexity bounds for attention-based architectures
- Analogy: Covering number bounds for RNNs from 2019 — can these techniques port?
- Hypothesis: "The sample complexity of transformers grows as O(L·d·log(d)/ε²) where L is depth and d is model dimension"