"""Sandboxed code execution tool — subprocess with timeout, optional Docker."""

from __future__ import annotations

import asyncio
import json
import logging
import subprocess
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

    async def _subprocess_exec(self, code: str, requirements: list[str]) -> str:
        with tempfile.TemporaryDirectory() as tmpdir:
            code_path = Path(tmpdir) / "script.py"
            code_path.write_text(code)

            # Optionally install requirements
            if requirements:
                try:
                    proc = await asyncio.create_subprocess_exec(
                        "pip", "install", "--quiet", *requirements,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                    )
                    await asyncio.wait_for(proc.communicate(), timeout=60)
                except asyncio.TimeoutError:
                    return json.dumps({"error": "pip install timed out"})

            try:
                proc = await asyncio.create_subprocess_exec(
                    "python3", str(code_path),
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
