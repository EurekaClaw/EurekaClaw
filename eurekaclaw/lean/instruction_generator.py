"""LLM-backed generation of Lean formalization instruction documents."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client


# ---------------------------------------------------------------------------
# System prompts — full proof vs. statement-only (--no-proof)
# ---------------------------------------------------------------------------

_SYSTEM_WITH_PROOF = """\
You are an expert mathematical proof architect specializing in Lean 4 formalization.

Generate exactly two sections for a Lean formalization instruction document:

## Target Theorem Statement

State the target theorem clearly in mathematical prose and LaTeX.
Explain informally what it means and why it matters.
Show the expected Lean 4 signature (with `by sorry` as a placeholder).

## Optimal Proof for Formalization

Break the proof into numbered steps. For each step:
- Give it a title and note if the required infrastructure is already formalized.
- Write the complete mathematical argument in enough detail that an LLM can
  translate it to Lean 4 tactics without guessing.
- Highlight key mathlib lemmas by name (e.g. `lintegral_liminf_le` for Fatou).
- Use **bold** for IMPORTANT warnings.

Style: LaTeX for math, ```lean4 blocks for code. Be precise about types and namespaces.
Do NOT output a "What We Have Formalized" section or a "Rules" section.
"""

_SYSTEM_NO_PROOF = """\
You are an expert mathematical proof architect specializing in Lean 4 formalization.

Generate exactly one section for a Lean formalization instruction document:

## Target Theorem Statement

State the target theorem clearly in mathematical prose and LaTeX.
Explain informally what it means.
Show the CORRECT Lean 4 statement — this is the most important part.
The proof body should be `by sorry`.

Focus entirely on getting the statement right:
- Correct types and universe levels
- Correct hypotheses (not too weak, not too strong)
- Idiomatic Lean 4 / mathlib naming

Do NOT output a proof strategy, a "What We Have Formalized" section, or a "Rules" section.
"""

_USER_TEMPLATE = """\
Generate the instruction sections for the following formalization task.

The declarations below are already available — use them when writing the theorem statement.

## Available Formalized Declarations

{formalized_context}

---

## New Theorem to Prove

{target_theorem}

## Additional Context

{additional_context}

{proof_strategy_block}
"""


# ---------------------------------------------------------------------------
# Section extractors
# ---------------------------------------------------------------------------

def extract_formalized_section(text: str) -> str:
    """Extract '## What We Have Formalized' verbatim from an instruction file."""
    m = re.search(
        r"(##\s+What We Have Formalized\b.*?)(?=\n##\s+|\n---|\Z)",
        text,
        re.DOTALL | re.IGNORECASE,
    )
    return m.group(1).strip() if m else ""


def extract_rules_section(text: str, target_lean_file: str = "") -> str:
    """Extract '## Rules' verbatim from an instruction file.

    If target_lean_file is provided, replace the filename in rule 1
    (e.g. 'OneDimGLSI.lean') with the actual target file name.
    """
    m = re.search(
        r"(##\s+Rules\b.*?)(?=\n##\s+|\n---|\Z)",
        text,
        re.DOTALL | re.IGNORECASE,
    )
    if not m:
        return ""
    section = m.group(1).strip()
    if target_lean_file:
        # Replace any *.lean filename in rule 1 with the actual target
        section = re.sub(
            r"(?m)(^1\..+?)(\w+\.lean)",
            lambda mo: mo.group(1) + target_lean_file,
            section,
            count=1,
        )
    return section


def make_no_proof_rules(target_lean_file: str = "") -> str:
    """Return a statement-focused Rules section for --no-proof mode."""
    filename = target_lean_file or "Target.lean"
    return f"""\
## Rules

1. Write all formalization code in {filename} .
2. **Success = `lake build` passes with `by sorry`.** The statement must typecheck — sorries are allowed, but zero type errors.
3. Do NOT guess Lean identifiers. Use fully qualified names or `open` the relevant namespace explicitly.
4. Prefer a smaller, type-correct statement over an ambitious one that uses likely-wrong APIs.
5. If the textbook wording is ambiguous, choose the smallest defensible statement and leave a short TODO comment."""


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

@dataclass
class GeneratedInstruction:
    content: str
    raw_response: str


# ---------------------------------------------------------------------------
# Generator
# ---------------------------------------------------------------------------

class LeanInstructionGenerator:
    """Generate a Lean formalization instruction Markdown document using an LLM.

    The LLM generates only: Target Theorem Statement (+ Optimal Proof if not --no-proof).
    "What We Have Formalized" and "Rules" are stitched in verbatim from reference files.

    Output structure::

        # TASK INSTRUCTIONS

        ## What We Have Formalized    ← verbatim from reference
        ---
        ## Target Theorem Statement   ┐  LLM-generated
        ## Optimal Proof              ┘  (skipped with no_proof=True)
        ---
        ## Rules                      ← verbatim from reference
    """

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def generate(
        self,
        *,
        target_theorem: str,
        existing_formalized: str = "",
        existing_rules: str = "",
        additional_context: str = "",
        proof_strategy: str = "",
        no_proof: bool = False,
        target_lean_file: str = "",
        # Legacy structured input
        formalized_decls: list[dict[str, Any]] | None = None,
        output_path: Path | None = None,
        max_tokens: int | None = None,
    ) -> GeneratedInstruction:
        """Generate a Lean instruction markdown document.

        Args:
            target_theorem: Theorem statement (prose / LaTeX).
            existing_formalized: "## What We Have Formalized" section, verbatim.
            existing_rules: "## Rules" section, verbatim.
            additional_context: Background or motivation.
            proof_strategy: High-level outline (LLM expands it).
            no_proof: If True, LLM only generates the theorem statement
                      (with `by sorry`), no proof steps.
            formalized_decls: Structured alternative to existing_formalized.
            output_path: Write markdown here if provided.
            max_tokens: Override LLM max_tokens.
        """
        # Build formalized context for the LLM prompt
        if existing_formalized:
            formalized_context = existing_formalized
        elif formalized_decls:
            formalized_context = _format_formalized_decls(formalized_decls)
        else:
            formalized_context = "(none — use mathlib only)"

        proof_strategy_block = (
            ""
            if no_proof
            else f"## Proof Outline (expand into detailed steps)\n\n{proof_strategy or '(not provided — generate a suitable one)'}"
        )

        user_text = _USER_TEMPLATE.format(
            formalized_context=formalized_context,
            target_theorem=target_theorem,
            additional_context=additional_context or "(none provided)",
            proof_strategy_block=proof_strategy_block,
        )

        system = _SYSTEM_NO_PROOF if no_proof else _SYSTEM_WITH_PROOF

        response = await self.client.messages.create(
            model=settings.active_model,
            max_tokens=max_tokens or settings.max_tokens_formalizer,
            system=system,
            messages=[{"role": "user", "content": user_text}],
        )
        llm_sections = response.content[0].text.strip() if response.content else ""

        # Determine rules and formalized section based on mode
        if no_proof:
            # Statement-only mode: simpler rules, no formalized context needed
            rules = make_no_proof_rules(target_lean_file)
            formalized_block = ""
        else:
            formalized_block = existing_formalized
            rules = existing_rules
            if rules and target_lean_file:
                rules = extract_rules_section(
                    "## Rules\n\n" + re.sub(r"^##\s+Rules\s*\n?", "", rules, count=1, flags=re.IGNORECASE),
                    target_lean_file=target_lean_file,
                )

        # Stitch: header + formalized (verbatim) + LLM sections + rules
        parts = ["# TASK INSTRUCTIONS", ""]
        if formalized_block:
            parts += [formalized_block, "", "---", ""]
        parts.append(llm_sections)
        if rules:
            parts += ["", "---", "", rules]
        content = "\n".join(parts).strip() + "\n"

        if output_path is not None:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(content, encoding="utf-8")

        return GeneratedInstruction(content=content, raw_response=llm_sections)


def _format_formalized_decls(formalized_decls: list[dict[str, Any]]) -> str:
    parts: list[str] = ["## What We Have Formalized", ""]
    for entry in formalized_decls:
        parts.append(f"### {entry.get('file', 'unknown')}")
        parts.append("")
        for decl in entry.get("decls", []):
            if decl.get("description"):
                parts.append(f"- {decl['description']}")
            if decl.get("signature"):
                parts.append(f"```lean4\n{decl['signature']}\n```")
        parts.append("")
    return "\n".join(parts).rstrip()
