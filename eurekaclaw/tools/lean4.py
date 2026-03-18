"""Lean4 interface — invokes Lean4 subprocess for formal proof verification."""

from __future__ import annotations

import asyncio
import json
import logging
import tempfile
from pathlib import Path
from typing import Any

from eurekaclaw.config import settings
from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)

LEAN4_HEADER = """
import Mathlib
import Aesop

set_option maxHeartbeats 400000

"""


class Lean4Tool(BaseTool):
    name = "lean4_verify"
    description = (
        "Verify a formal Lean4 proof. Pass a complete Lean4 proof script. "
        "Returns whether the proof compiles successfully (no errors) or the error message."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "proof_code": {
                    "type": "string",
                    "description": (
                        "Complete Lean4 proof code. Should include theorem statement "
                        "and proof. The Mathlib import is prepended automatically."
                    ),
                },
                "theorem_name": {
                    "type": "string",
                    "description": "Name of the theorem being proved (for logging).",
                },
            },
            "required": ["proof_code"],
        }

    async def call(self, proof_code: str, theorem_name: str = "theorem") -> str:
        lean_bin = settings.lean4_bin
        full_code = LEAN4_HEADER + proof_code

        with tempfile.TemporaryDirectory() as tmpdir:
            lean_file = Path(tmpdir) / "proof.lean"
            lean_file.write_text(full_code)

            try:
                proc = await asyncio.create_subprocess_exec(
                    lean_bin, str(lean_file),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    cwd=tmpdir,
                )
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)
                output = (stdout + stderr).decode()

                if proc.returncode == 0 and "error" not in output.lower():
                    return json.dumps({
                        "verified": True,
                        "theorem": theorem_name,
                        "message": "Proof verified successfully by Lean4.",
                    })
                else:
                    return json.dumps({
                        "verified": False,
                        "theorem": theorem_name,
                        "lean4_output": output[:2000],
                    })
            except FileNotFoundError:
                return json.dumps({
                    "verified": False,
                    "error": f"Lean4 binary '{lean_bin}' not found. Install Lean4 or update LEAN4_BIN.",
                    "lean4_available": False,
                })
            except asyncio.TimeoutError:
                return json.dumps({"verified": False, "error": "Lean4 verification timed out (120s)"})
            except Exception as e:
                logger.exception("Lean4 verification failed")
                return json.dumps({"verified": False, "error": str(e)})
