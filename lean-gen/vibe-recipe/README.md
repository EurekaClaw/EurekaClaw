# Lean 4 Vibe-Formalization Recipe

A practical guide and workflow for using agents to formalize mathematical proofs in Lean 4, summarized from our extensive experiences.

## Overview

We provide a hybrid approach to leveraging AI agents with human architect for Lean 4 proof formalization. All of our formalization is under the assistance of Claude Code with `Claude-Opus-4.5`. The workflow is designed to maximize agent efficiency, minimize context window usage, and produce clean, warning-free code.

## Key Principles

- **Decompose aggressively**: Break proofs into small, manageable lemmas
- **Minimize context pollution**: Use file outlines instead of reading full file contents
- **Leverage MCP tools**: Use semantic search tools for efficient declaration discovery
- **Clean iteratively**: Remove warnings and unused code systematically

## Workflow

### Step 1: Decompose Proofs into Small Lemmas

Break down your proof into smaller lemmas. The goal is for the agent to complete each lemma's formalization within a single context window **without** auto-compaction.

> **Empirical guideline**: Agents can typically handle up to ~300 lines of code per turn effectively.

Benefits of small lemmas:
- Increases thinking load for the agent
- Minimizes risk of context window overflow
- Makes debugging and iteration easier
- Improves code modularity and reusability

### Step 2: Design High-Quality Prompts

The initial instructions for agents should include possibly-needed local declarations identified by human and a well-written proof for formalization. We provide an example in `EXAMPLE_INSTRUCTIONS.md`.

For **project-local, pre-compiled declarations**:
- Write only the signatures of possibly-needed declarations in your instructions
- Use the file outline MCP tool (`mcp__lean-lsp__lean_file_outline`) to read signatures
- **Strictly forbid** the agent from reading full file contents

> ⚠️ **Important**: Reading entire files quickly fills the context window and causes hallucinations.

For **Mathlib declarations**:
- The agent can efficiently discover and use these via Lean external & internal search MCP tools
- No need to provide explicit signatures for standard Mathlib content

> ⚠️ **Human-in-the-Loop**: We identify a recurring failure pattern during agent's formalization. When generating extended Lean proofs in a single turn, the agent can produces code with a correct proof structure but contains localized, easily rectifiable tactic-level errors. However, due to the proof length, the agent receives numerous error diagnostics simultaneously. Rather than applying targeted fixes to individual tactics, the agent tends to interpret this volume of feedback as indicative of fundamental flaws, prompting substantial—and often deleterious—revisions to the proof strategy. This behavior frequently leads to the abandonment of a largely correct proof in favor of an incorrect alternative. We summarize some of these harmful signs:
> 1. Let me simplify the helper lemma by using a sorry for ...
> 2. There are many errors. Let me simplify the approach ...
> 3. The lemma has too many errors. Let me simplify it significantly with a cleaner proof ...
> 4. The proof is getting too complex with many subtle issues. Let me simplify by using a sorry for this lemma ...
> 5. There are many errors. Let me rewrite the file with a simpler, more direct approach ...
> 6. The errors are complex. Let me try a simpler approach ...
> 
> This failure mode underscores the importance of human-in-the-loop intervention. To leverage the agent's mathematical reasoning capabilities, we use the following prompt that instruct the agent to prioritize incremental error resolution:
> 
> ```DO NOT FREQUENTLY CHANGE PROOF, YOU ONLY NEED TO DO THIS WHEN YOU'RE CONFIDENT THAT IT IS WRONG. TRY TO FIX ERRORS ONE-BY-ONE.```
> 
> This approach works surprisingly well in practice. During incremental fixing, a small subset of tactic-level errors are structurally diagnostic: attempting to resolve them surfaces goal states that expose inconsistencies in the overall proof architecture. When the agent encounters such errors, it can identify the root cause of a flawed proof structure through localized feedback rather than holistic re-evaluation. These distilled error signals are substantially easier to verify than assessing the correctness of an entire proof, enabling more reliable agent self-correction.

### Step 3: Clean Warning Messages

After formalization, clean all compiler warnings using the following prompt:

```
Please modify the formalization code to eliminate the warning messages. **IMPORTANT:** For unused variables, you need to directly remove them instead of adding `_`, then correct the downstream call of modified results in [LIBRARYNAME]. Please use MCP tools to diagnose. The target file to modify is [FILENAME]
```

> **Note**: `Claude-Opus-4.5` will mask the unused variables by `_` with high preference without explicit instructions.

### Step 4: Clean Unused `have` Statements

Remove unused `have` statements systematically with this prompt:

```
Clean up unused have statements from the target Lean file. First, use the MCP tool mcp__lean-lsp__lean_file_outline with the absolute file path to get the file outline and identify all theorem/lemma declarations in the file. Then, update @TestUnusedHave.lean to include #check_unused_have command for each declaration you want to analyze (replace instead of adding). Run lake build TestUnusedHave to identify which theorems have unused have statements and note their names. For each unused statement reported, use Grep to find its exact location in the file, then use Edit to remove the entire have statement including any multi-line proof body. Work from bottom to top (highest line numbers first) to preserve line number accuracy during edits. For have statements on the same line as other tactics (like have hX := rfl; linarith), either inline the fact into the tactic (e.g., linarith [show X from rfl]) or just keep the tactic if it doesn't need the fact. After removing all identified statements, run lake build [FILENAME] to verify compilation succeeds. Then re-run lake build TestUnusedHave to check for any cascading unused statements that were exposed (statements that were only used by the ones you just removed). Repeat the removal and verification cycle until all theorems in the file report "No unused have statements found". Track progress and provide a summary of total statements removed when complete. The target Lean file is [FILENAME].
```

> ⚠️ **Important**: We recommend to repeatedly run Step 3 & 4 until they are both clean.

## Best Practices

### Do's ✅

- Decompose proofs into the smallest reasonable units
- Provide only necessary signatures for local declarations
- Use MCP tools for context-economic assistance
- Clean warnings and unused code iteratively

### Don'ts ❌

- Don't let the agent read entire file contents
- Don't attempt to formalize >300 lines in a single turn
- Don't suppress warnings with `_` prefixes—remove unused variables entirely
- Don't skip the cleanup steps
