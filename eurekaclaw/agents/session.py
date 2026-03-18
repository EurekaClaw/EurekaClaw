"""AgentSession — context window management and conversation history."""

from __future__ import annotations

from typing import Any


class AgentSession:
    """Manages the rolling conversation history for an agent's context window."""

    def __init__(self, max_tokens: int = 180_000) -> None:
        self.max_tokens = max_tokens
        self._messages: list[dict[str, Any]] = []
        self._token_count: int = 0

    def add_user(self, content: str) -> None:
        self._messages.append({"role": "user", "content": content})

    def add_assistant(self, content: str | list[dict[str, Any]]) -> None:
        """Add an assistant turn. Content may be a plain string or a list of
        serialized content blocks (required when the turn contains tool_use)."""
        self._messages.append({"role": "assistant", "content": content})

    def add_tool_result(self, tool_use_id: str, content: str) -> None:
        self._messages.append({
            "role": "user",
            "content": [{"type": "tool_result", "tool_use_id": tool_use_id, "content": content}],
        })

    def get_messages(self) -> list[dict[str, Any]]:
        return list(self._messages)

    def clear(self) -> None:
        self._messages.clear()
        self._token_count = 0

    def trim_to_fit(self, max_messages: int = 40) -> None:
        """Keep only the most recent max_messages to avoid context overflow."""
        if len(self._messages) > max_messages:
            # Always keep the first user message as context anchor
            self._messages = self._messages[:1] + self._messages[-(max_messages - 1):]

    def __len__(self) -> int:
        return len(self._messages)
