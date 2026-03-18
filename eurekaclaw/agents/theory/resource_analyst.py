"""ResourceAnalyst — math decomposer and bidirectional math↔code mapping (AI-Researcher pattern)."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from eurekaclaw.llm import LLMClient, create_client

from eurekaclaw.config import settings
from eurekaclaw.types.artifacts import TheoryState

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

ANALYST_SYSTEM = """\
You are a resource analyst for theoretical research. Given a formal mathematical statement, \
you decompose it into atomic components and create explicit bidirectional mappings between \
mathematical formulations and code implementations.

This reduces hallucination risks by grounding abstract math in concrete code.
"""

ANALYST_USER = """\
Analyze this formal theorem and create a math↔code bidirectional mapping:

Theorem: {formal_statement}
Domain: {domain}

Produce:
1. **Atomic components**: Decompose the theorem into its minimal mathematical primitives
   (each definition, operation, and quantifier)
2. **Math→Code mappings**: For each math primitive, provide a Python code equivalent
3. **Code→Math mappings**: For each code implementation choice, explain the math it represents
4. **Validation code**: A Python snippet that empirically checks the theorem on small cases

Return as JSON:
{{
  "atomic_components": [{{"math": "...", "description": "..."}}],
  "math_to_code": {{"math_symbol_or_expr": "python_code_snippet"}},
  "code_to_math": {{"python_name": "math_description"}},
  "validation_code": "python_code_string"
}}
"""


@dataclass
class ResourceAnalysis:
    atomic_components: list[dict] = field(default_factory=list)
    math_to_code: dict[str, str] = field(default_factory=dict)
    code_to_math: dict[str, str] = field(default_factory=dict)
    validation_code: str = ""


class ResourceAnalyst:
    """Runs in parallel with the Theory Agent inner loop to maintain math↔code mappings."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self.client: LLMClient = client or create_client()

    async def analyze(self, state: TheoryState, domain: str = "") -> ResourceAnalysis:
        """Decompose the formal statement into atomic components with code mappings."""
        if not state.formal_statement:
            return ResourceAnalysis()

        try:
            response = await self.client.messages.create(
                model=settings.eurekaclaw_fast_model,
                max_tokens=2048,
                system=ANALYST_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": ANALYST_USER.format(
                        formal_statement=state.formal_statement,
                        domain=domain or "mathematics",
                    ),
                }],
            )
            text = response.content[0].text
            return self._parse_analysis(text)

        except Exception as e:
            logger.exception("Resource analysis failed: %s", e)
            return ResourceAnalysis()

    def _parse_analysis(self, text: str) -> ResourceAnalysis:
        for delim_start, delim_end in [("```json", "```"), ("{", None)]:
            try:
                if delim_start in text:
                    start = text.index(delim_start) + len(delim_start)
                    if delim_end:
                        end = text.index(delim_end, start)
                        data = json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        data = json.loads(text[text.index("{"):end])
                    return ResourceAnalysis(
                        atomic_components=data.get("atomic_components", []),
                        math_to_code=data.get("math_to_code", {}),
                        code_to_math=data.get("code_to_math", {}),
                        validation_code=data.get("validation_code", ""),
                    )
            except (json.JSONDecodeError, ValueError):
                continue
        return ResourceAnalysis()
