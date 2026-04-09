"""LLM-backed instruction .md -> Lean 4 code generation."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client


LEAN_CODE_SYSTEM = """\
You are an expert Lean 4 formalization assistant specializing in mathlib-based proofs.

You receive a structured instruction document (in Markdown) that describes:
- What has already been formalized (definitions, lemmas, theorems with signatures)
- The target theorem to prove
- An optimal proof strategy broken into numbered steps
- Rules and constraints for the formalization

Your task is to produce a complete Lean 4 file implementing the target theorem.

Requirements:
- Output ONLY Lean code, no markdown fences, no prose.
- Always begin with `import Mathlib`.
- Respect all rules stated in the instruction document.
- Follow the proof strategy exactly as described.
- Use the signatures provided in the instruction document verbatim — do not
  re-derive or modify them.
- Prefer a lemma-based modular approach: decompose the proof into named lemmas,
  then combine them into the main theorem.
- It is acceptable to use `by sorry` for individual lemmas as placeholders, but
  the overall structure must be correct.
- Do NOT frequently change proof strategy. Fix errors one-by-one.
- Do NOT invent Lean identifiers not present in mathlib or the instruction document.
- In measure/probability theory, use names under `MeasureTheory` and related
  mathlib namespaces.
"""


LEAN_CODE_USER = """\
Below is the full instruction document for this formalization task.
Generate the Lean 4 file as instructed.

---

{instruction_content}
"""


@dataclass
class GeneratedLeanCode:
    code: str
    raw_response: str
    instruction_path: str


def _strip_code_fences(text: str) -> str:
    fenced = re.search(r"```(?:lean)?\s*(.*?)```", text, re.DOTALL | re.IGNORECASE)
    if fenced:
        return fenced.group(1).strip()
    return text.strip()


class LeanCodeFromInstructionGenerator:
    """Generate Lean 4 code from a Markdown instruction file.

    The instruction file follows the structure of EXAMPLE_INSTRUCTIONS.md:
    - Section describing what has been formalized (with signatures)
    - Target theorem statement
    - Optimal proof strategy (numbered steps)
    - Rules

    Usage::

        generator = LeanCodeFromInstructionGenerator()
        result = await generator.generate(Path("EXAMPLE_INSTRUCTIONS.md"))
        print(result.code)
    """

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def generate(
        self,
        instruction_path: Path,
        *,
        max_tokens: int | None = None,
    ) -> GeneratedLeanCode:
        """Generate Lean code from the given instruction markdown file.

        Args:
            instruction_path: Path to the .md instruction file.
            max_tokens: Override for the LLM max_tokens. Defaults to
                        settings.max_tokens_formalizer.

        Returns:
            GeneratedLeanCode with the generated Lean source.
        """
        instruction_content = instruction_path.read_text(encoding="utf-8")
        user_text = LEAN_CODE_USER.format(instruction_content=instruction_content)

        response = await self.client.messages.create(
            model=settings.active_model,
            max_tokens=max_tokens or settings.max_tokens_formalizer,
            system=LEAN_CODE_SYSTEM,
            messages=[{"role": "user", "content": user_text}],
        )
        raw = response.content[0].text if response.content else ""
        code = _strip_code_fences(raw)
        return GeneratedLeanCode(
            code=code,
            raw_response=raw,
            instruction_path=str(instruction_path),
        )
