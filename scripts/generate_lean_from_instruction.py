#!/usr/bin/env python3
"""Generate Lean 4 code from a Markdown instruction file.

Flow:
  instructions/<name>.md  →  LLM  →  lean-gen/<name>.lean

Instructions are read from LEAN_WORKSPACE/instructions/.
Generated Lean files are written to LEAN_GEN_DIR (default: eurekaclaw/lean-gen/).

Set once (e.g. in .env or ~/.zshrc):
  export LEAN_WORKSPACE=/Users/qiwei/Desktop/Projects/lean-stat-learning-theory
  export LEAN_GEN_DIR=/Users/qiwei/eurekaclaw/lean-gen   # optional override

Then just pass the stem name:
  python scripts/generate_lean_from_instruction.py my_theorem
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

# Lean output lives in eurekaclaw/lean-gen/ by default, away from the SLT project
_SCRIPT_DIR = Path(__file__).resolve().parent
_DEFAULT_WORKSPACE = Path(
    os.environ.get("LEAN_WORKSPACE", str(_SCRIPT_DIR.parent / "lean-gen"))
)
_DEFAULT_LEAN_GEN = Path(
    os.environ.get("LEAN_GEN_DIR", str(_SCRIPT_DIR.parent / "lean-gen"))
)

from eurekaclaw.config import settings
from eurekaclaw.lean import LeanCodeFromInstructionGenerator


async def _run(instruction_path: Path, output_path: Path, max_tokens: int) -> None:
    generator = LeanCodeFromInstructionGenerator()
    result = await generator.generate(instruction_path, max_tokens=max_tokens)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(result.code.rstrip() + "\n", encoding="utf-8")
    print(f"Lean code written to: {output_path}", file=sys.stderr)


def _resolve_instruction(name: str, workspace: Path) -> Path:
    p = Path(name)
    if p.is_absolute():
        return p.expanduser().resolve()
    if p.suffix == ".md" and p.exists():
        return p.resolve()
    return workspace / "instructions" / (p.stem + ".md")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "name",
        help="Instruction name: stem ('my_theorem'), filename, or full path",
    )
    parser.add_argument(
        "--workspace", "-w",
        type=Path,
        default=_DEFAULT_WORKSPACE,
        help=f"Workspace root for instructions/ (default: $LEAN_WORKSPACE = {_DEFAULT_WORKSPACE})",
    )
    parser.add_argument(
        "--lean-gen-dir",
        type=Path,
        default=_DEFAULT_LEAN_GEN,
        help=f"Output directory for .lean files (default: $LEAN_GEN_DIR = {_DEFAULT_LEAN_GEN})",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Explicit output .lean path (overrides --lean-gen-dir)",
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
    instruction_path = _resolve_instruction(args.name, workspace)

    if not instruction_path.is_file():
        print(f"Instruction file not found: {instruction_path}", file=sys.stderr)
        return 1

    if args.output:
        output_path = args.output.expanduser().resolve()
    else:
        lean_gen_dir = args.lean_gen_dir.expanduser().resolve()
        output_path = lean_gen_dir / (instruction_path.stem + ".lean")

    max_tokens = args.max_tokens or settings.max_tokens_formalizer

    try:
        asyncio.run(_run(instruction_path, output_path, max_tokens))
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
