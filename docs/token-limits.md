# Token Limits

This document explains the `Token limits per call type` controls in the UI and the corresponding backend settings.

These limits do **not** change the model's total context window. They control the **maximum output length for a single model call** at a specific stage.

In practice:
- Raising a limit gives that stage more room to finish a proof, theorem statement, or draft.
- Lowering a limit makes the stage cheaper and faster, but increases the chance of truncation.
- The most useful limits to tune depend on which theory pipeline you are using.

## Where These Settings Live

Backend configuration lives in:
- `eurekaclaw/config.py`

The UI config mapping lives in:
- `eurekaclaw/ui/server.py` (`_CONFIG_FIELDS`)

The UI form lives in:
- `frontend/index.html`
- `eurekaclaw/ui/static/index.html`

## Quick Reference

| Variable | Default | Used by |
|---|---|---|
| `MAX_TOKENS_AGENT` | `8192` | Generic agent loops (SurveyAgent, WriterAgent, fallback paths) |
| `MAX_TOKENS_PROVER` | `4096` | `Prover` — lemma proof generation |
| `MAX_TOKENS_PLANNER` | `4096` | `DivergentConvergentPlanner` (diverge phase); converge uses half |
| `MAX_TOKENS_ARCHITECT` | `3072` | `ProofArchitect` in the `default` pipeline |
| `MAX_TOKENS_DECOMPOSER` | `4096` | `KeyLemmaExtractor` and legacy decomposer stages |
| `MAX_TOKENS_ASSEMBLER` | `6144` | `Assembler` — full proof narrative |
| `MAX_TOKENS_FORMALIZER` | `4096` | `Formalizer`, `Refiner`, `CounterexampleSearcher`, `ResourceAnalyst`, `PaperReader` |
| `MAX_TOKENS_CRYSTALLIZER` | `4096` | `TheoremCrystallizer` — final theorem statement |
| `MAX_TOKENS_ANALYST` | `1536` | `MemoryGuidedAnalyzer`, `TemplateSelector`, `ProofSkeletonBuilder` (`memory_guided` pipeline) |
| `MAX_TOKENS_SKETCH` | `1024` | `SketchGenerator` — Lean4/Coq sketch |
| `MAX_TOKENS_VERIFIER` | `2048` | `Verifier` and peer-review calls |
| `MAX_TOKENS_COMPRESS` | `512` | Context compression summaries (fast model) |

## Which Pipeline Uses What

There are two theory pipelines:
- `default`
- `memory_guided`

### `default` Pipeline

The stages that matter most for `default` are:
- `Architect`
- `Prover`
- `Assembler`
- `TheoremCrystallizer`
- `Verifier`

Relevant code:
- [default_proof_pipeline.yaml](eurekaclaw/agents/theory/proof_pipelines/default_proof_pipeline.yaml)
- [proof_architect.py](eurekaclaw/agents/theory/proof_architect.py)
- [prover.py](eurekaclaw/agents/theory/prover.py)
- [assembler.py](eurekaclaw/agents/theory/assembler.py)
- [theorem_crystallizer.py](eurekaclaw/agents/theory/theorem_crystallizer.py)
- [verifier.py](eurekaclaw/agents/theory/verifier.py)

If the `default` pipeline is struggling, the most useful knobs are usually:
1. `Architect`
2. `Prover`
3. `Assembler`
4. `TheoremCrystallizer`
5. `Verifier`

### `memory_guided` Pipeline

The stages that matter most for `memory_guided` are:
- `Analyst`
- `Decomposer`
- `Prover`
- `Assembler`
- `TheoremCrystallizer`
- `Verifier`

Relevant code:
- [memory_guided_proof_pipeline.yaml](eurekaclaw/agents/theory/proof_pipelines/memory_guided_proof_pipeline.yaml)
- [analysis_stages.py](eurekaclaw/agents/theory/analysis_stages.py)
- [key_lemma_extractor.py](eurekaclaw/agents/theory/key_lemma_extractor.py)
- [prover.py](eurekaclaw/agents/theory/prover.py)
- [assembler.py](eurekaclaw/agents/theory/assembler.py)
- [theorem_crystallizer.py](eurekaclaw/agents/theory/theorem_crystallizer.py)
- [verifier.py](eurekaclaw/agents/theory/verifier.py)

If the `memory_guided` pipeline is struggling, the most useful knobs are usually:
1. `Analyst`
2. `Decomposer`
3. `Prover`
4. `Assembler`
5. `TheoremCrystallizer`
6. `Verifier`

## What Each Important Stage Does

### Agent loop

Used by generic agent calls, including:
- `SurveyAgent`
- `WriterAgent`
- any stage that falls back to the generic base agent path

Relevant code:
- [base.py](eurekaclaw/agents/base.py)
- [agent.py](eurekaclaw/agents/survey/agent.py)
- [agent.py](eurekaclaw/agents/writer/agent.py)

Raise this when:
- survey answers are too short
- writer keeps stopping early

### Prover

Used for theorem-proof generation at the lemma level.

Relevant code:
- [prover.py](eurekaclaw/agents/theory/prover.py)

Raise this when:
- lemma proofs stop mid-argument
- prover keeps omitting technical steps

### Architect

Used by `ProofArchitect` in the `default` pipeline.

Relevant code:
- [proof_architect.py](eurekaclaw/agents/theory/proof_architect.py)

Raise this when:
- proof plans are too shallow
- the architect returns incomplete lemma structure

### Analyst

Used by `MemoryGuidedAnalyzer`, `TemplateSelector`, and `ProofSkeletonBuilder` in the `memory_guided` pipeline.

Relevant code:
- [analysis_stages.py](eurekaclaw/agents/theory/analysis_stages.py)

Raise this when:
- the pipeline picks poor proof templates
- proof skeletons are too sketchy
- memory-guided analysis is too thin

### Decomposer

Used by decomposition-style stages, including `KeyLemmaExtractor`.

Relevant code:
- [key_lemma_extractor.py](eurekaclaw/agents/theory/key_lemma_extractor.py)
- [decomposer.py](eurekaclaw/agents/theory/decomposer.py)

Raise this when:
- key lemmas are missing
- decomposition is too coarse

### Assembler

Used to produce `state.assembled_proof`.

Relevant code:
- [assembler.py](eurekaclaw/agents/theory/assembler.py)

Raise this when:
- the proof body ends mid-sentence
- `assembled_proof` looks truncated
- theorem extraction later fails because the proof narrative is incomplete

### TheoremCrystallizer

Used to produce `state.formal_statement`.

Relevant code:
- [theorem_crystallizer.py](eurekaclaw/agents/theory/theorem_crystallizer.py)

Raise this when:
- the theorem statement is truncated
- the theorem ends mid-formula
- the theorem block is missing assumptions or terms that are present in the assembled proof

### Verifier

Used for:
- lemma peer review
- consistency checking

Relevant code:
- [verifier.py](eurekaclaw/agents/theory/verifier.py)
- [consistency_checker.py](eurekaclaw/agents/theory/consistency_checker.py)

Raise this when:
- reviewer outputs are too terse
- consistency checks miss obvious issues

### Formalizer / Refiner

Shared budget for several theorem-support stages:
- `Formalizer`
- `Refiner`
- `CounterexampleSearcher`
- `ResourceAnalyst`
- `PaperReader`

Relevant code:
- [formalizer.py](eurekaclaw/agents/theory/formalizer.py)
- [refiner.py](eurekaclaw/agents/theory/refiner.py)
- [counterexample.py](eurekaclaw/agents/theory/counterexample.py)
- [resource_analyst.py](eurekaclaw/agents/theory/resource_analyst.py)
- [paper_reader.py](eurekaclaw/agents/theory/paper_reader.py)

Raise this when:
- paper extraction is too shallow
- counterexample search is too thin
- refinement suggestions are incomplete

## Practical Guidance

### If the assembled proof is truncated

Increase:
1. `Assembler`
2. `Prover` if lemma proofs are also too short

### If the theorem statement is truncated

Increase:
1. `TheoremCrystallizer`
2. `Assembler` if the proof narrative itself is incomplete

### If `default` planning is weak

Increase:
1. `Architect`
2. `Prover`

### If `memory_guided` planning is weak

Increase:
1. `Analyst`
2. `Decomposer`
3. `Prover`

### If writer or survey outputs are too short

Increase:
1. `Agent loop`

## Important Distinction

These controls are **not** the same as the model's full context window.

They only control:
- how much a single stage may output in one call

They do **not** directly control:
- how much total conversation history can be sent
- how large the model's full context window is

So a stage can fail in two different ways:
- the stage output is too short because its own token limit is too low
- the whole request is too heavy or too complex even though the per-call limit is large enough

## Current UI Coverage

The UI now exposes the major token-limit controls used by both theory pipelines, including:
- `Architect`
- `Assembler`
- `TheoremCrystallizer`
- `Analyst`
- `Sketch`

If you add new `max_tokens_*` fields in the backend later, remember to update:
- [server.py](eurekaclaw/ui/server.py)
- [frontend/index.html](frontend/index.html)
- [index.html](eurekaclaw/ui/static/index.html)
