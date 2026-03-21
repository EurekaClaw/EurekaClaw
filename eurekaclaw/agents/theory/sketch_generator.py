"""ProofSketchGenerator — rapid high-level proof outline before the full pipeline.

Called once at the CLI level before the expensive survey/theory pipeline starts.
The sketch is shown to the user who can approve (→ run full pipeline) or reject
with a reason (→ regenerate sketch up to MAX_ROUNDS times).
"""

from __future__ import annotations

import logging

from eurekaclaw.config import settings
from eurekaclaw.llm import LLMClient, create_client

logger = logging.getLogger(__name__)

MAX_ROUNDS = 3

_SKETCH_SYSTEM = """\
You are a world-class mathematician and theoretical computer scientist.
Given a conjecture, produce a concise high-level proof sketch — the kind you
would write on a whiteboard before diving into details.

The sketch must:
1. Name 3-6 key lemmas or proof steps (no formal notation required)
2. State the key technique/idea for each step in one sentence
3. Note any non-trivial step or potential difficulty
4. End with a brief "Overall strategy" sentence

Keep the whole sketch under 300 words. Do NOT write a full proof.
Do NOT use heavy LaTeX — plain math notation is fine.
"""

_SKETCH_USER = """\
Conjecture: {conjecture}
Domain: {domain}

Generate the proof sketch.
"""

_REFINE_USER = """\
Conjecture: {conjecture}
Domain: {domain}

Previous sketch:
{previous_sketch}

User feedback: {feedback}

Revise the sketch addressing the feedback above.
"""


class ProofSketchGenerator:
    """Generate (and optionally refine) a proof sketch via a single LLM call."""

    def __init__(self, client: LLMClient | None = None) -> None:
        self._client = client or create_client()

    async def generate(self, conjecture: str, domain: str) -> str:
        user_msg = _SKETCH_USER.format(conjecture=conjecture, domain=domain or "mathematics")
        response = await self._client.messages.create(
            model=settings.eurekaclaw_model,
            system=_SKETCH_SYSTEM,
            messages=[{"role": "user", "content": user_msg}],
            max_tokens=600,
        )
        return response.content[0].text.strip()

    async def refine(self, conjecture: str, domain: str, previous: str, feedback: str) -> str:
        user_msg = _REFINE_USER.format(
            conjecture=conjecture,
            domain=domain or "mathematics",
            previous_sketch=previous,
            feedback=feedback,
        )
        response = await self._client.messages.create(
            model=settings.eurekaclaw_model,
            system=_SKETCH_SYSTEM,
            messages=[{"role": "user", "content": user_msg}],
            max_tokens=600,
        )
        return response.content[0].text.strip()
