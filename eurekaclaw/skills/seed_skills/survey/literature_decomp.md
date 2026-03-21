---
agent_roles:
- survey
created_at: '2026-03-19T23:32:30.830435'
description: 'Decompose a paper into cognitive primitives: Insight, Research Trending,
  Serendipity.'
name: literature_decomp
pipeline_stages:
- survey
source: seed
success_rate: 0.5790309899999999
tags:
- survey
- literature
- decomposition
- insight
- gaps
- open-problems
usage_count: 0
version: '1.0'
---

# Literature Decomposition

## When to apply
Use when analyzing a batch of papers to identify the research frontier and open problems.

## Strategy
For each paper, extract these three cognitive primitives:

1. **Insight** — The core technical contribution: What new mathematical object, algorithm, or lower bound does this paper introduce? State it in one formal sentence.

2. **Research Trending** — What direction is the field moving? What follow-up questions does this paper implicitly raise? Look for patterns across multiple papers.

3. **Serendipity** — What unexpected connection does this paper make? Cross-domain analogies, surprising equivalences, unintended applications.

## Literature map structure
After processing each paper, build:
- **Citation graph**: directed graph where A→B means A cites B
- **Open problems list**: extract explicit "open question" or "future work" sections
- **Key mathematical objects**: maintain a vocabulary of the central definitions (e.g., VC dimension, Rademacher complexity)

## Example
For a paper on "Generalization bounds via PAC-Bayes":
- Insight: Proves tighter bounds by taking a Bayesian prior over hypotheses
- Trending: Connection between Bayesian learning and robust generalization
- Serendipity: The KL divergence term is reminiscent of information-theoretic capacity