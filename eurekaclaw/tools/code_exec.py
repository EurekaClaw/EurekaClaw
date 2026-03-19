"""Sandboxed code execution tool — subprocess with timeout, optional Docker."""

from __future__ import annotations

import asyncio
import json
import logging
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)

TIMEOUT_SECONDS = 30


class CodeExecutionTool(BaseTool):
    name = "execute_python"
    description = (
        "Execute Python code and return stdout/stderr. Used for numerical validation "
        "of theoretical bounds and running experiments. Code is run in a subprocess "
        "with a 30-second timeout."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "Python code to execute. Print results to stdout.",
                },
                "requirements": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Optional pip packages needed (e.g. ['numpy', 'scipy']).",
                },
            },
            "required": ["code"],
        }

    async def call(self, code: str, requirements: list[str] | None = None) -> str:
        if settings.use_docker_sandbox:
            return await self._docker_exec(code, requirements or [])
        return await self._subprocess_exec(code, requirements or [])

    async def _install_requirements(self, requirements: list[str]) -> str | None:
        """Install packages into the active .venv.

        Tries ``uv pip install --python <venv>`` first (fast, no subprocess
        resolution issues), then falls back to ``sys.executable -m pip``.
        Returns an error string on failure, or None on success.
        """
        venv_python = sys.executable
        try:
            proc = await asyncio.create_subprocess_exec(
                "uv", "pip", "install", "--quiet", "--python", venv_python, *requirements,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await asyncio.wait_for(proc.communicate(), timeout=60)
            if proc.returncode == 0:
                return None
            logger.warning("uv pip install failed (%s), falling back to pip", stderr.decode().strip())
        except FileNotFoundError:
            logger.debug("uv not found, falling back to sys.executable -m pip")
        except asyncio.TimeoutError:
            return "uv pip install timed out"

        # Fallback: use the venv's own Python to invoke pip
        try:
            proc = await asyncio.create_subprocess_exec(
                venv_python, "-m", "pip", "install", "--quiet", *requirements,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            await asyncio.wait_for(proc.communicate(), timeout=60)
        except asyncio.TimeoutError:
            return "pip install timed out"
        return None

    async def _subprocess_exec(self, code: str, requirements: list[str]) -> str:
        with tempfile.TemporaryDirectory() as tmpdir:
            code_path = Path(tmpdir) / "script.py"
            code_path.write_text(code)

            # Optionally install requirements
            if requirements:
                err = await self._install_requirements(requirements)
                if err:
                    return json.dumps({"error": err})

            try:
                proc = await asyncio.create_subprocess_exec(
                    sys.executable, str(code_path),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    cwd=tmpdir,
                )
                stdout, stderr = await asyncio.wait_for(
                    proc.communicate(), timeout=TIMEOUT_SECONDS
                )
                return json.dumps(
                    {
                        "returncode": proc.returncode,
                        "stdout": stdout.decode()[:4000],
                        "stderr": stderr.decode()[:1000],
                        "success": proc.returncode == 0,
                    },
                    indent=2,
                )
            except asyncio.TimeoutError:
                return json.dumps({"error": f"Execution timed out after {TIMEOUT_SECONDS}s"})
            except Exception as e:
                logger.exception("Code execution failed")
                return json.dumps({"error": str(e)})

    async def _docker_exec(self, code: str, requirements: list[str]) -> str:
        try:
            import docker  # type: ignore

            client = docker.from_env()
            install_cmd = f"pip install -q {' '.join(requirements)}" if requirements else "true"
            full_cmd = f"{install_cmd} && python3 -c {json.dumps(code)}"
            result = client.containers.run(
                "python:3.11-slim",
                command=["bash", "-c", full_cmd],
                mem_limit="512m",
                network_disabled=True,
                remove=True,
                timeout=TIMEOUT_SECONDS,
            )
            return json.dumps({"stdout": result.decode()[:4000], "success": True}, indent=2)
        except ImportError:
            logger.warning("Docker not available, falling back to subprocess")
            return await self._subprocess_exec(code, requirements)
        except Exception as e:
            return json.dumps({"error": str(e)})
