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
usage_count: 0
version: '1.0'
---

# Theory Paper Structure

## Standard sections
1. **Abstract** (150 words): Problem, main result (state the theorem), significance
2. **Introduction**: Motivation → Prior work gaps → Our contributions (bullet list) → Paper organization
3. **Preliminaries**: Notation, definitions, background lemmas
4. **Main Results**: State theorems prominently in `\begin{theorem}...\end{theorem}` before proving them
5. **Proof of Main Theorem**: Use `\begin{proof}...\end{proof}`, cite lemmas as they appear, and justify every nontrivial step
6. **Experiments** (if applicable): Validate theoretical bounds empirically
7. **Related Work**: Compare to prior work; be specific about what you improve
8. **Conclusion**: Summary, limitations, future work

## Formal statement discipline
- Every theorem, lemma, proposition, corollary, or claim must either have a rigorous proof in the paper or an explicit citation
- If a result is adapted from prior work, cite the base result and prove the modified part
- Do not leave unsupported theorem-like statements in the paper

## Algorithm presentation
- If the paper contains an algorithm, typeset it in a LaTeX `algorithm` environment
- Give each algorithm a caption and label
- Refer to algorithms from the surrounding text using `Algorithm~\ref{...}`

## LaTeX sanity
- Ensure every environment is properly closed
- Ensure required packages are present for the commands and environments used
- Ensure every nonstandard macro is defined in the preamble
- Do not let Markdown syntax leak into LaTeX output

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
- Every nontrivial inequality or implication should say why it is valid
- Avoid phrases like "clearly", "standard", or "it is easy to see" unless the justification follows immediately