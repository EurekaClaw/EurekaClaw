# Configuration

All settings are read from environment variables (or a `.env` file in the project root). Copy `.env.example` to `.env` and edit before running.

## LLM Backend

| Variable | Default | Description |
|---|---|---|
| `LLM_BACKEND` | `anthropic` | Backend: `anthropic`, `openrouter`, `local`, `minimax` |
| `ANTHROPIC_API_KEY` | `""` | Anthropic API key. If empty, falls back to ccproxy OAuth (`~/.claude/.credentials.json`) |
| `ANTHROPIC_AUTH_MODE` | `api_key` | `api_key` or `oauth` (ccproxy) |
| `ANTHROPIC_BASE_URL` | `""` | Override base URL for the Anthropic client (e.g. for proxies or test servers) |
| `CCPROXY_PORT` | `8000` | Port for ccproxy server |
| `OPENAI_COMPAT_BASE_URL` | `""` | Base URL for OpenAI-compatible endpoint (OpenRouter / local vLLM) |
| `OPENAI_COMPAT_API_KEY` | `""` | API key for OpenAI-compatible endpoint |
| `OPENAI_COMPAT_MODEL` | `""` | Model name for OpenAI-compatible endpoint |

**Backend shortcuts:**

| `LLM_BACKEND` | Notes |
|---|---|
| `anthropic` | Default. Uses `ANTHROPIC_API_KEY` or ccproxy OAuth |
| `openrouter` | Set `OPENAI_COMPAT_API_KEY=sk-or-...` |
| `local` | Defaults to `http://localhost:8000/v1` (vLLM / Ollama) |
| `minimax` | Set `MINIMAX_API_KEY` and `MINIMAX_MODEL` |

**Minimax-specific variables:**

| Variable | Default | Description |
|---|---|---|
| `MINIMAX_API_KEY` | `""` | Minimax API key |
| `MINIMAX_MODEL` | `""` | Minimax model name (e.g. `abab7-chat`) |

## Models

| Variable | Default | Description |
|---|---|---|
| `EUREKACLAW_MODEL` | `claude-sonnet-4-6` | Main reasoning model (all agents) |
| `EUREKACLAW_FAST_MODEL` | `claude-haiku-4-5-20251001` | Fast/cheap model for compression, formalization, counterexample |

`settings.active_model` and `settings.active_fast_model` are **derived read-only properties** that resolve the correct model string for the active backend. All agents use these properties — never the raw `EUREKACLAW_MODEL` variable directly.

## External APIs

| Variable | Default | Description |
|---|---|---|
| `S2_API_KEY` | `""` | Semantic Scholar API key (optional — higher rate limits) |
| `BRAVE_SEARCH_API_KEY` | `""` | Brave Search API key (web search) |
| `SERPAPI_KEY` | `""` | SerpAPI key (web search fallback) |
| `WOLFRAM_APP_ID` | `""` | Wolfram Alpha app ID (symbolic computation) |

## Pipeline Modes

| Variable | Default | Options | Description |
|---|---|---|---|
| `EUREKACLAW_MODE` | `skills_only` | `skills_only`, `rl`, `madmax` | Post-run learning mode |
| `GATE_MODE` | `auto` | `auto`, `human`, `none` | Stage gate behavior |
| `THEORY_PIPELINE` | `default` | `default`, `memory_guided` | Which theory proof pipeline to use |
| `OUTPUT_FORMAT` | `latex` | `latex`, `markdown` | Paper output format |
| `EXPERIMENT_MODE` | `auto` | `auto`, `true`, `false` | Experiment stage: auto-detect / force run / force skip *(future work — recommend `false`)* |

**Gate modes:**
- `none` — no stage cards or approval prompts
- `auto` — prints stage summary cards; prompts only when low-confidence lemmas detected
- `human` — prints cards and prompts at every gate; accepts text feedback injected into next agent

## Proof & Theory

| Variable | Default | Description |
|---|---|---|
| `THEORY_MAX_ITERATIONS` | `10` | Max proof iterations in LemmaDeveloper loop |
| `THEORY_REVIEW_MAX_RETRIES` | `3` | Max retries when human reviewer flags a proof step |
| `AUTO_VERIFY_CONFIDENCE` | `0.95` | Auto-accept proofs with confidence ≥ this threshold (skips LLM Verifier call) |
| `VERIFIER_PASS_CONFIDENCE` | `0.90` | Confidence threshold for the LLM Verifier to mark a lemma as passing |
| `STAGNATION_WINDOW` | `3` | Force Refiner if same error repeats N times |
| `ENFORCE_PROOF_STYLE` | `true` | Inject proof readability rules into WriterAgent prompts |

## Context & Compression

| Variable | Default | Description |
|---|---|---|
| `CONTEXT_COMPRESS_AFTER_TURNS` | `6` | Compress agent history every N turns using fast model |

## Token Limits (per call type)

| Variable | Default | Applies to |
|---|---|---|
| `MAX_TOKENS_AGENT` | `8192` | Main agent reasoning loop (all agents) |
| `MAX_TOKENS_PROVER` | `4096` | Proof generation (Prover) |
| `MAX_TOKENS_PLANNER` | `4096` | Research direction planning (diverge); converge uses half |
| `MAX_TOKENS_DECOMPOSER` | `4096` | Lemma decomposition (LemmaDecomposer, KeyLemmaExtractor) |
| `MAX_TOKENS_ASSEMBLER` | `6144` | Proof assembly narrative (Assembler) |
| `MAX_TOKENS_CRYSTALLIZER` | `4096` | Final theorem statement extraction (TheoremCrystallizer) |
| `MAX_TOKENS_ARCHITECT` | `3072` | Proof plan generation (ProofArchitect) |
| `MAX_TOKENS_ANALYST` | `1536` | Analysis stages (MemoryGuidedAnalyzer, TemplateSelector, ProofSkeletonBuilder) |
| `MAX_TOKENS_SKETCH` | `1024` | Lean4/Coq sketch generation (SketchGenerator) |
| `MAX_TOKENS_FORMALIZER` | `4096` | Formalization, Refiner, CounterexampleSearcher, ResourceAnalyst, PaperReader |
| `MAX_TOKENS_VERIFIER` | `2048` | Proof verification (Verifier) and peer review |
| `MAX_TOKENS_COMPRESS` | `512` | Context compression summaries (fast model) |

All 12 values are adjustable from the Settings tab in the web UI.

## Paper Reader

| Variable | Default | Description |
|---|---|---|
| `PAPER_READER_USE_PDF` | `true` | Download and extract from full PDF in addition to abstract |
| `PAPER_READER_ABSTRACT_PAPERS` | `10` | Max papers to extract from abstract |
| `PAPER_READER_PDF_PAPERS` | `3` | Max papers to extract from full PDF |

## Turn Limits

| Variable | Default | Description |
|---|---|---|
| `SURVEY_MAX_TURNS` | `8` | Tool-use turns in SurveyAgent loop |
| `THEORY_STAGE_MAX_TURNS` | `6` | Turns per inner theory stage |
| `WRITER_MAX_TURNS` | `4` | Turns for WriterAgent |

## Search & Retrieval

| Variable | Default | Description |
|---|---|---|
| `ARXIV_MAX_RESULTS` | `10` | Hard cap on arXiv search results |

## Retry & Resilience

| Variable | Default | Description |
|---|---|---|
| `LLM_RETRY_ATTEMPTS` | `5` | Retry count on 5xx / rate-limit errors |
| `LLM_RETRY_WAIT_MIN` | `4` | Minimum exponential backoff (seconds) |
| `LLM_RETRY_WAIT_MAX` | `90` | Maximum exponential backoff (seconds) |

## File Paths & Tools

| Variable | Default | Description |
|---|---|---|
| `EUREKACLAW_DIR` | `~/.eurekaclaw` | Base directory for skills, memory, and run artifacts |
| `LEAN4_BIN` | `lean` | Path to the Lean4 binary |
| `LATEX_BIN` | `pdflatex` | Path to the pdflatex binary |
| `USE_DOCKER_SANDBOX` | `false` | Use Docker container for Python code execution *(future work — sandbox not fully integrated)* |

## Derived Paths (read-only properties on `settings`)

| Property | Value |
|---|---|
| `settings.skills_dir` | `EUREKACLAW_DIR/skills` |
| `settings.memory_dir` | `EUREKACLAW_DIR/memory` |
| `settings.runs_dir` | `EUREKACLAW_DIR/runs` |
| `settings.fast_model` | `EUREKACLAW_FAST_MODEL` (falls back to main model if unset) |
