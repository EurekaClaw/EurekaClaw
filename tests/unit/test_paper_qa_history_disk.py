"""Disk-reading contract for GET /api/runs/<id>/paper-qa/history.

Tests the parser directly rather than going through HTTP — the handler
body is ~10 lines of JSONL parsing that we can exercise by copying its
shape. When server.py grows a dedicated helper we'll import it here.
"""

import json
from pathlib import Path


def _read_history(history_file: Path) -> list[dict]:
    """Mirrors the JSONL parser in the GET /api/runs/<id>/paper-qa/history handler in server.py. Keep in sync."""
    messages: list[dict] = []
    if not history_file.exists():
        return messages
    text = history_file.read_text(encoding="utf-8").strip()
    if not text:
        return messages
    for line in text.split("\n"):
        if not line.strip():
            continue
        try:
            messages.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return messages


def test_missing_file_returns_empty(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    assert _read_history(history_file) == []


def test_empty_file_returns_empty(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text("", encoding="utf-8")
    assert _read_history(history_file) == []


def test_valid_jsonl_parses_all_lines(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text(
        json.dumps({"role": "user", "content": "q1"}) + "\n"
        + json.dumps({"role": "assistant", "content": "a1"}) + "\n",
        encoding="utf-8",
    )
    msgs = _read_history(history_file)
    assert len(msgs) == 2
    assert msgs[0]["role"] == "user"
    assert msgs[1]["content"] == "a1"


def test_malformed_line_is_skipped(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text(
        json.dumps({"role": "user", "content": "ok"}) + "\n"
        + "{not valid json\n"
        + json.dumps({"role": "assistant", "content": "also ok"}) + "\n",
        encoding="utf-8",
    )
    msgs = _read_history(history_file)
    assert len(msgs) == 2
    assert msgs[0]["content"] == "ok"
    assert msgs[1]["content"] == "also ok"


def test_blank_lines_between_entries_are_skipped(tmp_path):
    history_file = tmp_path / "paper_qa_history.jsonl"
    history_file.write_text(
        json.dumps({"role": "user", "content": "q"}) + "\n\n\n"
        + json.dumps({"role": "assistant", "content": "a"}) + "\n",
        encoding="utf-8",
    )
    msgs = _read_history(history_file)
    assert len(msgs) == 2
