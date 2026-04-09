#!/usr/bin/env python3
"""End-to-end Lean 4 formalization pipeline.

Flow:
  prompts/<name>.md  →  LLM  →  instructions/<name>.md  →  LLM  →  LeanGen/<name>.lean

All paths default to lean-gen/ inside the eurekaclaw repo.
Set LEAN_WORKSPACE to override the workspace root.

Usage:
  python scripts/generate_lean_pipeline.py theorem1
  python scripts/generate_lean_pipeline.py theorem1 --no-proof   # statement only
  python scripts/generate_lean_pipeline.py theorem1 --skip-instruction  # re-use existing instruction
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
_DEFAULT_LEAN_GEN = Path(
    os.environ.get("LEAN_GEN_DIR", str(_SCRIPT_DIR.parent / "lean-gen"))
)

from eurekaclaw.config import settings
from eurekaclaw.lean import LeanCodeFromInstructionGenerator, LeanInstructionGenerator
from eurekaclaw.lean.instruction_generator import (
    extract_formalized_section,
    extract_rules_section,
)


# ---------------------------------------------------------------------------
# Helpers (mirrors generate_lean_instruction.py)
# ---------------------------------------------------------------------------

_DEFAULT_REFERENCE_CANDIDATES = ["vibe-recipe/EXAMPLE_INSTRUCTIONS.md"]


def _load_sections(reference_paths: list[Path], extractor, heading: str) -> str:
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
    return [workspace / rel for rel in _DEFAULT_REFERENCE_CANDIDATES if (workspace / rel).is_file()]


def _parse_prompt(text: str) -> tuple[str, str, str]:
    def _section(heading: str) -> str:
        m = re.search(rf"##?\s+{re.escape(heading)}\s*\n(.*?)(?=\n##?\s+|\Z)", text, re.DOTALL | re.IGNORECASE)
        return m.group(1).strip() if m else ""

    return _section("Target Theorem") or text.strip(), _section("Context"), _section("Proof Strategy")


# ---------------------------------------------------------------------------
# Stage 1: prompt → instruction
# ---------------------------------------------------------------------------

async def _generate_instruction(
    prompt_path: Path,
    instruction_path: Path,
    reference_paths: list[Path],
    max_tokens: int,
    no_proof: bool,
) -> None:
    text = prompt_path.read_text(encoding="utf-8")
    target_theorem, additional_context, proof_strategy = _parse_prompt(text)

    if not target_theorem:
        print("Error: no 'Target Theorem' section in prompt file.", file=sys.stderr)
        sys.exit(1)

    existing_formalized = _load_sections(reference_paths, extract_formalized_section, "What We Have Formalized")
    existing_rules = _load_sections(reference_paths, extract_rules_section, "Rules")

    generator = LeanInstructionGenerator()
    await generator.generate(
        target_theorem=target_theorem,
        existing_formalized=existing_formalized,
        existing_rules=existing_rules,
        additional_context=additional_context,
        proof_strategy=proof_strategy,
        no_proof=no_proof,
        target_lean_file=prompt_path.stem + ".lean",
        output_path=instruction_path,
        max_tokens=max_tokens,
    )
    print(f"[1/2] Instruction written to: {instruction_path}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Stage 2: instruction → lean
# ---------------------------------------------------------------------------

async def _generate_lean(instruction_path: Path, output_path: Path, max_tokens: int) -> None:
    generator = LeanCodeFromInstructionGenerator()
    result = await generator.generate(instruction_path, max_tokens=max_tokens)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(result.code.rstrip() + "\n", encoding="utf-8")
    print(f"[2/2] Lean code written to: {output_path}", file=sys.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("name", help="Theorem stem, e.g. 'theorem1'")
    parser.add_argument(
        "--workspace", "-w",
        type=Path,
        default=_DEFAULT_WORKSPACE,
        help=f"Workspace root (default: $LEAN_WORKSPACE = {_DEFAULT_WORKSPACE})",
    )
    parser.add_argument(
        "--lean-gen-dir",
        type=Path,
        default=_DEFAULT_LEAN_GEN,
        help=f"Output dir for .lean files (default: $LEAN_GEN_DIR = {_DEFAULT_LEAN_GEN})",
    )
    parser.add_argument(
        "--skip-instruction",
        action="store_true",
        help="Skip stage 1 and use the existing instruction file.",
    )
    parser.add_argument(
        "--no-proof",
        action="store_true",
        help="Stage 1 only: generate theorem statement with `sorry`, skip proof.",
    )
    parser.add_argument(
        "--no-reference",
        action="store_true",
        help="Skip reference files when generating instruction.",
    )
    parser.add_argument(
        "--max-tokens", type=int, default=None,
        help=f"Max tokens per LLM call (default: {settings.max_tokens_formalizer})",
    )
    return parser.parse_args()


async def _main(args: argparse.Namespace) -> int:
    workspace = args.workspace.expanduser().resolve()
    stem = Path(args.name).stem

    prompt_path = workspace / "prompts" / (stem + ".md")
    instruction_path = workspace / "instructions" / (stem + ".md")
    lean_gen_dir = args.lean_gen_dir.expanduser().resolve()
    output_path = lean_gen_dir / "LeanGen" / (stem.capitalize().replace("_", "") + ".lean")

    max_tokens = args.max_tokens or settings.max_tokens_formalizer

    # Stage 1
    if not args.skip_instruction:
        if not prompt_path.is_file():
            print(f"Prompt file not found: {prompt_path}", file=sys.stderr)
            return 1
        reference_paths: list[Path] = [] if args.no_reference else _default_references(workspace)
        await _generate_instruction(prompt_path, instruction_path, reference_paths, max_tokens, args.no_proof)
    else:
        print(f"[1/2] Skipped — using existing: {instruction_path}", file=sys.stderr)

    # Stage 2
    if not instruction_path.is_file():
        print(f"Instruction file not found: {instruction_path}", file=sys.stderr)
        return 1
    await _generate_lean(instruction_path, output_path, max_tokens)
    return 0


def main() -> int:
    args = parse_args()
    try:
        return asyncio.run(_main(args))
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
