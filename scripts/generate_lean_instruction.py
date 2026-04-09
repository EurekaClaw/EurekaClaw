#!/usr/bin/env python3
"""Generate a Lean 4 formalization instruction Markdown document using an LLM.

Flow:
  prompts/<name>.md  +  reference instruction files
      →  LLM  →  instructions/<name>.md

The "What We Have Formalized" section is extracted verbatim from reference
files and stitched directly into the output — the LLM never modifies it.
The LLM only generates: Target Theorem Statement, Optimal Proof, Rules.

Set LEAN_WORKSPACE once:
  export LEAN_WORKSPACE=/Users/qiwei/Desktop/Projects/lean-stat-learning-theory

Then just pass the stem name:
  python scripts/generate_lean_instruction.py my_theorem

Reference files are loaded automatically:
  1. <workspace>/vibe-recipe/EXAMPLE_INSTRUCTIONS.md  (if it exists)
  2. All .md files in <workspace>/instructions/       (already-generated ones)
  Use --reference to override with explicit files.

Prompt file format (plain Markdown):

  # Target Theorem
  <theorem statement in prose / LaTeX>

  ## Context (optional)
  <background, references to existing results>

  ## Proof Strategy (optional)
  <high-level proof outline — LLM will expand it>
"""

from __future__ import annotations

import argparse
import asyncio
import os
import re
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
_DEFAULT_WORKSPACE = Path(
    os.environ.get("LEAN_WORKSPACE", str(_SCRIPT_DIR.parent / "lean-gen"))
)

from eurekaclaw.config import settings
from eurekaclaw.textbook import LeanInstructionGenerator
from eurekaclaw.textbook.instruction_generator import (
    extract_formalized_section,
    extract_rules_section,
)


# ---------------------------------------------------------------------------
# Reference file loading
# ---------------------------------------------------------------------------

_DEFAULT_REFERENCE_CANDIDATES = [
    "vibe-recipe/EXAMPLE_INSTRUCTIONS.md",
]


def _load_sections(
    reference_paths: list[Path],
    extractor,
    heading: str,
) -> str:
    """Extract and merge a named section from multiple reference files."""
    bodies: list[str] = []
    heading_pattern = re.compile(rf"^##\s+{re.escape(heading)}\s*\n?", re.IGNORECASE)
    for path in reference_paths:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        section = extractor(text)
        if section:
            body = heading_pattern.sub("", section, count=1).strip()
            if body:
                bodies.append(body)
            print(f"  [ref] loaded '{heading}' from {path.name}", file=sys.stderr)

    if not bodies:
        return ""
    return f"## {heading}\n\n" + "\n\n".join(bodies)


def _default_references(workspace: Path) -> list[Path]:
    refs: list[Path] = []
    for rel in _DEFAULT_REFERENCE_CANDIDATES:
        p = workspace / rel
        if p.is_file():
            refs.append(p)
    return refs


# ---------------------------------------------------------------------------
# Prompt parser
# ---------------------------------------------------------------------------

def _parse_prompt(text: str) -> tuple[str, str, str]:
    """Extract (target_theorem, context, proof_strategy) from a prompt .md file."""
    def _extract_section(heading: str) -> str:
        pattern = rf"##?\s+{re.escape(heading)}\s*\n(.*?)(?=\n##?\s+|\Z)"
        m = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
        return m.group(1).strip() if m else ""

    target = _extract_section("Target Theorem") or text.strip()
    context = _extract_section("Context")
    strategy = _extract_section("Proof Strategy")
    return target, context, strategy


# ---------------------------------------------------------------------------
# Async core
# ---------------------------------------------------------------------------

async def _run(
    prompt_path: Path,
    output_path: Path,
    reference_paths: list[Path],
    max_tokens: int,
    no_proof: bool,
) -> None:
    text = prompt_path.read_text(encoding="utf-8")
    target_theorem, additional_context, proof_strategy = _parse_prompt(text)

    if not target_theorem:
        print("Error: could not find a 'Target Theorem' section in the prompt file.", file=sys.stderr)
        sys.exit(1)

    existing_formalized = _load_sections(
        reference_paths, extract_formalized_section, "What We Have Formalized"
    )
    existing_rules = _load_sections(
        reference_paths, extract_rules_section, "Rules"
    )

    generator = LeanInstructionGenerator()
    await generator.generate(
        target_theorem=target_theorem,
        existing_formalized=existing_formalized,
        existing_rules=existing_rules,
        additional_context=additional_context,
        proof_strategy=proof_strategy,
        no_proof=no_proof,
        target_lean_file=prompt_path.stem + ".lean",
        output_path=output_path,
        max_tokens=max_tokens,
    )
    print(f"Instruction written to: {output_path}", file=sys.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _resolve_prompt(name: str, workspace: Path) -> Path:
    p = Path(name)
    if p.is_absolute():
        return p.expanduser().resolve()
    if p.suffix == ".md" and p.exists():
        return p.resolve()
    return workspace / "prompts" / (p.stem + ".md")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "name",
        help="Prompt name: stem ('my_theorem'), filename, or full path",
    )
    parser.add_argument(
        "--workspace", "-w",
        type=Path,
        default=_DEFAULT_WORKSPACE,
        help=f"Workspace root (default: $LEAN_WORKSPACE = {_DEFAULT_WORKSPACE})",
    )
    parser.add_argument(
        "--reference", "-r",
        type=Path,
        nargs="*",
        default=None,
        metavar="FILE",
        help=(
            "Reference instruction .md files to extract 'What We Have Formalized' from. "
            "Default: vibe-recipe/EXAMPLE_INSTRUCTIONS.md inside the workspace."
        ),
    )
    parser.add_argument(
        "--no-reference",
        action="store_true",
        help="Skip all reference files (generate without existing formalized context).",
    )
    parser.add_argument(
        "--no-proof",
        action="store_true",
        help=(
            "Statement-only mode: generate only the theorem statement (with `by sorry`), "
            "skip the proof strategy. Use this to verify the formulation before writing the proof."
        ),
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output path. Default: <workspace>/instructions/<stem>.md",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=None,
        help=f"Max tokens (default: {settings.max_tokens_formalizer})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    workspace = args.workspace.expanduser().resolve()
    prompt_path = _resolve_prompt(args.name, workspace)

    if not prompt_path.is_file():
        print(f"Prompt file not found: {prompt_path}", file=sys.stderr)
        return 1

    output_path: Path = (
        args.output.expanduser().resolve()
        if args.output
        else workspace / "instructions" / (prompt_path.stem + ".md")
    )

    if args.no_reference:
        reference_paths: list[Path] = []
    elif args.reference:
        reference_paths = [p.expanduser().resolve() for p in args.reference]
    else:
        reference_paths = _default_references(workspace)

    max_tokens = args.max_tokens or settings.max_tokens_formalizer

    try:
        asyncio.run(_run(prompt_path, output_path, reference_paths, max_tokens, args.no_proof))
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
