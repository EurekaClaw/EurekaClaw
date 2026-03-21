---
agent_roles:
- writer
created_at: '2026-03-20T06:30:46.018424'
description: 'Enforce rigorous proof writing: no skipped logical steps, and every
  theorem or lemma must either be cited to the literature or proved in full.'
name: rigorous_proof_citation_discipline
pipeline_stages:
- writing
source: seed
success_rate: 1.0
tags:
- writing
- proof
- rigor
- theorem
- lemma
- citation
- latex
- paper
usage_count: 0
version: '1.0'
---

# Rigorous Proof and Citation Discipline

## When to apply

Use when:
- the Writer Agent is generating a theory paper
- the paper contains theorems, lemmas, propositions, corollaries, or claims
- proof quality and citation discipline matter more than brevity

This skill is especially important when the system is turning draft proof artifacts into a paper that should read like a serious math or theory manuscript.

## Core rule

Every formal statement that appears in the paper must satisfy one of the following:

1. it is accompanied by a rigorous proof in the paper, or
2. it is clearly identified as a known result and supported by a citation

Do not state a theorem, lemma, proposition, corollary, or claim as if it were established unless one of those two conditions is met.

## Proof-writing rules

### 1. No skipped reasoning

The proof must not jump from one nontrivial statement to another without explanation.

For every displayed derivation, inequality chain, or logical implication:
- explain why the step is valid
- name the theorem, lemma, assumption, or algebraic fact being used
- write out intermediate manipulations when they are not completely routine

Forbidden phrases unless immediately followed by a real derivation:
- “clearly”
- “it is obvious”
- “it is easy to see”
- “by standard arguments”
- “one can show”
- “it follows immediately”
- “similarly”

If a step is important enough to affect the rate, constant, dependence on parameters, or logical correctness, it must be written out.

### 2. Each theorem or lemma must be justified

For every theorem-like environment:
- if it is new in this paper, provide a proof
- if it is a known result, cite a source directly in the statement or immediately afterward
- if it is adapted from prior work, say what is being adapted and prove the new part

Do not leave “floating lemmas” in the paper with neither proof nor citation.

### 3. Citations must be specific

If a statement is supported by prior work:
- cite the source with `\cite{...}`
- make clear whether the cited source proves the exact statement or a slightly different one
- if the statement is only a corollary of the cited source, say so

Bad:
- “The following lemma is standard.”

Good:
- “The following concentration inequality is a direct consequence of Theorem 2 in \cite{...}.”
- “The next lemma is adapted from Lemma 4.3 of \cite{...}; the only change is the weighted norm.”

### 4. Adapted results still need local justification

If you modify a known result by changing:
- assumptions
- constants
- norms
- regularizers
- state-action domains
- dependence structure

then do not cite it as if it were identical.
You must either:
- give a complete proof, or
- explicitly isolate the modified step and prove the modification

### 5. Proofs should be line-by-line explainable

When writing a proof, aim for the standard:
- a careful reader can point to any line and ask “why is this true?”
- the answer is present in the text or immediate context

In practice, this means:
- introduce notation before using it
- say where inequalities come from
- identify where assumptions such as convexity, boundedness, or independence are used
- explain how prior lemmas are invoked
- explain where the proof ends and what exactly has been shown

## Practical theorem policy

Apply the following checklist to every formal statement:

- **Known and exact**: cite it.
- **Known but adapted**: cite the base result and prove the adaptation.
- **New and central**: prove it fully.
- **New and technical**: prove it fully or move the proof to an appendix, but do not omit it.

## Common mistakes to avoid

- **Citation without match**: citing a paper that does not actually prove the statement being used.
- **Proof by slogan**: replacing a real derivation with “standard concentration,” “standard coupling,” or “standard convexity argument.”
- **Hidden dependence on assumptions**: using independence, smoothness, or strong convexity without stating it at the step where it matters.
- **Recycling known lemmas as if they were new**: if it is from the literature, say so.
- **Stating claims only because they feel true**: if it is not cited and not proved, it should not appear as an established theorem-like result.

## Writer checklist before finalizing

Before returning the paper, verify:

- every theorem-like environment has either a proof or a citation
- every proof has no major unexplained jumps
- every nontrivial inequality has a stated justification
- every cited “standard fact” is attached to a specific source
- every adapted result identifies what is new relative to the cited source

If any formal statement fails this checklist, revise the draft before finalizing it.

## Response template

When writing a theorem paper under this skill:

1. State the theorem or lemma.
2. Immediately decide: **citation** or **proof**.
3. If citation: say exactly what source supports it.
4. If proof: write the proof with explicit justifications at each nontrivial step.
5. If adapted: cite the base result and prove the modified component explicitly.