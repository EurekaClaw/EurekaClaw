"""Lightweight UI server for the EurekaClaw control center."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
import threading
import uuid
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import urlparse

if TYPE_CHECKING:
    from eurekaclaw.knowledge_bus.bus import KnowledgeBus
    from eurekaclaw.types.artifacts import ResearchBrief
    from eurekaclaw.types.tasks import TaskPipeline

import subprocess as _subprocess
import sys as _sys

from eurekaclaw.ccproxy_manager import maybe_start_ccproxy, stop_ccproxy, is_ccproxy_available, check_ccproxy_auth, _oauth_install_hint
from eurekaclaw.config import settings
from eurekaclaw.console import close_ui_html_sink, register_ui_html_sink
from eurekaclaw.llm import create_client
from eurekaclaw.main import (
    EurekaSession,
    save_artifacts,
    save_console_html_artifact,
    _compile_pdf,
    _copy_template_assets,
)
from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.types.tasks import InputSpec, ResearchOutput, TaskStatus
from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
from eurekaclaw.orchestrator.paper_qa_handler import PaperQAHandler
from eurekaclaw.ui.constants import REWRITE_MARKER_PREFIX

logger = logging.getLogger(__name__)

_ROOT_DIR = Path(__file__).resolve().parents[2]
_FRONTEND_DIR = Path(__file__).resolve().parent / "static"
_DEV_FRONTEND_DIR = _ROOT_DIR / "frontend"
_ENV_PATH = _ROOT_DIR / ".env"
_UI_LAUNCH_DIR = _ROOT_DIR / "launch_from_ui"

_CONFIG_FIELDS: dict[str, str] = {
    "llm_backend": "LLM_BACKEND",
    "anthropic_auth_mode": "ANTHROPIC_AUTH_MODE",
    "anthropic_api_key": "ANTHROPIC_API_KEY",
    "eurekaclaw_model": "EUREKACLAW_MODEL",
    "eurekaclaw_fast_model": "EUREKACLAW_FAST_MODEL",
    "openai_compat_base_url": "OPENAI_COMPAT_BASE_URL",
    "openai_compat_api_key": "OPENAI_COMPAT_API_KEY",
    "openai_compat_model": "OPENAI_COMPAT_MODEL",
    "minimax_api_key": "MINIMAX_API_KEY",
    "minimax_model": "MINIMAX_MODEL",
    "codex_auth_mode": "CODEX_AUTH_MODE",
    "codex_model": "CODEX_MODEL",
    "eurekaclaw_mode": "EUREKACLAW_MODE",
    "gate_mode": "GATE_MODE",
    "experiment_mode": "EXPERIMENT_MODE",
    "ccproxy_port": "CCPROXY_PORT",
    "theory_pipeline": "THEORY_PIPELINE",
    "theory_max_iterations": "THEORY_MAX_ITERATIONS",
    "auto_verify_confidence": "AUTO_VERIFY_CONFIDENCE",
    "verifier_pass_confidence": "VERIFIER_PASS_CONFIDENCE",
    "output_format": "OUTPUT_FORMAT",
    "paper_reader_use_pdf": "PAPER_READER_USE_PDF",
    "paper_reader_abstract_papers": "PAPER_READER_ABSTRACT_PAPERS",
    "paper_reader_pdf_papers": "PAPER_READER_PDF_PAPERS",
    "eurekaclaw_dir": "EUREKACLAW_DIR",
    # Token limits
    "max_tokens_agent": "MAX_TOKENS_AGENT",
    "max_tokens_prover": "MAX_TOKENS_PROVER",
    "max_tokens_planner": "MAX_TOKENS_PLANNER",
    "max_tokens_decomposer": "MAX_TOKENS_DECOMPOSER",
    "max_tokens_assembler": "MAX_TOKENS_ASSEMBLER",
    "max_tokens_formalizer": "MAX_TOKENS_FORMALIZER",
    "max_tokens_crystallizer": "MAX_TOKENS_CRYSTALLIZER",
    "max_tokens_architect": "MAX_TOKENS_ARCHITECT",
    "max_tokens_analyst": "MAX_TOKENS_ANALYST",
    "max_tokens_sketch": "MAX_TOKENS_SKETCH",
    "max_tokens_verifier": "MAX_TOKENS_VERIFIER",
    "max_tokens_compress": "MAX_TOKENS_COMPRESS",
}


@dataclass
class SessionRun:
    """Tracks a running or completed session for UI polling."""

    run_id: str
    input_spec: InputSpec
    name: str = ""
    # Statuses: queued → running → pausing → paused → resuming → running → completed
    #           any of the above → failed
    status: str = "queued"
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    started_at: datetime | None = None
    completed_at: datetime | None = None
    paused_at: datetime | None = None
    pause_requested_at: datetime | None = None  # set when status → "pausing"
    paused_stage: str = ""                       # stage name where proof stopped
    theory_feedback: str = ""                    # user guidance injected on next theory resume
    error: str = ""
    error_category: str = ""  # "retryable" | "fatal" | "" (not failed)
    result: ResearchOutput | None = None
    eureka_session: EurekaSession | None = None
    eureka_session_id: str = ""
    output_summary: dict[str, Any] = field(default_factory=dict)
    output_dir: str = ""


def _serialize_value(value: Any) -> Any:
    """Convert Pydantic models and datetimes into JSON-safe data."""
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json")
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(k): _serialize_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_serialize_value(item) for item in value]
    return value


def _load_saved_run_artifacts(run: SessionRun) -> tuple[Any | None, Any | None]:
    """Best-effort load of persisted survey artifacts for a UI run.

    Order:
    1. Current in-memory bus (caller should prefer this directly when available)
    2. UI output_dir (paper artifacts)
    3. ~/.eurekaclaw/runs/<session_id>/ (KnowledgeBus.persist artifacts)
    """
    from eurekaclaw.types.artifacts import Bibliography, ResearchBrief

    search_dirs: list[Path] = []
    if run.output_dir:
        search_dirs.append(Path(run.output_dir))
    if run.eureka_session_id:
        search_dirs.append(settings.runs_dir / run.eureka_session_id)

    brief = None
    bibliography = None
    for base in search_dirs:
        if not base.exists():
            continue
        if brief is None:
            p = base / "research_brief.json"
            if p.exists():
                try:
                    brief = ResearchBrief.model_validate_json(p.read_text(encoding="utf-8"))
                except Exception:
                    logger.warning("Failed to load research_brief from %s", p, exc_info=True)
        if bibliography is None:
            p = base / "bibliography.json"
            if p.exists():
                try:
                    bibliography = Bibliography.model_validate_json(p.read_text(encoding="utf-8"))
                except Exception:
                    logger.warning("Failed to load bibliography from %s", p, exc_info=True)
        if brief is not None and bibliography is not None:
            break

    if brief is not None and bibliography is None:
        legacy_dir = settings.runs_dir / brief.session_id
        p = legacy_dir / "bibliography.json"
        if p.exists():
            try:
                from eurekaclaw.types.artifacts import Bibliography

                bibliography = Bibliography.model_validate_json(p.read_text(encoding="utf-8"))
            except Exception:
                logger.warning("Failed to load bibliography from %s", p, exc_info=True)

    return brief, bibliography


def _load_saved_theory_state(run: SessionRun) -> Any | None:
    """Best-effort load of persisted TheoryState for a UI run."""
    from eurekaclaw.types.artifacts import TheoryState

    search_dirs: list[Path] = []
    if run.output_dir:
        search_dirs.append(Path(run.output_dir))
    if run.eureka_session_id:
        search_dirs.append(settings.runs_dir / run.eureka_session_id)

    for base in search_dirs:
        if not base.exists():
            continue
        p = base / "theory_state.json"
        if not p.exists():
            continue
        try:
            return TheoryState.model_validate_json(p.read_text(encoding="utf-8"))
        except Exception:
            logger.warning("Failed to load theory_state from %s", p, exc_info=True)
    return None


def _seed_output_dir_with_survey_artifacts(
    output_dir: str | Path,
    *,
    brief: Any | None,
    bibliography: Any | None,
) -> None:
    """Persist restartable survey artifacts into the UI run directory early."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    if brief is not None:
        try:
            out.joinpath("research_brief.json").write_text(
                brief.model_dump_json(indent=2),
                encoding="utf-8",
            )
        except Exception:
            logger.warning("Failed to seed research_brief.json into %s", out, exc_info=True)
    if bibliography is not None:
        try:
            out.joinpath("bibliography.json").write_text(
                bibliography.model_dump_json(indent=2),
                encoding="utf-8",
            )
        except Exception:
            logger.warning("Failed to seed bibliography.json into %s", out, exc_info=True)


def _seed_output_dir_with_theory_state(
    output_dir: str | Path,
    *,
    theory_state: Any | None,
) -> None:
    """Persist restartable theory artifacts into the UI run directory early."""
    if theory_state is None:
        return
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    try:
        out.joinpath("theory_state.json").write_text(
            theory_state.model_dump_json(indent=2),
            encoding="utf-8",
        )
    except Exception:
        logger.warning("Failed to seed theory_state.json into %s", out, exc_info=True)


def _write_json_artifact(path: Path, value: Any) -> None:
    """Best-effort JSON persistence for a bus artifact."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if hasattr(value, "model_dump_json"):
        path.write_text(value.model_dump_json(indent=2), encoding="utf-8")
    else:
        path.write_text(json.dumps(_serialize_value(value), indent=2), encoding="utf-8")


def _attach_run_artifact_persistence(run: SessionRun, session: EurekaSession) -> None:
    """Persist key bus artifacts incrementally while the UI run is in progress."""
    out_dir = Path(run.output_dir)
    bus = session.bus

    def _persist_named(name: str):
        def _inner(value: Any) -> None:
            try:
                _write_json_artifact(out_dir / f"{name}.json", value)
            except Exception:
                logger.warning("Failed to persist %s for run %s", name, run.run_id, exc_info=True)
        return _inner

    bus.subscribe("research_brief", _persist_named("research_brief"))
    bus.subscribe("bibliography", _persist_named("bibliography"))
    bus.subscribe("theory_state", _persist_named("theory_state"))
    bus.subscribe("experiment_result", _persist_named("experiment_result"))
    bus.subscribe("pipeline", _persist_named("pipeline"))


# Substrings that indicate transient/retryable LLM or network errors.
_RETRYABLE_ERROR_HINTS = (
    "429", "rate limit", "rate_limit",
    "overloaded", "529",
    "timeout", "timed out",
    "service unavailable", "500", "502", "503",
    "internal server error",
    "connection", "reset by peer", "broken pipe",
    "empty content",
)

_THEORY_SUBSTAGES = (
    "paper_reader",
    "gap_analyst",
    "proof_architect",
    "lemma_developer",
    "assembler",
    "theorem_crystallizer",
    "consistency_checker",
)


def _classify_error(exc: Exception) -> str:
    """Return 'retryable' for transient LLM/network errors, 'fatal' otherwise."""
    err_str = str(exc).lower()
    if any(hint in err_str for hint in _RETRYABLE_ERROR_HINTS):
        return "retryable"
    return "fatal"


def _capability_status(available: bool, detail: str, *, optional: bool = False) -> dict[str, str]:
    if available:
        return {"status": "available", "detail": detail}
    if optional:
        return {"status": "optional", "detail": detail}
    return {"status": "missing", "detail": detail}


def _infer_capabilities() -> dict[str, dict[str, str]]:
    """Inspect the local environment for the UI status surface."""
    python_detail = f"Python {os.sys.version_info.major}.{os.sys.version_info.minor}.{os.sys.version_info.micro}"
    model_ready = bool(
        settings.anthropic_api_key
        or settings.openai_compat_api_key
        or settings.anthropic_auth_mode == "oauth"
    )
    return {
        "python": _capability_status(True, python_detail),
        "package_install": _capability_status(True, "Repository checkout available"),
        "model_access": _capability_status(
            model_ready,
            "Model credentials configured" if model_ready else "No model credentials configured",
        ),
        "lean4": _capability_status(
            shutil.which(settings.lean4_bin) is not None,
            f"{settings.lean4_bin} found in PATH" if shutil.which(settings.lean4_bin) else "Lean4 binary not found",
            optional=True,
        ),
        "latex": _capability_status(
            shutil.which(settings.latex_bin) is not None,
            f"{settings.latex_bin} found in PATH" if shutil.which(settings.latex_bin) else "LaTeX binary not found",
            optional=True,
        ),
        "docker": _capability_status(
            shutil.which("docker") is not None,
            "Docker available" if shutil.which("docker") else "Docker not found",
            optional=True,
        ),
        "skills_dir": _capability_status(
            settings.skills_dir.exists(),
            str(settings.skills_dir),
            optional=True,
        ),
    }


def _load_env_lines(env_path: Path) -> list[str]:
    if not env_path.exists():
        return []
    return env_path.read_text().splitlines()


def _write_env_updates(env_path: Path, updates: dict[str, str]) -> None:
    """Update or append selected .env keys without dropping unrelated lines."""
    lines = _load_env_lines(env_path)
    index_map = {
        line.split("=", 1)[0]: idx
        for idx, line in enumerate(lines)
        if "=" in line and not line.lstrip().startswith("#")
    }

    for key, value in updates.items():
        rendered = f"{key}={value}"
        if key in index_map:
            lines[index_map[key]] = rendered
        else:
            lines.append(rendered)

    env_path.write_text("\n".join(lines) + ("\n" if lines else ""))


class UIServerState:
    """In-memory state for UI sessions and configuration."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.runs: dict[str, SessionRun] = {}
        self._load_persisted_runs()

    # ── Persistence helpers ──────────────────────────────────────────────────

    def _sessions_dir(self) -> Path:
        d = settings.eurekaclaw_dir / "ui_sessions"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _persist_run(self, run: SessionRun) -> None:
        """Write run metadata to disk so sessions survive server restarts."""
        try:
            data: dict[str, Any] = {
                "run_id": run.run_id,
                "name": run.name,
                "status": run.status,
                "error": run.error,
                "error_category": run.error_category,
                "eureka_session_id": run.eureka_session_id,
                "created_at": run.created_at.isoformat(),
                "updated_at": run.updated_at.isoformat(),
                "started_at": run.started_at.isoformat() if run.started_at else None,
                "completed_at": run.completed_at.isoformat() if run.completed_at else None,
                "paused_at": run.paused_at.isoformat() if run.paused_at else None,
                "pause_requested_at": run.pause_requested_at.isoformat() if run.pause_requested_at else None,
                "paused_stage": run.paused_stage,
                "theory_feedback": run.theory_feedback,
                "input_spec": _serialize_value(run.input_spec),
                "output_dir": run.output_dir,
                "output_summary": _serialize_value(run.output_summary),
            }
            path = self._sessions_dir() / f"{run.run_id}.json"
            path.write_text(json.dumps(data, indent=2))
        except Exception:
            logger.warning("Failed to persist run %s", run.run_id, exc_info=True)

    def _load_persisted_runs(self) -> None:
        """Load previously persisted sessions from disk on startup."""
        sessions_dir = settings.eurekaclaw_dir / "ui_sessions"
        if not sessions_dir.exists():
            return
        for path in sorted(sessions_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text())
                input_spec = InputSpec.model_validate(data.get("input_spec", {}))
                run = SessionRun(
                    run_id=data["run_id"],
                    input_spec=input_spec,
                    name=data.get("name", ""),
                    status=data.get("status", "failed"),
                    error=data.get("error", ""),
                    error_category=data.get("error_category", ""),
                    eureka_session_id=data.get("eureka_session_id", ""),
                    paused_stage=data.get("paused_stage", ""),
                    theory_feedback=data.get("theory_feedback", ""),
                    output_dir=data.get("output_dir", ""),
                    output_summary=data.get("output_summary", {}),
                )
                for ts_field in ("created_at", "updated_at", "started_at", "completed_at",
                                 "paused_at", "pause_requested_at"):
                    raw = data.get(ts_field)
                    if raw:
                        try:
                            setattr(run, ts_field, datetime.fromisoformat(raw))
                        except ValueError:
                            pass
                # Transient statuses that cannot survive a server restart
                if run.status in ("running", "queued", "pausing", "resuming"):
                    run.status = "failed"
                    run.error = "Session interrupted by a server restart."
                    run.error_category = "retryable"
                self.runs[run.run_id] = run
            except Exception:
                logger.warning("Failed to load persisted run from %s", path, exc_info=True)

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def create_run(self, input_spec: InputSpec) -> SessionRun:
        run = SessionRun(run_id=str(uuid.uuid4()), input_spec=input_spec)
        out_dir = _ROOT_DIR / "results" / run.run_id
        out_dir.mkdir(parents=True, exist_ok=True)
        run.output_dir = str(out_dir)
        with self._lock:
            self.runs[run.run_id] = run
        self._persist_run(run)
        return run

    def delete_run(self, run_id: str) -> dict[str, Any]:
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status in ("running", "queued"):
            return {"error": "Cannot delete a running session — pause or wait for it to finish first"}
        with self._lock:
            self.runs.pop(run_id, None)
        path = self._sessions_dir() / f"{run_id}.json"
        try:
            path.unlink(missing_ok=True)
        except Exception:
            logger.warning("Failed to remove persisted run file %s", path)
        return {"ok": True, "run_id": run_id}

    def rename_run(self, run_id: str, name: str) -> dict[str, Any]:
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        run.name = name.strip()[:80]
        run.updated_at = datetime.utcnow()
        self._persist_run(run)
        return {"ok": True, "run_id": run_id, "name": run.name}

    def restart_run(self, run_id: str) -> dict[str, Any]:
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status in ("running", "queued"):
            return {"error": f"Cannot restart a {run.status} session"}
        new_run = self.create_run(run.input_spec)
        new_run.name = run.name  # carry the custom name if any
        self._persist_run(new_run)
        self.start_run(new_run)
        return self.snapshot_run(new_run)

    def rerun_run(self, run_id: str, *, updated_skills: list[str] | None = None) -> dict[str, Any]:
        """Reset the same run in-place and re-execute with the original input_spec.

        If *updated_skills* is provided, the input_spec.selected_skills list
        is replaced so the user can add/remove skills between re-runs.
        """
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status in ("running", "queued"):
            return {"error": f"Cannot re-run a {run.status} session"}
        # Update skills if the frontend sent a new list
        if updated_skills is not None:
            run.input_spec.selected_skills = updated_skills
        # Reset all mutable state, keep run_id, input_spec, name
        run.status = "queued"
        run.created_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        run.started_at = None
        run.completed_at = None
        run.paused_at = None
        run.pause_requested_at = None
        run.paused_stage = ""
        run.theory_feedback = ""
        run.error = ""
        run.result = None
        run.eureka_session = None
        run.eureka_session_id = ""
        run.output_summary = {}
        out_dir = _ROOT_DIR / "results" / run.run_id
        out_dir.mkdir(parents=True, exist_ok=True)
        run.output_dir = str(out_dir)
        self._persist_run(run)
        self.start_run(run)
        return self.snapshot_run(run)

    def _restart_from_stage(
        self,
        run_id: str,
        *,
        start_stage: str,
        theory_substage: str | None = None,
        override_brief: Any | None = None,
        override_bibliography: Any | None = None,
        force_empty_bibliography: bool = False,
        force_no_theory_state: bool = False,
    ) -> dict[str, Any]:
        """Re-execute a run from a later stage using saved survey artifacts.

        ``override_brief`` / ``override_bibliography`` skip artifact loading
        from disk and bus, forcing the restart to use the supplied values.
        ``force_empty_bibliography`` drops any loaded bibliography so
        downstream stages see an empty paper set (used when the user opted
        to continue without papers after a stale survey gate).
        ``force_no_theory_state`` discards any persisted theory state so an
        earlier aborted theory attempt cannot leak into this restart (used
        whenever we resume at a stage before theory).
        """
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status in ("running", "queued"):
            return {"error": f"Cannot restart a {run.status} session from {start_stage}"}
        if theory_substage is not None and theory_substage not in _THEORY_SUBSTAGES:
            return {"error": f"Unknown theory substage: {theory_substage}"}

        brief = override_brief
        bibliography = override_bibliography
        theory_state = None
        if brief is None or (bibliography is None and not force_empty_bibliography):
            if run.eureka_session is not None and run.eureka_session.bus is not None:
                if brief is None:
                    brief = run.eureka_session.bus.get_research_brief()
                if bibliography is None and not force_empty_bibliography:
                    bibliography = run.eureka_session.bus.get_bibliography()
                if not force_no_theory_state:
                    theory_state = run.eureka_session.bus.get_theory_state()

        if brief is None or (bibliography is None and not force_empty_bibliography):
            saved_brief, saved_bib = _load_saved_run_artifacts(run)
            brief = brief or saved_brief
            if not force_empty_bibliography:
                bibliography = bibliography or saved_bib
        if theory_state is None and not force_no_theory_state:
            theory_state = _load_saved_theory_state(run)

        if force_empty_bibliography:
            bibliography = None
        if force_no_theory_state:
            theory_state = None

        if brief is None:
            return {"error": "No saved survey artifacts found — rerun the full session instead"}
        if theory_substage and theory_substage != "paper_reader" and theory_state is None:
            return {"error": f"No saved theory state found — restart from theory or from {theory_substage} is unavailable"}

        run.status = "queued"
        run.created_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        run.started_at = None
        run.completed_at = None
        run.paused_at = None
        run.pause_requested_at = None
        run.paused_stage = ""
        run.theory_feedback = ""
        run.error = ""
        run.error_category = ""
        run.result = None
        run.eureka_session = None
        run.eureka_session_id = ""
        run.output_summary = {"restart_from_stage": start_stage}
        if theory_substage:
            run.output_summary["restart_from_theory_substage"] = theory_substage
        out_dir = _ROOT_DIR / "results" / run.run_id
        out_dir.mkdir(parents=True, exist_ok=True)
        run.output_dir = str(out_dir)
        _seed_output_dir_with_survey_artifacts(
            run.output_dir,
            brief=brief,
            bibliography=bibliography,
        )
        _seed_output_dir_with_theory_state(
            run.output_dir,
            theory_state=theory_state,
        )
        self._persist_run(run)

        thread = threading.Thread(
            target=self._execute_from_stage,
            args=(run.run_id, brief, bibliography, start_stage, theory_state, theory_substage),
            daemon=True,
        )
        thread.start()
        return self.snapshot_run(run)

    def restart_from_ideation(self, run_id: str) -> dict[str, Any]:
        """Re-execute a run starting from ideation, reusing saved survey artifacts."""
        return self._restart_from_stage(run_id, start_stage="ideation")

    def skip_survey_to_ideation(self, run_id: str) -> dict[str, Any]:
        """Skip the survey stage and continue to ideation.

        Called from the survey gate endpoint when the gate is no longer live
        (the orchestrator thread is gone after a server restart or crash) and
        the user clicked "Continue without papers". Always builds a fresh
        research brief from the run's input_spec and forces an empty
        bibliography — any artifacts lingering from prior reruns of this run
        are discarded so ideation starts from a clean slate.
        """
        from eurekaclaw.types.artifacts import ResearchBrief

        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}

        # The gate was reported stale by submit_survey → treat any lingering
        # "running"/"queued" status as an interrupted run so restart proceeds.
        if run.status in ("running", "queued", "pausing", "resuming"):
            run.status = "failed"
            run.error = run.error or "Session interrupted before ideation."
            run.error_category = run.error_category or "retryable"
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

        # Purge any stale bibliography / theory state persisted from a prior
        # attempt so ideation starts from a clean slate (matches the user's
        # "Continue without papers" intent and prevents an earlier theory
        # attempt from bleeding into this fresh restart).
        if run.output_dir:
            out_dir = Path(run.output_dir)
            for stale_name in ("bibliography.json", "theory_state.json"):
                try:
                    out_dir.joinpath(stale_name).unlink(missing_ok=True)
                except Exception:
                    logger.warning(
                        "Failed to clear stale %s in %s",
                        stale_name,
                        run.output_dir,
                        exc_info=True,
                    )

        spec = run.input_spec
        fresh_brief = ResearchBrief(
            session_id=run.eureka_session_id or run.run_id,
            input_mode=spec.mode,
            domain=spec.domain,
            query=spec.query or spec.conjecture or spec.domain,
            conjecture=spec.conjecture,
            selected_skills=spec.selected_skills,
            reference_paper_ids=spec.paper_ids,
        )

        return self._restart_from_stage(
            run_id,
            start_stage="ideation",
            override_brief=fresh_brief,
            override_bibliography=None,
            force_empty_bibliography=True,
            force_no_theory_state=True,
        )

    def restart_from_theory(self, run_id: str) -> dict[str, Any]:
        """Re-execute a run starting from theory, reusing saved ideation artifacts."""
        return self._restart_from_stage(run_id, start_stage="theory")

    def restart_from_theory_substage(self, run_id: str, theory_substage: str) -> dict[str, Any]:
        """Re-execute a run starting from a theory substage."""
        return self._restart_from_stage(
            run_id,
            start_stage="theory",
            theory_substage=theory_substage,
        )

    def get_run(self, run_id: str) -> SessionRun | None:
        with self._lock:
            return self.runs.get(run_id)

    def list_runs(self) -> list[SessionRun]:
        with self._lock:
            return sorted(self.runs.values(), key=lambda run: run.created_at, reverse=True)

    def start_run(self, run: SessionRun) -> None:
        thread = threading.Thread(target=self._execute_run, args=(run.run_id,), daemon=True)
        thread.start()

    def pause_run(self, run_id: str) -> dict[str, Any]:
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status not in ("running",):
            return {"error": f"Run is not running (status: {run.status})"}
        if not run.eureka_session_id:
            return {"error": "No active theory session to pause"}
        from eurekaclaw.agents.theory.checkpoint import ProofCheckpoint
        cp = ProofCheckpoint(run.eureka_session_id)
        cp.request_pause()
        # Immediately reflect the intermediate state so the frontend can poll it
        run.status = "pausing"
        run.pause_requested_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        self._persist_run(run)
        return {"ok": True, "session_id": run.eureka_session_id, "status": "pausing"}

    def resume_run(self, run_id: str, feedback: str = "") -> dict[str, Any]:
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        # Allow resume from "paused" (user-initiated) or "failed" (crash with checkpoint)
        if run.status not in ("paused", "failed"):
            return {"error": f"Run is not paused or failed (status: {run.status})"}
        if not run.eureka_session_id:
            return {"error": "No checkpoint session ID found"}
        # For failed runs, verify a checkpoint actually exists before attempting resume
        if run.status == "failed":
            from eurekaclaw.agents.theory.checkpoint import ProofCheckpoint
            if not ProofCheckpoint(run.eureka_session_id).exists():
                return {"error": "No checkpoint available — use restart instead"}
        # Store user guidance to be injected into the theory context on resume
        if feedback:
            run.theory_feedback = feedback.strip()[:2000]
        # Clear previous error state and transition to "resuming"
        run.error = ""
        run.error_category = ""
        run.status = "resuming"
        run.updated_at = datetime.utcnow()
        self._persist_run(run)
        thread = threading.Thread(target=self._execute_resume, args=(run_id,), daemon=True)
        thread.start()
        return {"ok": True, "session_id": run.eureka_session_id, "status": "resuming"}

    def _execute_resume(self, run_id: str) -> None:
        from eurekaclaw.agents.theory.checkpoint import ProofCheckpoint, ProofPausedException
        from eurekaclaw.agents.theory.inner_loop_yaml import TheoryInnerLoopYaml
        from eurekaclaw.memory.manager import MemoryManager
        from eurekaclaw.skills.injector import SkillInjector
        from eurekaclaw.skills.registry import SkillRegistry

        run = self.get_run(run_id)
        if run is None:
            return

        run.status = "running"
        run.paused_at = None
        run.pause_requested_at = None
        run.paused_stage = ""
        run.updated_at = datetime.utcnow()
        self._persist_run(run)
        launch_html_path = _UI_LAUNCH_DIR / f"{run.run_id}.html"
        register_ui_html_sink(launch_html_path)

        try:
            session = run.eureka_session
            if session is None:
                raise ValueError("Session object not available for resume")

            session_id = run.eureka_session_id
            cp = ProofCheckpoint(session_id)
            cp.clear_pause_flag()

            if not cp._checkpoint.exists():
                # Paused/failed before theory stage — re-run the full pipeline
                # from scratch.  Must inject auth env vars so API calls work.
                config = _config_payload()
                run.status = "running"
                self._persist_run(run)
                loop2 = asyncio.new_event_loop()
                asyncio.set_event_loop(loop2)
                try:
                    with _temporary_auth_env(config):
                        async def _rerun() -> Any:
                            main_task = asyncio.current_task()
                            assert main_task is not None
                            cp3 = ProofCheckpoint(session_id)

                            async def _poll3() -> None:
                                while True:
                                    await asyncio.sleep(1)
                                    if cp3.is_pause_requested() and not main_task.cancelled():
                                        main_task.cancel()
                                        return

                            poll3 = asyncio.create_task(_poll3())
                            try:
                                return await session.run(run.input_spec)
                            except asyncio.CancelledError:
                                pipeline = session.bus.get_pipeline() if session.bus else None
                                stage = "unknown"
                                if pipeline:
                                    from eurekaclaw.types.tasks import TaskStatus
                                    for t in pipeline.tasks:
                                        if t.status == TaskStatus.IN_PROGRESS:
                                            stage = t.name
                                            break
                                raise ProofPausedException(session_id, stage)
                            finally:
                                poll3.cancel()

                        result2 = loop2.run_until_complete(_rerun())
                finally:
                    loop2.close()
                    asyncio.set_event_loop(None)
                run.status = "completed"
                run.output_summary = {"resumed": True, "session_id": session_id}
                return

            state, meta = cp.load()

            # Restore checkpoint theory state into the existing bus (which still has
            # survey / ideation / planning data from the original run).
            session.bus.put_theory_state(state)

            domain = meta.get("domain", "")

            # Inject user guidance if provided via the UI feedback dialog
            if run.theory_feedback:
                domain = domain + f"\n\n[Human guidance for this proof attempt]: {run.theory_feedback}"
                run.theory_feedback = ""   # consume — clear after use
                self._persist_run(run)

            memory = MemoryManager(session_id=session_id)
            skill_injector = SkillInjector(SkillRegistry())
            inner_loop = TheoryInnerLoopYaml(
                bus=session.bus,
                skill_injector=skill_injector,
                memory=memory,
            )

            config = _config_payload()
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                with _temporary_auth_env(config):
                    async def _resume_with_poller() -> Any:
                        main_task = asyncio.current_task()
                        assert main_task is not None
                        cp2 = ProofCheckpoint(session_id)

                        async def _poll() -> None:
                            while True:
                                await asyncio.sleep(1)
                                if cp2.is_pause_requested() and not main_task.cancelled():
                                    main_task.cancel()
                                    return

                        poll = asyncio.create_task(_poll())
                        try:
                            return await inner_loop.run(session_id, domain=domain)
                        except asyncio.CancelledError:
                            from eurekaclaw.agents.theory.checkpoint import ProofPausedException
                            raise ProofPausedException(session_id, "theory")
                        finally:
                            poll.cancel()

                    final_state = loop.run_until_complete(_resume_with_poller())
                    session.bus.put_theory_state(final_state)
            finally:
                loop.close()
                asyncio.set_event_loop(None)

            # Theory completed — run the writer stage to produce the paper.
            pipeline = session.bus.get_pipeline()
            if pipeline:
                from eurekaclaw.types.tasks import TaskStatus as _TS
                writer_task = next(
                    (t for t in pipeline.tasks if t.name == "writer" and t.status != _TS.COMPLETED),
                    None,
                )
                if writer_task:
                    orch = session.orchestrator
                    config = _config_payload()
                    wloop = asyncio.new_event_loop()
                    asyncio.set_event_loop(wloop)
                    try:
                        with _temporary_auth_env(config):
                            async def _run_writer() -> None:
                                writer_task.mark_started()
                                agent = orch.router.resolve(writer_task)
                                result = await agent.execute(writer_task)
                                if not result.failed:
                                    task_outputs = dict(result.output)
                                    if result.text_summary:
                                        task_outputs["text_summary"] = result.text_summary
                                    writer_task.mark_completed(task_outputs)
                                else:
                                    writer_task.mark_failed(result.error)
                            wloop.run_until_complete(_run_writer())
                    finally:
                        wloop.close()
                        asyncio.set_event_loop(None)

            # Collect outputs and save artifacts so PDF compilation works.
            brief = session.bus.get_research_brief()
            if brief:
                orch = session.orchestrator
                result = orch._collect_outputs(brief)
                run.result = result
                out_dir = save_artifacts(result, _ROOT_DIR / "results" / run.run_id)
                save_console_html_artifact(out_dir)
                run.output_dir = str(out_dir)
                run.output_summary = {
                    "latex_paper_length": len(result.latex_paper),
                    "has_theory_state": bool(result.theory_state_json),
                    "output_dir": str(out_dir),
                    "resumed": True,
                }
            else:
                run.output_summary = {"resumed": True, "session_id": session_id}

            run.status = "completed"

        except Exception as exc:
            from eurekaclaw.agents.theory.checkpoint import ProofPausedException  # noqa: F811
            if isinstance(exc, ProofPausedException):
                logger.info("Session %s paused again at stage '%s'", run_id, exc.stage_name)
                run.status = "paused"
                run.paused_at = datetime.utcnow()
                run.paused_stage = exc.stage_name
                run.pause_requested_at = None
                run.error = ""
            else:
                logger.exception("UI session resume failed")
                run.status = "failed"
                run.error = str(exc)
                run.error_category = _classify_error(exc)
        finally:
            close_ui_html_sink()
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

    def _execute_run(self, run_id: str) -> None:
        run = self.get_run(run_id)
        if run is None:
            return

        run.status = "running"
        run.started_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        launch_html_path = _UI_LAUNCH_DIR / f"{run.run_id}.html"
        register_ui_html_sink(launch_html_path)

        try:
            # Pre-flight: verify credentials before spending time initialising agents
            config = _config_payload()
            _preflight_check(config)

            session = EurekaSession()
            run.eureka_session = session
            run.eureka_session_id = session.session_id
            self._persist_run(run)
            _attach_run_artifact_persistence(run, session)

            from eurekaclaw.ui import review_gate as _rg
            _rg.register_survey(session.session_id)
            _rg.register_direction(session.session_id)
            _rg.register_theory(session.session_id)
            _rg.register_paper_qa(session.session_id)

            with _temporary_auth_env(config):
                # asyncio.run() can be unreliable in non-main threads on some
                # Python versions.  Creating an explicit loop is safer.
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    from eurekaclaw.agents.theory.checkpoint import ProofCheckpoint

                    async def _run_with_pause_poller() -> Any:
                        main_task = asyncio.current_task()
                        assert main_task is not None

                        async def _poll() -> None:
                            cp = ProofCheckpoint(session.session_id)
                            while True:
                                await asyncio.sleep(1)
                                if cp.is_pause_requested() and not main_task.cancelled():
                                    main_task.cancel()
                                    return

                        poll = asyncio.create_task(_poll())
                        try:
                            return await session.run(run.input_spec)
                        except asyncio.CancelledError:
                            from eurekaclaw.agents.theory.checkpoint import ProofPausedException
                            # Determine which pipeline stage was active when cancelled
                            pipeline = session.bus.get_pipeline() if session.bus else None
                            stage = "unknown"
                            if pipeline:
                                for t in pipeline.tasks:
                                    from eurekaclaw.types.tasks import TaskStatus
                                    if t.status == TaskStatus.IN_PROGRESS:
                                        stage = t.name
                                        break
                            raise ProofPausedException(session.session_id, stage)
                        finally:
                            poll.cancel()

                    result = loop.run_until_complete(_run_with_pause_poller())
                finally:
                    loop.close()
                    asyncio.set_event_loop(None)

            run.result = result

            # Save artifacts to results/<run_id>/ so files are always on disk.
            out_dir = save_artifacts(result, _ROOT_DIR / "results" / run.run_id)
            save_console_html_artifact(out_dir)
            run.output_dir = str(out_dir)

            run.status = "completed"
            run.output_summary = {
                "latex_paper_length": len(result.latex_paper),
                "has_experiment_result": bool(result.experiment_result_json),
                "has_theory_state": bool(result.theory_state_json),
                "output_dir": str(out_dir),
            }
        except Exception as exc:
            from eurekaclaw.agents.theory.checkpoint import ProofPausedException
            if isinstance(exc, ProofPausedException):
                logger.info("Session %s paused at stage '%s'", run_id, exc.stage_name)
                run.status = "paused"
                run.paused_at = datetime.utcnow()
                run.paused_stage = exc.stage_name
                run.pause_requested_at = None
                run.error = ""
            else:
                logger.exception("UI session run failed")
                run.status = "failed"
                run.error = str(exc)
                run.error_category = _classify_error(exc)
        finally:
            close_ui_html_sink()
            if run.eureka_session_id:
                from eurekaclaw.ui import review_gate as _rg
                _rg.unregister_all(run.eureka_session_id)
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

    def _execute_from_stage(
        self,
        run_id: str,
        brief: Any,
        bibliography: Any,
        start_stage: str,
        theory_state: Any | None = None,
        theory_substage: str | None = None,
    ) -> None:
        run = self.get_run(run_id)
        if run is None:
            return

        run.status = "running"
        run.started_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        launch_html_path = _UI_LAUNCH_DIR / f"{run.run_id}.html"
        register_ui_html_sink(launch_html_path)

        try:
            config = _config_payload()
            _preflight_check(config)

            session = EurekaSession()
            run.eureka_session = session
            run.eureka_session_id = session.session_id
            self._persist_run(run)
            _attach_run_artifact_persistence(run, session)
            session.bus.put_research_brief(brief.model_copy(update={"session_id": session.session_id}))
            if bibliography is not None:
                session.bus.put_bibliography(bibliography.model_copy(update={"session_id": session.session_id}))
            if theory_state is not None:
                session.bus.put_theory_state(theory_state.model_copy(update={"session_id": session.session_id}))

            from eurekaclaw.ui import review_gate as _rg
            _rg.register_survey(session.session_id)
            _rg.register_direction(session.session_id)
            _rg.register_theory(session.session_id)
            _rg.register_paper_qa(session.session_id)

            with _temporary_auth_env(config):
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    async def _resume_from_stage() -> Any:
                        orchestrator = session.orchestrator
                        return await orchestrator.run_from_stage(
                            run.input_spec,
                            brief=brief,
                            start_stage=start_stage,
                            bibliography=bibliography,
                            theory_start_substage=theory_substage,
                        )

                    result = loop.run_until_complete(_resume_from_stage())
                finally:
                    loop.close()
                    asyncio.set_event_loop(None)

            run.result = result
            out_dir = save_artifacts(result, _ROOT_DIR / "results" / run.run_id)
            save_console_html_artifact(out_dir)
            run.output_dir = str(out_dir)
            run.status = "completed"
            run.output_summary = {
                "latex_paper_length": len(result.latex_paper),
                "has_experiment_result": bool(result.experiment_result_json),
                "has_theory_state": bool(result.theory_state_json),
                "output_dir": str(out_dir),
                "restarted_from_stage": start_stage,
                "restarted_from_theory_substage": theory_substage or "",
            }
        except Exception as exc:
            logger.exception("UI session %s restart failed", start_stage)
            run.status = "failed"
            run.error = str(exc)
            run.error_category = _classify_error(exc)
        finally:
            close_ui_html_sink()
            if run.eureka_session_id:
                from eurekaclaw.ui import review_gate as _rg
                _rg.unregister_all(run.eureka_session_id)
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

    def snapshot_run(self, run: SessionRun) -> dict[str, Any]:
        bus = run.eureka_session.bus if run.eureka_session else None
        pipeline = bus.get_pipeline() if bus else None
        # When bus is None (e.g. server restarted after session completed),
        # load the pipeline from the persisted pipeline.json on disk.
        if pipeline is None and run.eureka_session_id:
            from eurekaclaw.types.tasks import TaskPipeline as _TP
            for _search_dir in [
                Path(run.output_dir) if run.output_dir else None,
                settings.runs_dir / run.eureka_session_id,
            ]:
                if _search_dir and (_search_dir / "pipeline.json").is_file():
                    try:
                        pipeline = _TP.model_validate_json(
                            (_search_dir / "pipeline.json").read_text(encoding="utf-8")
                        )
                        break
                    except Exception:
                        pass
        tasks: list[dict[str, Any]] = []
        if pipeline:
            for task in pipeline.tasks:
                tasks.append(
                    {
                        "task_id": task.task_id,
                        "name": task.name,
                        "agent_role": task.agent_role,
                        "status": task.status.value if isinstance(task.status, TaskStatus) else str(task.status),
                        "description": task.description,
                        "started_at": task.started_at.isoformat() if task.started_at else None,
                        "completed_at": task.completed_at.isoformat() if task.completed_at else None,
                        "error_message": task.error_message,
                        "outputs": _serialize_value(task.outputs),
                    }
                )

        brief = bus.get_research_brief() if bus else None
        bibliography = bus.get_bibliography() if bus else None
        if brief is None or bibliography is None:
            saved_brief, saved_bib = _load_saved_run_artifacts(run)
            brief = brief or saved_brief
            bibliography = bibliography or saved_bib
        theory_state = bus.get_theory_state() if bus else None
        if theory_state is None:
            theory_state = _load_saved_theory_state(run)
        experiment_result = bus.get_experiment_result() if bus else None
        resource_analysis = bus.get("resource_analysis") if bus else None
        paper_qa_answer = bus.get("paper_qa_answer") if bus else None

        # Check if a checkpoint exists for this session (enables "resume" in UI)
        has_checkpoint = False
        if run.eureka_session_id:
            from eurekaclaw.agents.theory.checkpoint import ProofCheckpoint
            has_checkpoint = ProofCheckpoint(run.eureka_session_id).exists()

        return {
            "run_id": run.run_id,
            "name": run.name,
            "session_id": run.eureka_session_id,
            "launch_html_url": f"/api/runs/{run.run_id}/launch-html",
            "status": run.status,
            "error": run.error,
            "error_category": run.error_category,
            "has_checkpoint": has_checkpoint,
            "created_at": run.created_at.isoformat(),
            "started_at": run.started_at.isoformat() if run.started_at else None,
            "completed_at": run.completed_at.isoformat() if run.completed_at else None,
            "paused_at": run.paused_at.isoformat() if run.paused_at else None,
            "pause_requested_at": run.pause_requested_at.isoformat() if run.pause_requested_at else None,
            "paused_stage": run.paused_stage,
            "input_spec": _serialize_value(run.input_spec),
            "pipeline": tasks,
            "artifacts": {
                "research_brief": _serialize_value(brief) if brief else None,
                "bibliography": _serialize_value(bibliography) if bibliography else None,
                "theory_state": _serialize_value(theory_state) if theory_state else None,
                "experiment_result": _serialize_value(experiment_result) if experiment_result else None,
                "resource_analysis": _serialize_value(resource_analysis) if resource_analysis else None,
                "paper_qa_answer": paper_qa_answer if paper_qa_answer else None,
            },
            "result": _serialize_value(run.result) if run.result else None,
            "output_summary": _serialize_value(run.output_summary),
            "output_dir": run.output_dir,
            "theory_feedback": run.theory_feedback,
        }


def _bump_writer_paper_version(bus: "KnowledgeBus") -> int:
    """Increment writer.outputs['paper_version'] on the bus pipeline.

    Treats a missing field as version 1 (the frontend shows v1 for
    first writer output). Returns the new version. No-op (returns 0) if
    no writer task is found.
    """
    pipeline = bus.get_pipeline()
    if not pipeline:
        return 0
    writer_task = next(
        (t for t in pipeline.tasks if t.name == "writer"), None
    )
    if writer_task is None:
        return 0
    outputs = writer_task.outputs or {}
    new_version = int(outputs.get("paper_version", 1)) + 1
    outputs["paper_version"] = new_version
    writer_task.outputs = outputs
    bus.put_pipeline(pipeline)
    return new_version


def _sync_latex_to_disk(run) -> tuple[bool, str]:
    """Sync writer bus latex → <run.output_dir>/paper.tex.

    Returns (changed, latex). Writes paper.tex only if bus latex differs
    from the on-disk copy. An empty `latex_paper` is treated as "nothing
    to sync" — the on-disk copy is not overwritten. Never touches
    paper.pdf; callers that care about stale PDFs are responsible for
    unlinking them.
    """
    if not getattr(run, "output_dir", None):
        return False, ""
    session = getattr(run, "eureka_session", None)
    bus = getattr(session, "bus", None) if session else None
    if bus is None:
        return False, ""
    pipeline = bus.get_pipeline()
    if not pipeline:
        return False, ""
    writer = next((t for t in pipeline.tasks if t.name == "writer"), None)
    if writer is None or not writer.outputs:
        return False, ""
    latex = writer.outputs.get("latex_paper", "")
    if not latex:
        return False, ""
    tex_path = Path(run.output_dir) / "paper.tex"
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    old = tex_path.read_text(encoding="utf-8") if tex_path.is_file() else ""
    if latex != old:
        tex_path.write_text(latex, encoding="utf-8")
        return True, latex
    return False, latex


def _ensure_bus_activated(run) -> tuple["KnowledgeBus", "TaskPipeline", "ResearchBrief"]:
    """Return the run's live bus/pipeline/brief, hydrating from disk if needed.

    Raises ValueError / FileNotFoundError on corrupt or missing state.
    Callers typically map those to HTTP 400.
    """
    session = getattr(run, "eureka_session", None)
    bus = getattr(session, "bus", None) if session else None
    if bus is None:
        from eurekaclaw.orchestrator.session_loader import SessionLoader
        bus, _brief, _pipeline = SessionLoader.load(run.eureka_session_id)
        from eurekaclaw.main import EurekaSession
        if session is None:
            run.eureka_session = EurekaSession.__new__(EurekaSession)
            run.eureka_session.session_id = run.eureka_session_id
        run.eureka_session.bus = bus
    pipeline = bus.get_pipeline()
    brief = bus.get_research_brief()
    if pipeline is None or brief is None:
        raise ValueError("Session pipeline or brief missing from bus")
    return bus, pipeline, brief


def _unlink_stale_pdf(run) -> None:
    """Delete paper.pdf from session_dir and output_dir if present.

    Matches the cleanup _review/rewrite_ was doing inline; called after a
    successful rewrite so the frontend's PDF iframe re-fetches the freshly
    compiled file instead of the stale one.
    """
    candidates = []
    session_id = getattr(run, "eureka_session_id", None)
    if session_id:
        candidates.append(settings.runs_dir / session_id / "paper.pdf")
    if getattr(run, "output_dir", None):
        candidates.append(Path(run.output_dir) / "paper.pdf")
    for pdf_path in candidates:
        try:
            if pdf_path.is_file():
                pdf_path.unlink()
        except OSError:
            logger.warning("Could not unlink stale PDF at %s", pdf_path, exc_info=True)


def _mark_rewrite_tasks_failed(pipeline, bus) -> None:
    """Flip theory/experiment/writer to FAILED if they were left mid-rewrite.

    Called from the background-rewrite exception handler so the pipeline
    settles in a visible terminal state — the frontend polls pipeline and
    can otherwise see a phantom "in progress" forever.

    Catches both IN_PROGRESS (task was actively running) and PENDING (task
    was marked pending by the handler's pre-spawn flip but the bg thread
    died before the agent executor ran, e.g. create_client crash).
    """
    mid_rewrite = (TaskStatus.IN_PROGRESS, TaskStatus.PENDING)
    changed = False
    for name in ("theory", "experiment", "writer"):
        task = next((t for t in pipeline.tasks if t.name == name), None)
        if task is not None and task.status in mid_rewrite:
            task.status = TaskStatus.FAILED
            changed = True
    if changed:
        bus.put_pipeline(pipeline)


def _mark_rewrite_tasks_pending(pipeline, bus) -> None:
    """Flip theory/experiment/writer to PENDING before the bg thread starts.

    Called from the /rewrite handler synchronously before thread.start() so
    the client's next pipeline poll immediately sees pipelineRewriting=True.
    Without this, the 202 response drops the frontend's local isRewriting
    flag in a window where pipelineRewriting is still false — a fast
    double-click slips through to a second POST, and an early bg crash
    (orchestrator construction, etc) is invisible because the UI never
    refetches /paper-qa/history (mode stays 'completed').
    """
    changed = False
    for name in ("theory", "experiment", "writer"):
        task = next((t for t in pipeline.tasks if t.name == name), None)
        if task is not None and task.status != TaskStatus.PENDING:
            task.status = TaskStatus.PENDING
            changed = True
    if changed:
        bus.put_pipeline(pipeline)


_REWRITE_CLAIM_LOCK = threading.Lock()
_REWRITE_CLAIM_SESSIONS: set[str] = set()

# Non-task bus artifacts written by theory/experiment/writer agents during
# a rewrite. Snapshot before _do_rewrite and restore on failure so a failed
# rewrite doesn't leak stale analysis into the next attempt. Task outputs
# (theory/experiment/writer.outputs) are already restored by _do_rewrite
# itself; this list covers everything OUTSIDE the pipeline tasks.
#
# If you add an agent that writes new bus keys during theory/experiment/
# writer, add the key here so the rollback covers it.
_REWRITE_MUTABLE_BUS_KEYS: tuple[str, ...] = (
    "resource_analysis",
    "numerically_suspect_lemmas",
    "revision_feedback",
)


_REWRITE_ARTIFACT_UNSET = object()


def _snapshot_rewrite_bus_artifacts(bus) -> dict[str, Any]:
    """Snapshot bus artifacts that rewrite agents may mutate.

    Returns a dict mapping key → prior value, or _REWRITE_ARTIFACT_UNSET
    for keys that weren't set. Pair with _restore_rewrite_bus_artifacts.
    """
    return {
        key: bus.get(key, _REWRITE_ARTIFACT_UNSET)
        for key in _REWRITE_MUTABLE_BUS_KEYS
    }


def _restore_rewrite_bus_artifacts(bus, snapshot: dict[str, Any]) -> None:
    """Restore bus artifacts from a snapshot taken before _do_rewrite.

    For keys with a prior value: put the prior value back.
    For keys that were unset before: remove them from the bus store so
    a failed rewrite's newly-created artifact doesn't linger into the
    next attempt. KnowledgeBus has no public delete, so we reach into
    ._store.pop — bus is a thin dict wrapper.
    """
    for key, prior in snapshot.items():
        if prior is _REWRITE_ARTIFACT_UNSET:
            bus._store.pop(key, None)
            continue
        bus.put(key, prior)


def _claim_rewrite_slot(session_id: str) -> bool:
    """Claim a per-session rewrite slot. Returns True iff claim succeeded.

    The /rewrite handler's status-based guard is not atomic with thread
    spawn — two requests can both see all-COMPLETED tasks in the window
    before _do_rewrite flips anything to IN_PROGRESS. This lock closes
    that window: a second /rewrite for the same session is refused until
    the first bg thread releases its slot.
    """
    if not session_id:
        return False
    with _REWRITE_CLAIM_LOCK:
        if session_id in _REWRITE_CLAIM_SESSIONS:
            return False
        _REWRITE_CLAIM_SESSIONS.add(session_id)
        return True


def _release_rewrite_slot(session_id: str) -> None:
    """Release a claim made by _claim_rewrite_slot. No-op if not held."""
    if not session_id:
        return
    with _REWRITE_CLAIM_LOCK:
        _REWRITE_CLAIM_SESSIONS.discard(session_id)


def _stale_paper_qa_response(action: str) -> tuple[dict[str, Any], HTTPStatus]:
    """Response body + status for a /gate/paper_qa submit on a stale gate.

    For action='no' (Accept), the stale-gate cleanup closes the stranded
    UI state — which IS what the user asked for. Returning {ok:true} is
    honest.

    For action='rewrite' (or any other non-'no' action), the cleanup
    only de-strands the UI; it does NOT honor the rewrite. Returning
    {ok:true} would silently drop the user's intent. Return 409 so the
    client knows to retry via /rewrite.
    """
    if action == "no":
        return {"ok": True, "stale_gate_cleaned": True}, HTTPStatus.OK
    return (
        {
            "error": "Gate no longer active; use /rewrite for rewrite actions.",
            "stale_gate_cleaned": True,
        },
        HTTPStatus.CONFLICT,
    )


def _handle_stale_paper_qa_gate(pipeline, bus, session_id: str) -> None:
    """Flip a stale AWAITING_GATE paper_qa_gate task to FAILED and persist.

    Called from /rewrite and /gate/paper_qa when submit_paper_qa returns
    False. Only flips the task when its current status is AWAITING_GATE —
    otherwise the helper is a no-op. The guard matters because a duplicate
    Accept click after the orchestrator finishes (paper_qa_gate=COMPLETED,
    gate entry unregistered) also produces submit_paper_qa=False, and we
    must not corrupt a legitimately completed gate into FAILED.
    """
    qa = next((t for t in pipeline.tasks if t.name == "paper_qa_gate"), None)
    if qa is None or qa.status != TaskStatus.AWAITING_GATE:
        return
    qa.status = TaskStatus.FAILED
    bus.put_pipeline(pipeline)
    try:
        bus.persist(settings.runs_dir / session_id)
    except Exception:
        logger.exception(
            "Could not persist pipeline after stale gate for %s",
            session_id,
        )


def _append_paper_qa_rewrite_marker_file(session_id: str, prompt: str) -> None:
    """Module-level counterpart to the HTTP handler's rewrite-marker method.

    Needed because _run_rewrite_bg is module-level (runs on a background
    thread with no handler instance). The on-disk format and constants
    match _append_paper_qa_rewrite_marker exactly.
    """
    if not session_id or not prompt:
        return
    from datetime import datetime as _dt, timezone as _tz
    history_dir = settings.runs_dir / session_id
    try:
        history_dir.mkdir(parents=True, exist_ok=True)
        history_file = history_dir / "paper_qa_history.jsonl"
        entry = {
            "role": "system",
            "content": f'{REWRITE_MARKER_PREFIX}"{prompt}"',
            "ts": _dt.now(_tz.utc).isoformat(),
        }
        with history_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        logger.warning("Could not append rewrite marker for %s", session_id, exc_info=True)


def _append_paper_qa_error_marker(session_id: str, msg: str) -> None:
    """Append a 'Revision error: <msg>' system line for the rewrite history."""
    if not session_id or not msg:
        return
    from datetime import datetime as _dt, timezone as _tz
    history_dir = settings.runs_dir / session_id
    try:
        history_dir.mkdir(parents=True, exist_ok=True)
        history_file = history_dir / "paper_qa_history.jsonl"
        entry = {
            "role": "system",
            "content": f"Revision error: {msg}",
            "ts": _dt.now(_tz.utc).isoformat(),
        }
        with history_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        logger.warning("Could not append error marker for %s", session_id, exc_info=True)


def _run_rewrite_bg(run, bus, pipeline, brief, prompt: str, rewrite_id: str) -> None:
    """Thread entry point. Owns its own asyncio event loop.

    On success: mutates pipeline in-place (theory → experiment → writer
    re-run) through handler._do_rewrite, then syncs paper.tex to disk,
    unlinks stale paper.pdf, bumps paper_version, appends rewrite marker,
    persists bus.

    On failure: catches everything, flips any IN_PROGRESS rewrite tasks
    to FAILED so the frontend's pipeline poll settles, and appends an
    error marker.
    """
    session_id = run.eureka_session_id
    # Snapshot non-task bus artifacts BEFORE any agent runs. If the rewrite
    # fails (soft failure OR exception), restore them so the next rewrite
    # doesn't inherit stale analysis from the failed attempt. _do_rewrite
    # already restores task outputs internally; this covers what it doesn't.
    artifact_snapshot = _snapshot_rewrite_bus_artifacts(bus)
    try:
        orchestrator = MetaOrchestrator(bus=bus, client=create_client())
        handler = PaperQAHandler(
            bus=bus,
            agents=orchestrator.agents,
            router=orchestrator.router,
            client=orchestrator.client,
            tool_registry=orchestrator.tool_registry,
            skill_injector=orchestrator.skill_injector,
            memory=orchestrator.memory,
            gate_controller=orchestrator.gate,
        )
        new_latex = asyncio.run(
            handler._do_rewrite(pipeline, brief, revision_prompt=prompt)
        )
        if new_latex:
            _sync_latex_to_disk(run)
            _unlink_stale_pdf(run)
            _bump_writer_paper_version(bus)
            _append_paper_qa_rewrite_marker_file(session_id, prompt)
            bus.persist(settings.runs_dir / session_id)
        else:
            # Soft failure: restore bus artifacts, then surface as error.
            _restore_rewrite_bus_artifacts(bus, artifact_snapshot)
            _append_paper_qa_error_marker(session_id, "Rewrite produced no new paper")
    except Exception as e:
        logger.exception("Rewrite background task %s failed: %s", rewrite_id, e)
        _restore_rewrite_bus_artifacts(bus, artifact_snapshot)
        _mark_rewrite_tasks_failed(pipeline, bus)
        try:
            bus.persist(settings.runs_dir / session_id)
        except Exception:
            logger.exception(
                "Could not persist bus after rewrite failure for %s", session_id
            )
        _append_paper_qa_error_marker(session_id, f"Rewrite failed: {e}")
    finally:
        _release_rewrite_slot(session_id)


def _extract_latex_error(log_path: Path, max_chars: int = 1200) -> str:
    """Pull the relevant pdflatex error excerpt out of paper.log.

    pdflatex logs are noisy; the useful bit is the block starting at the
    first line that begins with '!'. We return that block (plus a few
    lines of context) trimmed to max_chars so the UI can show it.
    """
    try:
        text = log_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    lines = text.splitlines()
    first_err = next((i for i, ln in enumerate(lines) if ln.startswith("!")), None)
    if first_err is None:
        return "\n".join(lines[-30:])[-max_chars:]
    start = max(0, first_err - 2)
    end = min(len(lines), first_err + 20)
    return "\n".join(lines[start:end])[-max_chars:]


def _install_lean4() -> dict[str, Any]:
    """Install Lean4 via elan and wire LEAN4_BIN to the installed binary."""
    if _sys.platform.startswith("win"):
        return {"ok": False, "message": "Lean4 one-click install is not supported on Windows yet. Install elan manually and set LEAN4_BIN."}
    curl_exe = shutil.which("curl")
    wget_exe = shutil.which("wget")
    bash_exe = shutil.which("bash") or "/bin/bash"
    if not curl_exe and not wget_exe:
        return {"ok": False, "message": "Neither curl nor wget was found. Install one of them, then try again."}
    if curl_exe:
        install_cmd = f'{curl_exe} https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | {bash_exe} -s -- -y'
    else:
        install_cmd = f'{wget_exe} -qO- https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | {bash_exe} -s -- -y'
    try:
        result = _subprocess.run([bash_exe, "-lc", install_cmd], capture_output=True, text=True, timeout=180)
        if result.returncode != 0:
            return {"ok": False, "message": result.stderr.strip() or result.stdout.strip() or "Lean4 install failed."}
        lean_path = (Path.home() / ".elan" / "bin" / "lean").expanduser()
        if not lean_path.is_file():
            return {"ok": False, "message": "elan finished, but the Lean binary was not found at ~/.elan/bin/lean."}
        settings.lean4_bin = str(lean_path)
        _write_env_updates(_ENV_PATH, {"LEAN4_BIN": str(lean_path)})
        return {"ok": True, "message": f"Lean4 installed successfully at {lean_path}."}
    except Exception as exc:
        return {"ok": False, "message": str(exc)}


def _config_payload() -> dict[str, Any]:
    return {
        field_name: str(getattr(settings, field_name))
        if isinstance(getattr(settings, field_name), Path)
        else getattr(settings, field_name)
        for field_name in _CONFIG_FIELDS
    }


def _preflight_check(config: dict[str, Any]) -> None:
    """Raise a descriptive ValueError if credentials are not configured.

    Called before the session thread spins up the LLM client so that failures
    surface as a clear ``run.error`` message rather than a cryptic traceback
    deep inside the agent loop.
    """
    from eurekaclaw.llm.factory import _BACKEND_ALIASES

    original_backend = str(config.get("llm_backend", "anthropic"))
    auth_mode = str(config.get("anthropic_auth_mode", "api_key"))
    codex_auth_mode = str(config.get("codex_auth_mode", "api_key"))

    # Resolve shortcut backends (openrouter, local, codex) → (openai_compat, default_base_url)
    _canonical, _default_base = _BACKEND_ALIASES.get(original_backend, (original_backend, ""))
    backend = _canonical if _canonical != original_backend else original_backend

    if original_backend == "minimax":
        api_key = str(config.get("minimax_api_key", "") or "")
        if not api_key:
            raise ValueError(
                "MINIMAX_API_KEY is not set. "
                "Configure it in the UI settings or .env before starting a session."
            )
    elif backend == "openai_compat":
        base_url = str(config.get("openai_compat_base_url", "") or "") or _default_base
        if not base_url:
            raise ValueError(
                "OPENAI_COMPAT_BASE_URL is not set. "
                "Configure it in the UI settings or .env before starting a session."
            )
        # Skip API key check for codex OAuth — the key is injected at runtime
        # by maybe_setup_codex_auth() before the LLM client is created.
        if original_backend == "codex" and codex_auth_mode == "oauth":
            return
        api_key = str(config.get("openai_compat_api_key", "") or "")
        if not api_key:
            raise ValueError(
                "OPENAI_COMPAT_API_KEY is not set. "
                "Configure it in the UI settings or .env before starting a session."
            )
    else:
        # Anthropic backend
        if auth_mode == "oauth":
            return  # ccproxy handles auth; no key needed here

        import os as _os
        from pathlib import Path as _Path
        import json as _json

        api_key = (
            str(config.get("anthropic_api_key", "") or "")
            or _os.environ.get("ANTHROPIC_API_KEY", "")
        )
        if not api_key:
            # Last resort: check for Claude Code OAuth token
            creds = _Path.home() / ".claude" / ".credentials.json"
            if creds.exists():
                try:
                    token = _json.loads(creds.read_text()).get("claudeAiOauth", {}).get("accessToken", "")
                    if token:
                        return
                except Exception:
                    pass
            raise ValueError(
                "ANTHROPIC_API_KEY is not set. "
                "Add it in the UI Settings panel or your .env file, "
                "or use ANTHROPIC_AUTH_MODE=oauth with Claude Code."
            )


def _skills_payload() -> list[dict[str, Any]]:
    registry = SkillRegistry()
    skills = registry.load_all()
    skills.sort(key=lambda skill: (skill.meta.source != "seed", skill.meta.name))
    return [
        {
            "name": skill.meta.name,
            "description": skill.meta.description,
            "tags": skill.meta.tags,
            "agent_roles": skill.meta.agent_roles,
            "pipeline_stages": skill.meta.pipeline_stages,
            "source": skill.meta.source,
            "usage_count": skill.meta.usage_count,
            "success_rate": skill.meta.success_rate,
            "file_path": skill.file_path,
        }
        for skill in skills
    ]


def _install_skill(skillname: str) -> dict[str, Any]:
    """Install a skill from ClawHub or copy seed skills.  Runs synchronously."""
    from eurekaclaw.skills.install import install_from_hub, install_seed_skills

    dest = settings.skills_dir
    try:
        if skillname:
            ok = install_from_hub(skillname, dest)
            if ok:
                return {"ok": True, "message": f"Installed '{skillname}' from ClawHub → {dest}"}
            return {"ok": False, "error": f"Could not install '{skillname}'. Check that the `clawhub` CLI is installed and the skill slug is correct."}
        else:
            install_seed_skills(dest)
            return {"ok": True, "message": f"Seed skills installed → {dest}"}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def _merged_config(overrides: dict[str, Any] | None = None) -> dict[str, Any]:
    config = _config_payload()
    if overrides:
        for key, value in overrides.items():
            config[key] = value
    return config


@contextmanager
def _temporary_auth_env(config: dict[str, Any]):
    """Temporarily align settings/env for auth checks, then restore them."""
    env_keys = ["ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "OPENAI_COMPAT_API_KEY"]
    old_env = {key: os.environ.get(key) for key in env_keys}
    old_settings = {
        "anthropic_auth_mode": settings.anthropic_auth_mode,
        "ccproxy_port": settings.ccproxy_port,
        "codex_auth_mode": settings.codex_auth_mode,
    }
    proc = None

    try:
        settings.anthropic_auth_mode = str(config.get("anthropic_auth_mode", settings.anthropic_auth_mode))
        settings.ccproxy_port = int(config.get("ccproxy_port", settings.ccproxy_port))
        settings.codex_auth_mode = str(config.get("codex_auth_mode", settings.codex_auth_mode))

        api_key = str(config.get("anthropic_api_key", "") or "")
        if api_key:
            os.environ["ANTHROPIC_API_KEY"] = api_key

        backend = str(config.get("llm_backend", "anthropic"))

        if backend in {"anthropic", "oauth"} and config.get("anthropic_auth_mode") == "oauth":
            proc = maybe_start_ccproxy()

        if config.get("llm_backend") == "codex" and config.get("codex_auth_mode") == "oauth":
            from eurekaclaw.codex_manager import maybe_setup_codex_auth
            maybe_setup_codex_auth()

        yield
    finally:
        stop_ccproxy(proc)
        settings.anthropic_auth_mode = old_settings["anthropic_auth_mode"]
        settings.ccproxy_port = old_settings["ccproxy_port"]
        settings.codex_auth_mode = old_settings["codex_auth_mode"]
        for key, value in old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def _test_llm_auth(config: dict[str, Any]) -> dict[str, Any]:
    """Initialize the configured client and perform a minimal text-generation check."""
    backend = str(config.get("llm_backend", "anthropic"))
    auth_mode = str(config.get("anthropic_auth_mode", "api_key"))
    codex_auth = str(config.get("codex_auth_mode", "api_key"))

    # Resolve model per backend.
    if backend == "codex":
        model = str(config.get("codex_model") or "o4-mini")
    elif backend == "minimax":
        model = str(config.get("minimax_model") or "")
    else:
        model = str(
            config.get("eurekaclaw_fast_model")
            or config.get("openai_compat_model")
            or config.get("eurekaclaw_model")
            or ""
        )

    try:
        with _temporary_auth_env(config):
            # For codex OAuth, don't pass openai_api_key — it's injected into
            # env by maybe_setup_codex_auth() inside _temporary_auth_env.
            if backend == "codex" and codex_auth == "oauth":
                client = create_client(
                    backend=backend,
                    openai_model=str(config.get("codex_model") or ""),
                )
            else:
                openai_base_url = str(config.get("openai_compat_base_url", "") or "")
                openai_api_key = str(config.get("openai_compat_api_key", "") or "")
                openai_model = str(config.get("openai_compat_model", "") or "")
                if backend == "minimax":
                    openai_base_url = ""
                    openai_api_key = str(config.get("minimax_api_key", "") or "")
                    openai_model = str(config.get("minimax_model", "") or "")
                effective_backend = "anthropic" if backend == "oauth" else backend
                client = create_client(
                    backend=effective_backend,
                    anthropic_api_key=str(config.get("anthropic_api_key", "") or ""),
                    openai_base_url=openai_base_url,
                    openai_api_key=openai_api_key,
                    openai_model=openai_model,
                )
            response = await client.messages.create(
                model=model,
                max_tokens=16,
                system="Reply with exactly OK.",
                messages=[{"role": "user", "content": "Return OK."}],
            )
    except Exception as exc:
        return {
            "ok": False,
            "provider": backend,
            "auth_mode": auth_mode,
            "message": str(exc),
        }

    text_parts = [block.text for block in response.content if getattr(block, "type", "") == "text"]
    reply = " ".join(text_parts).strip()
    return {
        "ok": True,
        "provider": backend,
        "auth_mode": auth_mode,
        "message": "Connection verified with a live model response.",
        "reply_preview": reply[:120],
        "model": model,
    }


class UIRequestHandler(SimpleHTTPRequestHandler):
    """Serve frontend assets and JSON API routes."""

    def __init__(self, *args: Any, state: UIServerState, directory: str, **kwargs: Any) -> None:
        self.state = state
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/config":
            self._send_json({"config": _config_payload()})
            return
        if parsed.path == "/api/capabilities":
            self._send_json({"capabilities": _infer_capabilities()})
            return
        if parsed.path == "/api/skills":
            self._send_json({"skills": _skills_payload()})
            return
        if parsed.path == "/api/runs":
            runs = [self.state.snapshot_run(run) for run in self.state.list_runs()]
            self._send_json({"runs": runs})
            return
        _launch_parts = parsed.path.strip("/").split("/")
        if (len(_launch_parts) == 4 and _launch_parts[0] == "api" and _launch_parts[1] == "runs"
                and _launch_parts[3] == "launch-html"):
            _launch_run_id = _launch_parts[2]
            _launch_run = self.state.get_run(_launch_run_id)
            if _launch_run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            _launch_path = _UI_LAUNCH_DIR / f"{_launch_run.run_id}.html"
            if not _launch_path.is_file():
                self._send_json({"error": "File not found"}, status=HTTPStatus.NOT_FOUND)
                return
            self._send_file(_launch_path, as_attachment=False)
            return
        # Serve artifact files: /api/runs/<run_id>/artifacts/<filename>
        _art_parts = parsed.path.strip("/").split("/")
        if (len(_art_parts) == 5 and _art_parts[0] == "api" and _art_parts[1] == "runs"
                and _art_parts[3] == "artifacts"):
            _art_run_id = _art_parts[2]
            _art_filename = _art_parts[4]
            _art_run = self.state.get_run(_art_run_id)
            if _art_run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            if not _art_run.output_dir:
                self._send_json({"error": "No output directory"}, status=HTTPStatus.NOT_FOUND)
                return
            _art_path = Path(_art_run.output_dir) / _art_filename
            # Security: only allow known artifact filenames
            _allowed = {"paper.tex", "paper.pdf", "paper.md", "references.bib",
                        "theory_state.json", "experiment_result.json", "research_brief.json"}
            if _art_filename not in _allowed:
                self._send_json({"error": "File not found"}, status=HTTPStatus.NOT_FOUND)
                return
            # Sync the latest paper.tex from memory so .tex downloads
            # reflect any edits made since save_artifacts last ran.
            # Never touch paper.pdf here — compile-pdf owns the PDF
            # lifecycle.
            if _art_filename == "paper.tex":
                _sync_latex_to_disk(_art_run)
            if not _art_path.is_file():
                self._send_json({"error": "File not found"}, status=HTTPStatus.NOT_FOUND)
                return
            # Serve PDF inline so iframes can display it
            inline = _art_filename.endswith(".pdf")
            self._send_file(_art_path, as_attachment=not inline)
            return

        # GET /api/runs/<run_id>/paper-qa/history
        parts_pqa = parsed.path.strip("/").split("/")
        if (len(parts_pqa) == 5 and parts_pqa[0] == "api" and parts_pqa[1] == "runs"
                and parts_pqa[3] == "paper-qa" and parts_pqa[4] == "history"):
            run_id = parts_pqa[2]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            session_id = run.eureka_session_id
            if not session_id:
                # No session id yet — return empty rather than reading
                # settings.runs_dir / "" which would mix history across runs.
                self._send_json({"messages": []})
                return
            import json as _json
            history_file = settings.runs_dir / session_id / "paper_qa_history.jsonl"
            messages = []
            if history_file.exists():
                for line in history_file.read_text(encoding="utf-8").strip().split("\n"):
                    if line.strip():
                        try:
                            messages.append(_json.loads(line))
                        except _json.JSONDecodeError:
                            pass
            self._send_json({"messages": messages})
            return

        if parsed.path.startswith("/api/runs/"):
            run_id = parsed.path.split("/")[-1]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            self._send_json(self.state.snapshot_run(run))
            return
        if parsed.path == "/api/oauth/status":
            available = is_ccproxy_available()
            if not available:
                self._send_json({"installed": False, "authenticated": False, "message": f"ccproxy not found. Install with: {_oauth_install_hint()}"})
                return
            authed, msg = check_ccproxy_auth("claude_api")
            self._send_json({"installed": True, "authenticated": authed, "message": msg})
            return
        if parsed.path == "/api/codex/status":
            try:
                from eurekaclaw.codex_manager import _read_codex_cli_tokens, _CODEX_CLI_AUTH_PATH
                from eurekaclaw.auth.token_store import load_tokens

                # Check EurekaClaw store first, then Codex CLI file
                stored = load_tokens("openai-codex")
                cli_tokens = _read_codex_cli_tokens()
                has_token = bool(
                    (stored and stored.get("access_token"))
                    or (cli_tokens and cli_tokens.get("access_token"))
                )
                if has_token:
                    self._send_json({
                        "installed": True,
                        "authenticated": True,
                        "message": "Codex credentials available",
                    })
                elif _CODEX_CLI_AUTH_PATH.exists():
                    self._send_json({
                        "installed": True,
                        "authenticated": False,
                        "message": "Codex CLI file found but access token is missing or invalid",
                    })
                else:
                    self._send_json({
                        "installed": False,
                        "authenticated": False,
                        "message": f"No credentials found. Run: npm install -g @openai/codex && codex auth login",
                    })
            except Exception as exc:
                self._send_json({
                    "installed": False,
                    "authenticated": False,
                    "message": f"Error checking Codex status: {exc}",
                })
            return
        if parsed.path == "/api/codex/package-status":
            try:
                import importlib.util
                openai_spec = importlib.util.find_spec("openai")
                self._send_json({"installed": openai_spec is not None})
            except Exception:
                self._send_json({"installed": False})
            return
        if parsed.path == "/api/health":
            self._send_json({"ok": True, "time": datetime.utcnow().isoformat()})
            return

        if parsed.path in ("/", ""):
            self.path = "/index.html"
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/runs":
            payload = self._read_json()
            try:
                input_spec = InputSpec.model_validate(payload)
            except Exception as exc:
                self._send_json(
                    {"error": f"Invalid request: {exc}"},
                    status=HTTPStatus.BAD_REQUEST,
                )
                return
            run = self.state.create_run(input_spec)
            self.state.start_run(run)
            self._send_json(self.state.snapshot_run(run), status=HTTPStatus.CREATED)
            return
        if parsed.path == "/api/auth/test":
            payload = self._read_json()
            result = asyncio.run(_test_llm_auth(_merged_config(payload)))
            self._send_json(result)
            return
        if parsed.path == "/api/config":
            payload = self._read_json()
            config_updates: dict[str, str] = {}
            for field_name, env_name in _CONFIG_FIELDS.items():
                if field_name not in payload:
                    continue
                value = payload[field_name]
                if isinstance(value, bool):
                    rendered = "true" if value else "false"
                else:
                    rendered = str(value)
                config_updates[env_name] = rendered
                current = getattr(settings, field_name)
                if isinstance(current, Path):
                    setattr(settings, field_name, Path(rendered))
                elif isinstance(current, bool):
                    setattr(settings, field_name, rendered.lower() == "true")
                elif isinstance(current, int):
                    setattr(settings, field_name, int(rendered))
                elif isinstance(current, float):
                    setattr(settings, field_name, float(rendered))
                else:
                    setattr(settings, field_name, rendered)

            _write_env_updates(_ENV_PATH, config_updates)
            self._send_json({"config": _config_payload(), "saved": True})
            return

        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/pause"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/pause")
            result = self.state.pause_run(run_id)
            if "error" in result:
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result)
            return
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/resume"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/resume")
            payload = self._read_json()
            feedback = str(payload.get("feedback", "")).strip()
            result = self.state.resume_run(run_id, feedback=feedback)
            if "error" in result:
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result)
            return
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/rename"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/rename")
            payload = self._read_json()
            result = self.state.rename_run(run_id, str(payload.get("name", "")))
            if "error" in result:
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result)
            return
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/restart"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/restart")
            result = self.state.restart_run(run_id)
            if result.get("error"):  # snapshot always has "error" key; check truthiness
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result, status=HTTPStatus.CREATED)
            return

        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/restart-from-ideation"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/restart-from-ideation")
            result = self.state.restart_from_ideation(run_id)
            if result.get("error"):
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result, status=HTTPStatus.CREATED)
            return
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/restart-from-theory"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/restart-from-theory")
            result = self.state.restart_from_theory(run_id)
            if result.get("error"):
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result, status=HTTPStatus.CREATED)
            return
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/restart-from-theory-stage"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/restart-from-theory-stage")
            payload = self._read_json()
            substage = str(payload.get("substage", "")).strip()
            result = self.state.restart_from_theory_substage(run_id, substage)
            if result.get("error"):
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result, status=HTTPStatus.CREATED)
            return

        # Re-run in place: /api/runs/<run_id>/rerun
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/rerun"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/rerun")
            payload = self._read_json()
            updated_skills = payload.get("selected_skills") if payload else None
            result = self.state.rerun_run(run_id, updated_skills=updated_skills)
            if result.get("error"):
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result)
            return

        # Compile PDF: /api/runs/<run_id>/compile-pdf
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/compile-pdf"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/compile-pdf")
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            if not run.output_dir:
                self._send_json({"error": "No output directory"}, status=HTTPStatus.BAD_REQUEST)
                return
            tex_path = Path(run.output_dir) / "paper.tex"
            # Always sync the latest LaTeX from the writer task's
            # in-memory output to disk. At gate time paper.tex may not
            # exist yet, and after a rewrite the on-disk copy is stale.
            changed, _ = _sync_latex_to_disk(run)
            if changed:
                # Remove stale PDF so it gets freshly compiled.
                stale_pdf = Path(run.output_dir) / "paper.pdf"
                if stale_pdf.is_file():
                    stale_pdf.unlink()
            if not tex_path.is_file():
                self._send_json({"error": "No paper.tex found"}, status=HTTPStatus.BAD_REQUEST)
                return
            # Ensure eureka.cls, smile.sty, logo-claw.png, fonts/ sit next to
            # paper.tex. save_artifacts() only runs at full pipeline
            # completion, so during the Paper QA gate or a rewrite the
            # template assets may not have been copied yet.
            try:
                _copy_template_assets(Path(run.output_dir))
            except Exception:
                logger.warning("Could not copy template assets to %s", run.output_dir, exc_info=True)
            try:
                _compile_pdf(tex_path, settings.latex_bin)
                pdf_path = Path(run.output_dir) / "paper.pdf"
                if pdf_path.is_file():
                    self._send_json({"ok": True, "pdf_path": str(pdf_path)})
                else:
                    log_tail = _extract_latex_error(Path(run.output_dir) / "paper.log")
                    msg = "pdflatex ran but produced no PDF"
                    if log_tail:
                        msg = f"{msg}:\n{log_tail}"
                    self._send_json({"error": msg}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            except FileNotFoundError:
                self._send_json({"error": "pdflatex binary not found. Install TeX (e.g. brew install --cask basictex)"}, status=HTTPStatus.BAD_REQUEST)
            except Exception as exc:
                self._send_json({"error": f"PDF compilation failed: {exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        if parsed.path == "/api/lean4/install":
            result = _install_lean4()
            self._send_json(result, status=HTTPStatus.OK if result.get("ok") else HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        if parsed.path == "/api/oauth/install":
            try:
                repo_root = str(Path(__file__).resolve().parents[2])
                # Prefer uv pip (uv-managed venvs don't bundle pip)
                uv_exe = shutil.which("uv")
                if uv_exe:
                    cmd = [uv_exe, "pip", "install", "-e", ".[oauth]"]
                else:
                    cmd = [_sys.executable, "-m", "pip", "install", "-e", ".[oauth]"]
                result = _subprocess.run(
                    cmd,
                    capture_output=True, text=True, timeout=120,
                    cwd=repo_root,
                )
                if result.returncode == 0:
                    self._send_json({"ok": True, "message": "OAuth dependencies installed successfully."})
                else:
                    self._send_json({"ok": False, "message": result.stderr.strip() or result.stdout.strip()})
            except Exception as exc:
                self._send_json({"ok": False, "message": str(exc)})
            return

        if parsed.path == "/api/oauth/login":
            from eurekaclaw.ccproxy_manager import _ccproxy_exe
            exe = _ccproxy_exe()
            if not exe:
                self._send_json({"ok": False, "message": f"ccproxy not found. Install first with: {_oauth_install_hint()}"})
                return
            try:
                # Launch login in background — it opens a browser and waits
                # for the user to complete auth, so we can't block the HTTP response.
                _subprocess.Popen(
                    [exe, "auth", "login", "claude_api"],
                    stdout=_subprocess.DEVNULL,
                    stderr=_subprocess.DEVNULL,
                )
                self._send_json({"ok": True, "message": "OAuth login opened in your browser. Complete authorization, then click 'Save & test'."})
            except Exception as exc:
                self._send_json({"ok": False, "message": str(exc)})
            return

        if parsed.path == "/api/codex/install":
            try:
                repo_root = str(Path(__file__).resolve().parents[2])
                # Prefer uv pip (uv-managed venvs don't bundle pip)
                uv_exe = shutil.which("uv")
                if uv_exe:
                    cmd = [uv_exe, "pip", "install", "openai"]
                else:
                    cmd = [_sys.executable, "-m", "pip", "install", "openai"]
                result = _subprocess.run(
                    cmd,
                    capture_output=True, text=True, timeout=120,
                    cwd=repo_root,
                )
                if result.returncode == 0:
                    self._send_json({"ok": True, "message": "OpenAI package installed successfully."})
                else:
                    self._send_json({"ok": False, "message": result.stderr.strip() or result.stdout.strip()})
            except Exception as exc:
                self._send_json({"ok": False, "message": str(exc)})
            return

        if parsed.path == "/api/codex/login":
            try:
                from eurekaclaw.codex_manager import _read_codex_cli_tokens, _CODEX_CLI_AUTH_PATH
                from eurekaclaw.auth.token_store import save_tokens

                if not _CODEX_CLI_AUTH_PATH.exists():
                    self._send_json({
                        "ok": False,
                        "message": (
                            f"Codex CLI credentials not found at {_CODEX_CLI_AUTH_PATH}. "
                            "Install and login first:\n"
                            "  npm install -g @openai/codex\n"
                            "  codex auth login"
                        ),
                    })
                    return
                tokens = _read_codex_cli_tokens()
                if not tokens or not tokens.get("access_token"):
                    self._send_json({
                        "ok": False,
                        "message": (
                            f"Could not read a valid access_token from {_CODEX_CLI_AUTH_PATH}. "
                            "Try re-authenticating with: codex auth login"
                        ),
                    })
                    return
                save_tokens("openai-codex", tokens)
                self._send_json({
                    "ok": True,
                    "message": f"Codex credentials imported from {_CODEX_CLI_AUTH_PATH}",
                })
            except Exception as exc:
                self._send_json({"ok": False, "message": str(exc)})
            return

        if parsed.path == "/api/skills/install":
            payload = self._read_json()
            skillname = str(payload.get("skillname", "")).strip()
            result = _install_skill(skillname)
            status = HTTPStatus.OK if result.get("ok") else HTTPStatus.BAD_REQUEST
            self._send_json(result, status=status)
            return

        # POST /api/runs/<run_id>/rewrite — unified rewrite entry point
        parts_rw = parsed.path.strip("/").split("/")
        if (len(parts_rw) == 4 and parts_rw[0] == "api" and parts_rw[1] == "runs"
                and parts_rw[3] == "rewrite"):
            run_id = parts_rw[2]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return

            try:
                bus, pipeline, brief = _ensure_bus_activated(run)
            except (ValueError, FileNotFoundError) as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.BAD_REQUEST)
                return

            payload = self._read_json()
            prompt = str(payload.get("revision_prompt", "")).strip()
            if not prompt:
                self._send_json(
                    {"error": "revision_prompt required"},
                    status=HTTPStatus.BAD_REQUEST,
                )
                return

            # Concurrency guard — refuse if a rewrite is already in flight.
            # Scope mirrors _mark_rewrite_tasks_failed and _do_rewrite's replay
            # set: theory → experiment → writer. Missing experiment here would
            # let a second request slip through while the experiment task was
            # IN_PROGRESS.
            rewrite_task_names = ("theory", "experiment", "writer")
            rewrite_tasks = [
                next((t for t in pipeline.tasks if t.name == name), None)
                for name in rewrite_task_names
            ]
            if any(t is not None and t.status == TaskStatus.IN_PROGRESS
                   for t in rewrite_tasks):
                self._send_json(
                    {"error": "A rewrite is already in progress"},
                    status=HTTPStatus.CONFLICT,
                )
                return

            # Gate-live path: live orchestrator is still waiting on paper_qa_gate.
            # submit_paper_qa returns False when the in-memory gate entry is
            # missing (orchestrator died, server restart) — in that case we
            # clean up the stale AWAITING_GATE on disk and fall through to the
            # bg path so the user's rewrite intent still gets honored.
            paper_qa_task = next(
                (t for t in pipeline.tasks if t.name == "paper_qa_gate"), None
            )
            if paper_qa_task is not None and paper_qa_task.status == TaskStatus.AWAITING_GATE:
                from eurekaclaw.ui import review_gate
                from eurekaclaw.ui.review_gate import PaperQADecision
                submitted = review_gate.submit_paper_qa(
                    run.eureka_session_id,
                    PaperQADecision(action="rewrite", question=prompt),
                )
                if submitted:
                    self._send_json(
                        {"ok": True, "mode": "gate"},
                        status=HTTPStatus.ACCEPTED,
                    )
                    return
                _handle_stale_paper_qa_gate(pipeline, bus, run.eureka_session_id)

            # Background path: orchestrator is idle/completed. Spawn a thread.
            # Claim the per-session slot BEFORE starting the thread so a
            # racing second request can't slip past the status-based guard
            # in the window before _do_rewrite flips tasks to IN_PROGRESS.
            if not _claim_rewrite_slot(run.eureka_session_id):
                self._send_json(
                    {"error": "A rewrite is already in progress"},
                    status=HTTPStatus.CONFLICT,
                )
                return
            # Flip rewrite tasks to PENDING synchronously so the client's
            # next pipeline poll sees pipelineRewriting=True before the 202
            # lands — closes the "invisible early failure" and
            # "double-click slips a second POST" gaps.
            _mark_rewrite_tasks_pending(pipeline, bus)
            rewrite_id = str(uuid.uuid4())
            thread = threading.Thread(
                target=_run_rewrite_bg,
                args=(run, bus, pipeline, brief, prompt, rewrite_id),
                daemon=True,
            )
            try:
                thread.start()
            except Exception:
                # Release the slot AND restore task statuses if we failed to
                # start the thread at all — otherwise the session is
                # permanently blocked with phantom PENDING tasks.
                _mark_rewrite_tasks_failed(pipeline, bus)
                _release_rewrite_slot(run.eureka_session_id)
                raise
            self._send_json(
                {"ok": True, "mode": "bg", "rewrite_id": rewrite_id},
                status=HTTPStatus.ACCEPTED,
            )
            return

        # ── Paper QA endpoints ────────────────────────────────────────────
        parts_pqa = parsed.path.strip("/").split("/")
        if (len(parts_pqa) == 5 and parts_pqa[0] == "api" and parts_pqa[1] == "runs"
                and parts_pqa[3] == "paper-qa" and parts_pqa[4] == "ask"):
            run_id = parts_pqa[2]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            session_id = run.eureka_session_id
            if not session_id:
                self._send_json({"error": "No active session"}, status=HTTPStatus.BAD_REQUEST)
                return
            payload = self._read_json()
            question = str(payload.get("question", "")).strip()
            history_list = payload.get("history", [])
            if not question:
                self._send_json({"error": "No question provided"}, status=HTTPStatus.BAD_REQUEST)
                return

            try:
                bus, _pipeline, _brief = _ensure_bus_activated(run)
            except (ValueError, FileNotFoundError) as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.BAD_REQUEST)
                return
            latex = bus.get("paper_qa_latex") or ""

            import asyncio as _asyncio
            from eurekaclaw.agents.paper_qa.agent import PaperQAAgent
            from eurekaclaw.tools.registry import build_default_registry
            from eurekaclaw.skills.injector import SkillInjector
            from eurekaclaw.skills.registry import SkillRegistry
            from eurekaclaw.memory.manager import MemoryManager
            from eurekaclaw.llm import create_client

            tool_registry = build_default_registry(bus=bus)
            agent = PaperQAAgent(
                bus=bus,
                tool_registry=tool_registry,
                skill_injector=SkillInjector(SkillRegistry()),
                memory=MemoryManager(session_id=session_id),
                client=create_client(),
            )
            clean_history = [
                {"role": h.get("role", "user"), "content": h.get("content", "")}
                for h in history_list
            ]
            loop = _asyncio.new_event_loop()
            try:
                result = loop.run_until_complete(
                    agent.ask(question=question, latex=latex, history=clean_history)
                )
            except Exception as e:
                self._send_json({"error": str(e)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            finally:
                loop.close()
            if result.failed:
                self._send_json({"error": result.error}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return

            import json as _json
            from datetime import datetime as _dt, timezone as _tz
            history_dir = settings.runs_dir / session_id
            history_dir.mkdir(parents=True, exist_ok=True)
            history_file = history_dir / "paper_qa_history.jsonl"
            ts = _dt.now(_tz.utc).isoformat()
            with history_file.open("a", encoding="utf-8") as f:
                f.write(_json.dumps({"role": "user", "content": question, "ts": ts}, ensure_ascii=False) + "\n")
                f.write(_json.dumps({"role": "assistant", "content": result.output.get("answer", ""), "ts": ts}, ensure_ascii=False) + "\n")

            self._send_json({
                "answer": result.output.get("answer", ""),
                "tool_steps": [],
            })
            return

        # Gate submission endpoints: /api/runs/<run_id>/gate/{survey|direction|theory}
        parts = parsed.path.strip("/").split("/")
        if len(parts) == 4 and parts[0] == "api" and parts[1] == "runs" and parts[3] == "gate":
            self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)
            return
        if len(parts) == 5 and parts[0] == "api" and parts[1] == "runs" and parts[3] == "gate":
            run_id = parts[2]
            gate_type = parts[4]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            session_id = run.eureka_session_id
            if not session_id:
                self._send_json({"error": "No active session"}, status=HTTPStatus.BAD_REQUEST)
                return
            from eurekaclaw.ui import review_gate as _rg
            payload = self._read_json()
            if gate_type == "survey":
                raw_ids = payload.get("paper_ids", [])
                paper_ids = [str(x).strip() for x in raw_ids if str(x).strip()]
                ok = _rg.submit_survey(session_id, paper_ids)
                if not ok:
                    # Stale gate (server restart / orchestrator already gone).
                    # "Continue without papers" → skip survey, restart from ideation.
                    if not paper_ids:
                        recovery = self.state.skip_survey_to_ideation(run_id)
                        if "error" in recovery:
                            self._send_json(recovery, status=HTTPStatus.BAD_REQUEST)
                        else:
                            self._send_json({"ok": True, "skipped": "survey"})
                        return
                    self._send_json(
                        {"error": "Gate no longer active — restart the session to retry with these papers."},
                        status=HTTPStatus.BAD_REQUEST,
                    )
                    return
            elif gate_type == "direction":
                direction = str(payload.get("direction", "")).strip()
                ok = _rg.submit_direction(session_id, direction)
            elif gate_type == "theory":
                from eurekaclaw.ui.review_gate import TheoryDecision
                approved = bool(payload.get("approved", True))
                lemma_id = str(payload.get("lemma_id", "")).strip()
                reason = str(payload.get("reason", "")).strip()
                ok = _rg.submit_theory(session_id, TheoryDecision(approved=approved, lemma_id=lemma_id, reason=reason))
            elif gate_type == "paper_qa":
                from eurekaclaw.ui.review_gate import PaperQADecision
                action = str(payload.get("action", "no")).strip()
                question = str(payload.get("question", "")).strip()
                ok = _rg.submit_paper_qa(session_id, PaperQADecision(action=action, question=question))
                # We intentionally do NOT write a rewrite marker here —
                # submit only queues the decision. PaperQAHandler persists
                # the "↻ Rewrite requested" entry itself, but only after
                # the rewrite actually produces a new paper version.
                if not ok:
                    # Stale gate: disk shows AWAITING_GATE but the in-memory
                    # entry is gone (orchestrator died, server restart).
                    # Without cleanup the pipeline stays AWAITING_GATE forever
                    # and every click hits the same 400, stranding the user.
                    # Flip the task to FAILED + persist so the pipeline poll
                    # resolves the UI. For Accept that's the whole story; for
                    # rewrite the action was NOT honored (see
                    # _stale_paper_qa_response) and the client must retry via
                    # /rewrite.
                    try:
                        bus, pipeline, _brief = _ensure_bus_activated(run)
                        _handle_stale_paper_qa_gate(pipeline, bus, session_id)
                        body, status = _stale_paper_qa_response(action)
                        self._send_json(body, status=status)
                        return
                    except (ValueError, FileNotFoundError):
                        # Fall through to the generic error below.
                        pass
            else:
                self._send_json({"error": f"Unknown gate type: {gate_type}"}, status=HTTPStatus.BAD_REQUEST)
                return
            if ok:
                self._send_json({"ok": True})
            else:
                self._send_json(
                    {"error": "Gate no longer active — this session was interrupted. Restart to continue."},
                    status=HTTPStatus.BAD_REQUEST,
                )
            return

        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def do_DELETE(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/skills/"):
            skill_name = parsed.path.removeprefix("/api/skills/").strip("/")
            skill_file = settings.skills_dir / f"{skill_name}.md"
            if not skill_file.exists():
                self._send_json({"error": f"Skill '{skill_name}' not found in user skills dir."}, status=HTTPStatus.NOT_FOUND)
                return
            skill_file.unlink()
            self._send_json({"ok": True, "message": f"Deleted '{skill_name}'"})
            return
        if parsed.path.startswith("/api/runs/"):
            run_id = parsed.path.removeprefix("/api/runs/").strip("/")
            result = self.state.delete_run(run_id)
            if "error" in result:
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result)
            return
        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        # Silence noisy polling GETs to /api/runs and /api/runs/<id>
        msg = format % args
        if '"GET /api/runs' in msg and '" 200 -' in msg:
            logger.debug("UI %s", msg)
            return
        logger.info("UI %s", msg)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b"{}"
        if not body:
            return {}
        return json.loads(body.decode("utf-8"))

    def _append_paper_qa_rewrite_marker(self, session_id: str, prompt: str) -> None:
        """Persist a "↻ Rewrite requested" line to paper_qa_history.jsonl so
        the marker survives page reloads (frontend-only optimistic state
        would otherwise disappear on refresh)."""
        if not session_id or not prompt:
            return
        from datetime import datetime as _dt, timezone as _tz
        history_dir = settings.runs_dir / session_id
        try:
            history_dir.mkdir(parents=True, exist_ok=True)
            history_file = history_dir / "paper_qa_history.jsonl"
            entry = {
                "role": "system",
                "content": f'{REWRITE_MARKER_PREFIX}"{prompt}"',
                "ts": _dt.now(_tz.utc).isoformat(),
            }
            with history_file.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError:
            logger.warning("Could not append rewrite marker for %s", session_id, exc_info=True)

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, file_path: Path, *, as_attachment: bool = True) -> None:
        """Serve a file with appropriate Content-Type."""
        import mimetypes
        content_type, _ = mimetypes.guess_type(str(file_path))
        if content_type is None:
            content_type = "application/octet-stream"
        data = file_path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        disposition = "attachment" if as_attachment else "inline"
        self.send_header("Content-Disposition", f'{disposition}; filename="{file_path.name}"')
        self.end_headers()
        self.wfile.write(data)


def bind_ui_server(host: str = "127.0.0.1", port: int = 8080) -> "ThreadingHTTPServer":
    """Create and bind the UI server, trying alternative ports if needed.

    Tries up to 10 ports (port, port+1, ...) to work around Windows
    WinError 10013 (port blocked by Hyper-V / WSL exclusion ranges or firewall).

    Returns the bound server; caller is responsible for calling serve_forever()
    and server_close().
    """
    frontend_dir = _FRONTEND_DIR if _FRONTEND_DIR.exists() else _DEV_FRONTEND_DIR
    if not frontend_dir.exists():
        raise FileNotFoundError(f"Frontend directory not found: {frontend_dir}")

    state = UIServerState()
    handler = partial(UIRequestHandler, state=state, directory=str(frontend_dir))

    last_error: Exception | None = None
    for candidate in range(port, port + 10):
        try:
            server = ThreadingHTTPServer((host, candidate), handler)
            return server
        except OSError as exc:
            last_error = exc
            logger.debug("Could not bind port %d: %s", candidate, exc)

    raise OSError(
        f"Could not bind to any port in range {port}–{port + 9}. "
        f"Last error: {last_error}\n"
        f"On Windows, check excluded ports with: "
        f"netsh int ipv4 show excludedportrange protocol=tcp"
    ) from last_error


def serve_ui(host: str = "127.0.0.1", port: int = 8080) -> None:
    """Bind and serve the EurekaClaw UI, blocking until KeyboardInterrupt."""
    os.environ["EUREKACLAW_UI_MODE"] = "1"
    server = bind_ui_server(host, port)
    actual_port = server.server_address[1]
    logger.info("Serving EurekaClaw UI at http://%s:%d", host, actual_port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down UI server")
    finally:
        server.server_close()
