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
    "eurekaclaw_mode": "EUREKACLAW_MODE",
    "gate_mode": "GATE_MODE",
    "ccproxy_port": "CCPROXY_PORT",
    "theory_max_iterations": "THEORY_MAX_ITERATIONS",
    "output_format": "OUTPUT_FORMAT",
    "metaclaw_dir": "METACLAW_DIR",
    # Token limits
    "max_tokens_agent": "MAX_TOKENS_AGENT",
    "max_tokens_prover": "MAX_TOKENS_PROVER",
    "max_tokens_planner": "MAX_TOKENS_PLANNER",
    "max_tokens_decomposer": "MAX_TOKENS_DECOMPOSER",
    "max_tokens_formalizer": "MAX_TOKENS_FORMALIZER",
    "max_tokens_verifier": "MAX_TOKENS_VERIFIER",
    "max_tokens_compress": "MAX_TOKENS_COMPRESS",
}


@dataclass
class SessionRun:
    """Tracks a running or completed session for UI polling."""

    run_id: str
    input_spec: InputSpec
    status: str = "queued"
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    started_at: datetime | None = None
    completed_at: datetime | None = None
    error: str = ""
    result: ResearchOutput | None = None
    eureka_session: EurekaSession | None = None
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

    def create_run(self, input_spec: InputSpec) -> SessionRun:
        run = SessionRun(run_id=str(uuid.uuid4()), input_spec=input_spec)
        with self._lock:
            self.runs[run.run_id] = run
        return run

    def get_run(self, run_id: str) -> SessionRun | None:
        with self._lock:
            return self.runs.get(run_id)

    def list_runs(self) -> list[SessionRun]:
        with self._lock:
            return sorted(self.runs.values(), key=lambda run: run.created_at, reverse=True)

    def start_run(self, run: SessionRun) -> None:
        thread = threading.Thread(target=self._execute_run, args=(run.run_id,), daemon=True)
        thread.start()

    def _execute_run(self, run_id: str) -> None:
        run = self.get_run(run_id)
        if run is None:
            return

        run.status = "running"
        run.started_at = datetime.utcnow()
        run.updated_at = datetime.utcnow()
        session = EurekaSession()
        run.eureka_session = session

        try:
            with _temporary_auth_env(_config_payload()):
                result = asyncio.run(session.run(run.input_spec))
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
            logger.exception("UI session run failed")
            run.status = "failed"
            run.error = str(exc)
        finally:
            run.completed_at = datetime.utcnow()
            run.updated_at = datetime.utcnow()

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
            "status": run.status,
            "error": run.error,
            "created_at": run.created_at.isoformat(),
            "started_at": run.started_at.isoformat() if run.started_at else None,
            "completed_at": run.completed_at.isoformat() if run.completed_at else None,
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
        }


def _config_payload() -> dict[str, Any]:
    return {
        field_name: str(getattr(settings, field_name))
        if isinstance(getattr(settings, field_name), Path)
        else getattr(settings, field_name)
        for field_name in _CONFIG_FIELDS
    }


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
        }
        for skill in skills
    ]


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
            input_spec = InputSpec.model_validate(payload)
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
                elif isinstance(current, int):
                    setattr(settings, field_name, int(rendered))
                else:
                    setattr(settings, field_name, rendered)

            _write_env_updates(_ENV_PATH, config_updates)
            self._send_json({"config": _config_payload(), "saved": True})
            return

        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        # Silence noisy polling GETs to /api/runs/<id> (status-check endpoint)
        msg = format % args
        if '"GET /api/runs/' in msg and '" 200 -' in msg:
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


def serve_ui(host: str = "127.0.0.1", port: int = 8080) -> None:
    """Start the EurekaClaw UI server."""
    frontend_dir = _FRONTEND_DIR if _FRONTEND_DIR.exists() else _DEV_FRONTEND_DIR
    if not frontend_dir.exists():
        raise FileNotFoundError(f"Frontend directory not found: {frontend_dir}")

    state = UIServerState()
    handler = partial(UIRequestHandler, state=state, directory=str(frontend_dir))
    server = ThreadingHTTPServer((host, port), handler)
    logger.info("Serving EurekaClaw UI at http://%s:%d", host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down UI server")
    finally:
        server.server_close()
