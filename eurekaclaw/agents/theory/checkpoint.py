"""ProofCheckpoint — pause/resume support for the YAML proof pipeline."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.types.artifacts import TheoryState

logger = logging.getLogger(__name__)

_PAUSE_FLAG = "pause.flag"
_CHECKPOINT_FILE = "checkpoint.json"


class ProofPausedException(Exception):
    """Raised when a pause flag is detected mid-pipeline.

    The pipeline serialises its state before raising this exception so that
    a subsequent ``eurekaclaw resume <session_id>`` can continue from the
    exact stage boundary where execution stopped.
    """

    def __init__(self, session_id: str, stage_name: str) -> None:
        self.session_id = session_id
        self.stage_name = stage_name
        super().__init__(
            f"Proof paused at stage '{stage_name}' for session '{session_id}'. "
            f"Resume with: eurekaclaw resume {session_id}"
        )


class ProofCheckpoint:
    """Manages pause flags and checkpoint serialisation for a single session.

    Directory layout::

        ~/.eurekaclaw/sessions/<session_id>/
            pause.flag       — touch this file to request a pause
            checkpoint.json  — written on pause, deleted on resume
    """

    def __init__(self, session_id: str) -> None:
        self.session_id = session_id
        self._dir = settings.eurekaclaw_dir / "sessions" / session_id
        self._pause_flag = self._dir / _PAUSE_FLAG
        self._checkpoint = self._dir / _CHECKPOINT_FILE

    # ------------------------------------------------------------------
    # Pause flag
    # ------------------------------------------------------------------

    def request_pause(self) -> None:
        """Write the pause flag file to request a graceful stop."""
        self._dir.mkdir(parents=True, exist_ok=True)
        self._pause_flag.touch()
        logger.info("Pause flag written for session %s", self.session_id)

    def is_pause_requested(self) -> bool:
        """Return True if the pause flag file exists."""
        return self._pause_flag.exists()

    def clear_pause_flag(self) -> None:
        """Remove the pause flag (called on successful resume)."""
        try:
            self._pause_flag.unlink(missing_ok=True)
        except OSError as e:
            logger.warning("Could not remove pause flag: %s", e)

    # ------------------------------------------------------------------
    # Checkpoint existence
    # ------------------------------------------------------------------

    def exists(self) -> bool:
        """Return True if a saved checkpoint is available."""
        return self._checkpoint.exists()

    # ------------------------------------------------------------------
    # Save / load
    # ------------------------------------------------------------------

    def save(
        self,
        state: TheoryState,
        *,
        next_stage: str,
        outer_iter: int,
        current_spec: list[dict[str, Any]],
        original_spec: list[dict[str, Any]],
        domain: str = "",
        research_brief_json: str = "{}",
    ) -> None:
        """Serialise *state* and pipeline position to disk.

        Args:
            state:               Current TheoryState to persist.
            next_stage:          Name of the stage that should run next on resume.
            outer_iter:          Current outer iteration index.
            current_spec:        Remaining stage specs for the current iteration.
            original_spec:       Full original stage spec list.
            domain:              Research domain string.
            research_brief_json: JSON-serialised ResearchBrief (may be "{}").
        """
        self._dir.mkdir(parents=True, exist_ok=True)
        payload = {
            "session_id": self.session_id,
            "next_stage": next_stage,
            "outer_iter": outer_iter,
            "current_spec": current_spec,
            "original_spec": original_spec,
            "domain": domain,
            "research_brief_json": research_brief_json,
            "theory_state": json.loads(state.model_dump_json()),
        }
        self._checkpoint.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        logger.info(
            "Checkpoint saved: session=%s stage='%s' outer_iter=%d",
            self.session_id, next_stage, outer_iter,
        )

    def load(self) -> tuple[TheoryState, dict[str, Any]]:
        """Load a previously saved checkpoint.

        Returns:
            A ``(TheoryState, meta)`` tuple where *meta* contains:
            ``next_stage``, ``outer_iter``, ``current_spec``,
            ``original_spec``, ``domain``, ``research_brief_json``.

        Raises:
            FileNotFoundError: if no checkpoint file exists.
            ValueError: if the checkpoint JSON is malformed.
        """
        if not self._checkpoint.exists():
            raise FileNotFoundError(
                f"No checkpoint found for session '{self.session_id}' "
                f"at {self._checkpoint}"
            )
        try:
            payload = json.loads(self._checkpoint.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Malformed checkpoint file: {exc}") from exc

        state = TheoryState.model_validate(payload["theory_state"])
        meta: dict[str, Any] = {
            "next_stage": payload["next_stage"],
            "outer_iter": payload["outer_iter"],
            "current_spec": payload["current_spec"],
            "original_spec": payload["original_spec"],
            "domain": payload.get("domain", ""),
            "research_brief_json": payload.get("research_brief_json", "{}"),
        }
        logger.info(
            "Checkpoint loaded: session=%s stage='%s' outer_iter=%d",
            self.session_id, meta["next_stage"], meta["outer_iter"],
        )
        return state, meta

    def clear(self) -> None:
        """Delete the checkpoint file (called after a successful resume completes)."""
        try:
            self._checkpoint.unlink(missing_ok=True)
        except OSError as e:
            logger.warning("Could not remove checkpoint file: %s", e)
