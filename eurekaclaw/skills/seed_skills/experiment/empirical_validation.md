---
agent_roles:
- experiment
created_at: '2026-03-20T00:06:37.960352'
description: 'Validate theoretical bounds empirically: verify the bound holds and
  is tight.'
name: empirical_validation
pipeline_stages:
- experiment
source: seed
success_rate: 1.0
tags:
- experiment
- validation
- numerical
- bounds
- ablation
usage_count: 0
version: '1.0'
---

# Empirical Validation of Theoretical Bounds

## When to apply
Use when the theory agent has produced bounds (e.g., sample complexity O(d/ε²)) that need numerical validation.

## Strategy
1. **Translate bound to code**: Convert the mathematical statement to a measurable quantity (e.g., if the bound says m = O(d log d / ε²), define m as a function of d and ε)
2. **Sweep parameters**: Vary d and ε over a grid; measure the actual quantity (e.g., empirical generalization error)
3. **Overlay bound on plot**: Plot both the theoretical bound and empirical measurement; check the bound is an upper bound (theoretical ≥ empirical)
4. **Check tightness**: Is there a configuration where theoretical ≈ empirical? If not, the bound may be loose
5. **Ablation**: Remove key assumptions one at a time; verify the bound degrades gracefully

## Standard validation code template
```python
import numpy as np

def validate_bound(theoretical_fn, empirical_fn, param_grid):
    results = []
    for params in param_grid:
        theory = theoretical_fn(**params)
        empirical = empirical_fn(**params)
        results.append({
            **params,
            "theoretical": theory,
            "empirical": empirical,
            "ratio": theory / (empirical + 1e-10),
            "bound_holds": theory >= empirical,
        })
    return results
```

## Pitfalls
- **Finite sample noise**: Run multiple seeds and report mean ± std
- **Asymptotic vs. finite regime**: O(·) hides constants; the bound may not hold for small d
- **Wrong metric**: Ensure you're measuring what the theorem claims (e.g., generalization error, not training error)