---
agent_roles:
- writer
created_at: '2026-03-20T00:06:37.961421'
description: 'Standard structure for a theory paper: abstract, intro, related work,
  main results, proofs, conclusion.'
name: paper_structure
pipeline_stages:
- writing
source: seed
success_rate: 1.0
tags:
- writing
- latex
- paper
- structure
- theorem
- proof
usage_count: 4
version: '1.0'
---

# Theory Paper Structure

## Standard sections
1. **Abstract** (150 words): Problem, main result (state the theorem), significance
2. **Introduction**: Motivation → Prior work gaps → Our contributions (bullet list) → Paper organization
3. **Preliminaries**: Notation, definitions, background lemmas
4. **Main Results**: State theorems prominently in `\begin{theorem}...\end{theorem}` before proving them
5. **Proof of Main Theorem**: Use `\begin{proof}...\end{proof}`, cite lemmas as they appear
6. **Experiments** (if applicable): Validate theoretical bounds empirically
7. **Related Work**: Compare to prior work; be specific about what you improve
8. **Conclusion**: Summary, limitations, future work

## LaTeX theorem environments
```latex
\newtheorem{theorem}{Theorem}
\newtheorem{lemma}[theorem]{Lemma}
\newtheorem{corollary}[theorem]{Corollary}
\newtheorem{proposition}[theorem]{Proposition}
\newtheorem{definition}[theorem]{Definition}
\newtheorem{remark}{Remark}
```

## Proof structure
- Start with "We prove the theorem by [method]."
- Use `\qed` or `\hfill\square` at proof end
- For long proofs, use `\begin{proof}[Proof of Lemma X]`