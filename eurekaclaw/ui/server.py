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
from typing import Any
from urllib.parse import urlparse

from eurekaclaw.ccproxy_manager import maybe_start_ccproxy, stop_ccproxy
from eurekaclaw.config import settings
from eurekaclaw.llm import create_client
from eurekaclaw.main import EurekaSession, save_artifacts
from eurekaclaw.skills.registry import SkillRegistry
from eurekaclaw.types.tasks import InputSpec, ResearchOutput, TaskStatus

logger = logging.getLogger(__name__)

_ROOT_DIR = Path(__file__).resolve().parents[2]
_FRONTEND_DIR = Path(__file__).resolve().parent / "static"
_DEV_FRONTEND_DIR = _ROOT_DIR / "frontend"
_ENV_PATH = _ROOT_DIR / ".env"

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
    "max_tokens_crystallizer": "MAX_TOKENS_CRYSTALLIZER",
    "max_tokens_assembler": "MAX_TOKENS_ASSEMBLER",
    "max_tokens_architect": "MAX_TOKENS_ARCHITECT",
    "max_tokens_analyst": "MAX_TOKENS_ANALYST",
    "max_tokens_sketch": "MAX_TOKENS_SKETCH",
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
                self.runs[run.run_id] = run
            except Exception:
                logger.warning("Failed to load persisted run from %s", path, exc_info=True)

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def create_run(self, input_spec: InputSpec) -> SessionRun:
        run = SessionRun(run_id=str(uuid.uuid4()), input_spec=input_spec)
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
        if run.status != "paused":
            return {"error": f"Run is not paused (status: {run.status})"}
        if not run.eureka_session_id:
            return {"error": "No checkpoint session ID found"}
        from eurekaclaw.agents.theory.checkpoint import ProofCheckpoint
        cp = ProofCheckpoint(run.eureka_session_id)
        if not cp.exists():
            return {"error": f"No checkpoint found for session '{run.eureka_session_id}'"}
        # Store user guidance to be injected into the theory context on resume
        if feedback:
            run.theory_feedback = feedback.strip()[:2000]
        # Transition to intermediate "resuming" state before the thread starts
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

        try:
            session = run.eureka_session
            if session is None:
                raise ValueError("Session object not available for resume")

            session_id = run.eureka_session_id
            cp = ProofCheckpoint(session_id)
            state, meta = cp.load()
            cp.clear_pause_flag()

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
                    final_state = loop.run_until_complete(
                        inner_loop.run(session_id, domain=domain)
                    )
                    session.bus.put_theory_state(final_state)
            finally:
                loop.close()
                asyncio.set_event_loop(None)

            run.status = "completed"
            run.output_summary = {"resumed": True, "session_id": session_id}

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
        finally:
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

        try:
            # Pre-flight: verify credentials before spending time initialising agents
            config = _config_payload()
            _preflight_check(config)

            session = EurekaSession()
            run.eureka_session = session
            run.eureka_session_id = session.session_id

            # Signal orchestrator to raise instead of blocking on console.input()
            session.bus.put("ui_mode", True)

            with _temporary_auth_env(config):
                # asyncio.run() can be unreliable in non-main threads on some
                # Python versions.  Creating an explicit loop is safer.
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    result = loop.run_until_complete(session.run(run.input_spec))
                finally:
                    loop.close()
                    asyncio.set_event_loop(None)

            run.result = result

            # Save artifacts to results/<run_id>/ so files are always on disk.
            out_dir = save_artifacts(result, _ROOT_DIR / "results" / run.run_id)
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
            from eurekaclaw.orchestrator.meta_orchestrator import AwaitingDirectionException, AwaitingReviewException
            if isinstance(exc, AwaitingReviewException):
                logger.info("Session %s awaiting proof review from UI", run_id)
                run.status = "awaiting_review"
                run.error = ""
            elif isinstance(exc, AwaitingDirectionException):
                logger.info("Session %s awaiting direction from UI", run_id)
                run.status = "awaiting_direction"
                run.error = ""
            elif isinstance(exc, ProofPausedException):
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
        finally:
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

    def set_direction(self, run_id: str, hypothesis: str) -> dict[str, Any]:
        """Set a user-provided research direction on an awaiting_direction run and continue from theory."""
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status != "awaiting_direction":
            return {"error": f"Run is not awaiting direction (status: {run.status})"}
        if not run.eureka_session:
            return {"error": "No session available — cannot set direction"}

        import uuid as _uuid
        from eurekaclaw.types.artifacts import ResearchDirection

        bus = run.eureka_session.bus
        brief = bus.get_research_brief()
        if not brief:
            return {"error": "No research brief found on session bus"}

        direction = ResearchDirection(
            direction_id=str(_uuid.uuid4()),
            title=hypothesis[:80],
            hypothesis=hypothesis,
            approach_sketch="User-provided direction — formalize, decompose into lemmas, attempt proof.",
            novelty_score=0.8,
            soundness_score=0.8,
            transformative_score=0.7,
        )
        direction.compute_composite()
        brief.directions = [direction]
        brief.selected_direction = direction
        bus.put_research_brief(brief)

        # Reset run state and re-execute from theory
        run.status = "running"
        run.error = ""
        run.started_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        self._persist_run(run)

        thread = threading.Thread(target=self._execute_with_direction, args=(run_id,), daemon=True)
        thread.start()
        return self.snapshot_run(run)

    def _execute_with_direction(self, run_id: str) -> None:
        """Continue a failed run from the theory stage after direction was set on the bus."""
        run = self.get_run(run_id)
        if run is None:
            return

        try:
            config = _config_payload()
            _preflight_check(config)

            session = run.eureka_session
            if session is None:
                raise ValueError("Session object not available")

            # Create a fresh orchestrator for the remaining stages
            from eurekaclaw.domains import resolve_domain
            domain = run.input_spec.domain or ""
            domain_plugin = resolve_domain(domain) if domain else None
            from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
            orchestrator = MetaOrchestrator(
                bus=session.bus,
                domain_plugin=domain_plugin,
                selected_skills=run.input_spec.selected_skills,
            )

            with _temporary_auth_env(config):
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    result = loop.run_until_complete(orchestrator.run_from_direction())
                finally:
                    loop.close()
                    asyncio.set_event_loop(None)

            run.result = result
            out_dir = save_artifacts(result, _ROOT_DIR / "results" / run.run_id)
            run.output_dir = str(out_dir)
            run.status = "completed"
            run.output_summary = {
                "latex_paper_length": len(result.latex_paper),
                "has_experiment_result": bool(result.experiment_result_json),
                "has_theory_state": bool(result.theory_state_json),
                "output_dir": str(out_dir),
                "continued_from_direction": True,
            }
        except Exception as exc:
            from eurekaclaw.agents.theory.checkpoint import ProofPausedException
            from eurekaclaw.orchestrator.meta_orchestrator import AwaitingReviewException
            if isinstance(exc, AwaitingReviewException):
                logger.info("Session %s awaiting proof review after direction set", run_id)
                run.status = "awaiting_review"
                run.error = ""
            elif isinstance(exc, ProofPausedException):
                logger.info("Session %s paused at stage '%s'", run_id, exc.stage_name)
                run.status = "paused"
                run.paused_at = datetime.utcnow()
                run.paused_stage = exc.stage_name
                run.pause_requested_at = None
                run.error = ""
            else:
                logger.exception("UI session run_from_direction failed")
                run.status = "failed"
                run.error = str(exc)
        finally:
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

    def submit_review(self, run_id: str, approved: bool, lemma_id: str = "", reason: str = "") -> dict[str, Any]:
        """Handle proof review decision from the UI and continue the pipeline."""
        run = self.get_run(run_id)
        if run is None:
            return {"error": "Run not found"}
        if run.status != "awaiting_review":
            return {"error": f"Run is not awaiting review (status: {run.status})"}
        if not run.eureka_session:
            return {"error": "No session available"}

        feedback = ""
        if not approved and lemma_id and reason:
            feedback = (
                f"The user flagged lemma '{lemma_id}' as having a critical logical gap.\n"
                f"Issue: {reason}\n"
                f"Please re-examine this lemma and fix the logical chain before assembling the proof."
            )

        run.status = "running"
        run.error = ""
        run.updated_at = datetime.utcnow()
        self._persist_run(run)

        thread = threading.Thread(
            target=self._execute_after_review,
            args=(run_id, approved, feedback),
            daemon=True,
        )
        thread.start()
        return self.snapshot_run(run)

    def _execute_after_review(self, run_id: str, approved: bool, feedback: str) -> None:
        """Continue pipeline after proof review decision."""
        run = self.get_run(run_id)
        if run is None:
            return

        try:
            config = _config_payload()
            _preflight_check(config)

            session = run.eureka_session
            if session is None:
                raise ValueError("Session object not available")

            from eurekaclaw.domains import resolve_domain
            domain = run.input_spec.domain or ""
            domain_plugin = resolve_domain(domain) if domain else None
            from eurekaclaw.orchestrator.meta_orchestrator import MetaOrchestrator
            orchestrator = MetaOrchestrator(
                bus=session.bus,
                domain_plugin=domain_plugin,
                selected_skills=run.input_spec.selected_skills,
            )

            with _temporary_auth_env(config):
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    result = loop.run_until_complete(
                        orchestrator.run_from_review(approved=approved, feedback=feedback)
                    )
                finally:
                    loop.close()
                    asyncio.set_event_loop(None)

            run.result = result
            out_dir = save_artifacts(result, _ROOT_DIR / "results" / run.run_id)
            run.output_dir = str(out_dir)
            run.status = "completed"
            run.output_summary = {
                "latex_paper_length": len(result.latex_paper),
                "has_experiment_result": bool(result.experiment_result_json),
                "has_theory_state": bool(result.theory_state_json),
                "output_dir": str(out_dir),
                "review_approved": approved,
            }
        except Exception as exc:
            from eurekaclaw.agents.theory.checkpoint import ProofPausedException
            from eurekaclaw.orchestrator.meta_orchestrator import AwaitingReviewException
            if isinstance(exc, AwaitingReviewException):
                logger.info("Session %s awaiting proof review again", run_id)
                run.status = "awaiting_review"
                run.error = ""
            elif isinstance(exc, ProofPausedException):
                logger.info("Session %s paused at stage '%s'", run_id, exc.stage_name)
                run.status = "paused"
                run.paused_at = datetime.utcnow()
                run.paused_stage = exc.stage_name
                run.pause_requested_at = None
                run.error = ""
            else:
                logger.exception("UI session run_from_review failed")
                run.status = "failed"
                run.error = str(exc)
        finally:
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()
            self._persist_run(run)

    def snapshot_run(self, run: SessionRun) -> dict[str, Any]:
        bus = run.eureka_session.bus if run.eureka_session else None
        pipeline = bus.get_pipeline() if bus else None
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
        theory_state = bus.get_theory_state() if bus else None
        experiment_result = bus.get_experiment_result() if bus else None
        resource_analysis = bus.get("resource_analysis") if bus else None

        return {
            "run_id": run.run_id,
            "name": run.name,
            "session_id": run.eureka_session_id,
            "status": run.status,
            "error": run.error,
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
            },
            "result": _serialize_value(run.result) if run.result else None,
            "output_summary": _serialize_value(run.output_summary),
            "output_dir": run.output_dir,
            "theory_feedback": run.theory_feedback,
        }


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

    backend = str(config.get("llm_backend", "anthropic"))
    auth_mode = str(config.get("anthropic_auth_mode", "api_key"))

    # Resolve shortcut backends (openrouter, local) → (openai_compat, default_base_url)
    _canonical, _default_base = _BACKEND_ALIASES.get(backend, (backend, ""))
    if _canonical != backend:
        backend = _canonical

    if backend == "openai_compat":
        base_url = str(config.get("openai_compat_base_url", "") or "") or _default_base
        if not base_url:
            raise ValueError(
                "OPENAI_COMPAT_BASE_URL is not set. "
                "Configure it in the UI settings or .env before starting a session."
            )
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
    env_keys = ["ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL"]
    old_env = {key: os.environ.get(key) for key in env_keys}
    old_settings = {
        "anthropic_auth_mode": settings.anthropic_auth_mode,
        "ccproxy_port": settings.ccproxy_port,
    }
    proc = None

    try:
        settings.anthropic_auth_mode = str(config.get("anthropic_auth_mode", settings.anthropic_auth_mode))
        settings.ccproxy_port = int(config.get("ccproxy_port", settings.ccproxy_port))

        api_key = str(config.get("anthropic_api_key", "") or "")
        if api_key:
            os.environ["ANTHROPIC_API_KEY"] = api_key

        if config.get("llm_backend") == "anthropic" and config.get("anthropic_auth_mode") == "oauth":
            proc = maybe_start_ccproxy()

        yield
    finally:
        stop_ccproxy(proc)
        settings.anthropic_auth_mode = old_settings["anthropic_auth_mode"]
        settings.ccproxy_port = old_settings["ccproxy_port"]
        for key, value in old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def _test_llm_auth(config: dict[str, Any]) -> dict[str, Any]:
    """Initialize the configured client and perform a minimal text-generation check."""
    backend = str(config.get("llm_backend", "anthropic"))
    auth_mode = str(config.get("anthropic_auth_mode", "api_key"))
    model = str(
        config.get("eurekaclaw_fast_model")
        or config.get("openai_compat_model")
        or config.get("eurekaclaw_model")
        or ""
    )

    try:
        with _temporary_auth_env(config):
            client = create_client(
                backend=backend,
                anthropic_api_key=str(config.get("anthropic_api_key", "") or ""),
                openai_base_url=str(config.get("openai_compat_base_url", "") or ""),
                openai_api_key=str(config.get("openai_compat_api_key", "") or ""),
                openai_model=str(config.get("openai_compat_model", "") or ""),
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
        if parsed.path.startswith("/api/runs/"):
            run_id = parsed.path.split("/")[-1]
            run = self.state.get_run(run_id)
            if run is None:
                self._send_json({"error": "Run not found"}, status=HTTPStatus.NOT_FOUND)
                return
            self._send_json(self.state.snapshot_run(run))
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
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/review"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/review")
            payload = self._read_json()
            approved = bool(payload.get("approved", False))
            lemma_id = str(payload.get("lemma_id", "")).strip()
            reason = str(payload.get("reason", "")).strip()
            result = self.state.submit_review(run_id, approved, lemma_id, reason)
            if result.get("error"):
                self._send_json(result, status=HTTPStatus.BAD_REQUEST)
            else:
                self._send_json(result)
            return
        if parsed.path.startswith("/api/runs/") and parsed.path.endswith("/direction"):
            run_id = parsed.path.removeprefix("/api/runs/").removesuffix("/direction")
            payload = self._read_json()
            hypothesis = str(payload.get("hypothesis", "")).strip()
            if not hypothesis:
                self._send_json({"error": "hypothesis is required"}, status=HTTPStatus.BAD_REQUEST)
                return
            result = self.state.set_direction(run_id, hypothesis)
            if result.get("error"):
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

        if parsed.path == "/api/skills/install":
            payload = self._read_json()
            skillname = str(payload.get("skillname", "")).strip()
            result = _install_skill(skillname)
            status = HTTPStatus.OK if result.get("ok") else HTTPStatus.BAD_REQUEST
            self._send_json(result, status=status)
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

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
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
    server = bind_ui_server(host, port)
    actual_port = server.server_address[1]
    logger.info("Serving EurekaClaw UI at http://%s:%d", host, actual_port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down UI server")
    finally:
        server.server_close()
