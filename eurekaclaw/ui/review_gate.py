"""Thread-safe gate registry for interactive UI pipeline gates.

Pipeline threads call ``register_*`` before blocking, then ``wait_*`` to
block until the frontend submits a decision via the API.  The server calls
``submit_*`` to unblock the thread.  After the session ends,
``unregister_all`` cleans up.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Decision types
# ---------------------------------------------------------------------------

@dataclass
class SurveyDecision:
    paper_ids: list[str] = field(default_factory=list)


@dataclass
class DirectionDecision:
    direction: str = ""


@dataclass
class TheoryDecision:
    approved: bool = True
    lemma_id: str = ""
    reason: str = ""


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

@dataclass
class _GateEntry:
    event: threading.Event = field(default_factory=threading.Event)
    decision: object = None


_lock = threading.Lock()
_survey: dict[str, _GateEntry] = {}
_direction: dict[str, _GateEntry] = {}
_theory: dict[str, _GateEntry] = {}


# ── Survey ───────────────────────────────────────────────────────────────────

def register_survey(session_id: str) -> None:
    with _lock:
        _survey[session_id] = _GateEntry()


def is_survey_waiting(session_id: str) -> bool:
    with _lock:
        return session_id in _survey


def wait_survey(session_id: str, timeout: float = 3600.0) -> SurveyDecision:
    with _lock:
        entry = _survey.get(session_id)
    if entry is None:
        return SurveyDecision()
    entry.event.wait(timeout=timeout)
    d = entry.decision
    return d if isinstance(d, SurveyDecision) else SurveyDecision()


def submit_survey(session_id: str, paper_ids: list[str]) -> bool:
    with _lock:
        entry = _survey.get(session_id)
    if entry is None:
        return False
    entry.decision = SurveyDecision(paper_ids=paper_ids)
    entry.event.set()
    return True


# ── Direction ─────────────────────────────────────────────────────────────────

def register_direction(session_id: str) -> None:
    with _lock:
        _direction[session_id] = _GateEntry()


def is_direction_waiting(session_id: str) -> bool:
    with _lock:
        return session_id in _direction


def wait_direction(session_id: str, timeout: float = 3600.0) -> DirectionDecision | None:
    with _lock:
        entry = _direction.get(session_id)
    if entry is None:
        return None
    entry.event.wait(timeout=timeout)
    d = entry.decision
    return d if isinstance(d, DirectionDecision) else None


def submit_direction(session_id: str, direction: str) -> bool:
    with _lock:
        entry = _direction.get(session_id)
    if entry is None:
        return False
    entry.decision = DirectionDecision(direction=direction)
    entry.event.set()
    return True


# ── Theory ───────────────────────────────────────────────────────────────────

def register_theory(session_id: str) -> None:
    with _lock:
        _theory[session_id] = _GateEntry()


def is_theory_waiting(session_id: str) -> bool:
    with _lock:
        return session_id in _theory


def wait_theory(session_id: str, timeout: float = 3600.0) -> TheoryDecision:
    with _lock:
        entry = _theory.get(session_id)
    if entry is None:
        return TheoryDecision(approved=True)
    entry.event.wait(timeout=timeout)
    d = entry.decision
    return d if isinstance(d, TheoryDecision) else TheoryDecision(approved=True)


def submit_theory(session_id: str, decision: TheoryDecision) -> bool:
    with _lock:
        entry = _theory.get(session_id)
    if entry is None:
        return False
    entry.event.clear()
    entry.decision = decision
    entry.event.set()
    return True


def reset_theory(session_id: str) -> None:
    """Re-arm the theory gate for another review round."""
    with _lock:
        if session_id in _theory:
            _theory[session_id] = _GateEntry()


# ── Cleanup ───────────────────────────────────────────────────────────────────

def unregister_all(session_id: str) -> None:
    with _lock:
        _survey.pop(session_id, None)
        _direction.pop(session_id, None)
        _theory.pop(session_id, None)
