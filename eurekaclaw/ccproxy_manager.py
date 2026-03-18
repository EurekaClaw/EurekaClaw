"""ccproxy lifecycle management for OAuth-based Anthropic access.

Allows users with a Claude Pro/Max subscription to run EurekaClaw without
a separate Anthropic API key, by reusing Claude Code's OAuth tokens via
ccproxy.

ccproxy is invoked via subprocess (not Python imports) so the
``ccproxy-api`` package is truly optional at runtime.
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import time

logger = logging.getLogger(__name__)


# =============================================================================
# Availability & auth checks
# =============================================================================


def _ccproxy_exe() -> str | None:
    """Return the path to the ccproxy binary, or None if not found.

    Checks PATH first, then the current Python environment's bin directory
    (handles conda envs where newly installed binaries may not be visible
    to shutil.which immediately after pip install).
    """
    found = shutil.which("ccproxy")
    if found:
        return found
    import sys as _sys

    candidate = os.path.join(os.path.dirname(_sys.executable), "ccproxy")
    if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
        return candidate
    return None


def is_ccproxy_available() -> bool:
    """Check whether the ``ccproxy`` CLI binary is available."""
    return _ccproxy_exe() is not None


def _is_editable_install() -> bool:
    """Return True if eurekaclaw was installed in editable/development mode."""
    try:
        import json
        import importlib.metadata as _meta

        for dist in _meta.distributions():
            name = dist.metadata.get("Name", "")
            if name.lower() != "eurekaclaw":
                continue
            direct_url = dist.read_text("direct_url.json")
            if direct_url is not None:
                data = json.loads(direct_url)
                if data.get("dir_info", {}).get("editable", False) is True:
                    return True
    except Exception:
        pass
    return False


def _oauth_install_hint() -> str:
    """Return the appropriate install command depending on install method."""
    if _is_editable_install():
        return "pip install -e '.[oauth]'"
    return "pip install 'eurekaclaw[oauth]'"


def _summarize_auth_output(raw: str) -> str:
    """Extract key fields from ccproxy auth status output into a one-line summary."""
    import re as _re

    clean = _re.sub(r"\x1b\[[0-9;]*m", "", raw)
    fields: dict[str, str] = {}
    for line in clean.splitlines():
        m = _re.match(r"\s*(.+?)\s{2,}(.+)", line)
        if not m:
            continue
        key, val = m.group(1).strip(), m.group(2).strip()
        if key in ("Email", "Subscription", "Subscription Status"):
            fields[key.lower().replace(" ", "_")] = val

    email = fields.get("email", "")
    sub = fields.get("subscription", "")
    status = fields.get("subscription_status", "")

    if email:
        detail = ", ".join(filter(None, [sub, status]))
        return f"{email} ({detail})" if detail else email
    return "Authenticated"


def check_ccproxy_auth(provider: str = "claude_api") -> tuple[bool, str]:
    """Check if ccproxy has valid OAuth credentials.

    Args:
        provider: ccproxy provider name — ``"claude_api"`` for Anthropic.

    Returns:
        ``(is_valid, message)`` tuple.
    """
    try:
        exe = _ccproxy_exe() or "ccproxy"
        result = subprocess.run(
            [exe, "auth", "status", provider],
            capture_output=True,
            text=True,
            timeout=10,
        )
        import re as _re

        raw = (result.stdout + result.stderr).strip()
        clean = _re.sub(r"\x1b\[[0-9;]*m", "", raw)

        status_lines = [
            line
            for line in clean.splitlines()
            if line.strip()
            and not _re.match(r"\d{4}-\d{2}-\d{2}", line.strip())
            and "warning" not in line.lower()
            and "plugin" not in line.lower()
        ]
        status_msg = " ".join(status_lines).strip()

        if result.returncode != 0 or "not authenticated" in clean.lower():
            return False, status_msg or "Not authenticated"

        summary = _summarize_auth_output(result.stdout)
        return True, summary or "Authenticated"
    except FileNotFoundError:
        return False, "ccproxy not found"
    except subprocess.TimeoutExpired:
        return False, "Auth check timed out"
    except Exception as exc:
        return False, f"Auth check failed: {exc}"


# =============================================================================
# Process management
# =============================================================================


def is_ccproxy_running(port: int) -> bool:
    """Check if ccproxy is already serving on the given port."""
    import httpx

    try:
        resp = httpx.get(f"http://127.0.0.1:{port}/health/live", timeout=2.0)
        return resp.status_code == 200
    except (httpx.ConnectError, httpx.TimeoutException, OSError):
        return False


def start_ccproxy(port: int) -> subprocess.Popen:
    """Start ccproxy serve as a background process.

    Raises:
        RuntimeError: If ccproxy fails to become healthy within 30 seconds.
        FileNotFoundError: If ccproxy binary is not found.
    """
    exe = _ccproxy_exe() or "ccproxy"
    proc = subprocess.Popen(
        [exe, "serve", "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(
                f"ccproxy exited immediately with code {proc.returncode}"
            )
        if is_ccproxy_running(port):
            return proc
        time.sleep(0.3)

    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
    raise RuntimeError("ccproxy did not become healthy within 30 seconds")


def stop_ccproxy(proc: subprocess.Popen | None) -> None:
    """Gracefully stop a ccproxy process. Safe to call with None."""
    if proc is None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    except Exception:
        pass


def ensure_ccproxy(port: int) -> subprocess.Popen | None:
    """Ensure ccproxy is running — reuse existing or start new.

    Returns:
        Popen handle if we started a new process, None if already running.
    """
    if is_ccproxy_running(port):
        logger.debug("ccproxy already running on port %d", port)
        return None
    return start_ccproxy(port)


# =============================================================================
# Environment setup
# =============================================================================


def setup_ccproxy_env(port: int) -> None:
    """Point the Anthropic client at ccproxy by setting environment variables.

    ``anthropic.AsyncAnthropic`` reads ``ANTHROPIC_BASE_URL`` automatically,
    so no code changes are needed in the adapter.
    """
    os.environ["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{port}/claude"
    os.environ["ANTHROPIC_API_KEY"] = "ccproxy-oauth"


# =============================================================================
# OAuth header patch
# =============================================================================


def _patch_ccproxy_oauth_header() -> None:
    """Auto-patch ccproxy's adapter to send the correct OAuth beta header.

    ccproxy 0.2.4 hardcodes ``computer-use-2025-01-24`` as the
    ``anthropic-beta`` header, which causes:
    - Missing ``oauth-2025-04-20`` → 401 from Anthropic
    - ``computer-use-2025-01-24`` incompatible with OAuth auth → 400

    The patch is idempotent.
    """
    import pathlib
    import re

    try:
        ccproxy_bin = _ccproxy_exe()
        if not ccproxy_bin:
            return

        shebang = pathlib.Path(ccproxy_bin).read_text().splitlines()[0]
        python_exe = shebang.lstrip("#!").strip()

        result = subprocess.run(
            [
                python_exe, "-c",
                "import inspect, ccproxy.plugins.claude_api.adapter as m; print(inspect.getfile(m))",
            ],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return
        src_file = pathlib.Path(result.stdout.strip())
        if not src_file.exists():
            return

        text = src_file.read_text()

        correct = 'filtered_headers["anthropic-beta"] = "oauth-2025-04-20"'
        cli_marker = "cli_headers = self._collect_cli_headers()"
        if correct in text and text.index(correct) > text.index(cli_marker):
            return  # Already correctly patched

        patched = re.sub(
            r'\s*filtered_headers\["anthropic-beta"\]\s*=\s*"[^"]*"\n',
            "\n",
            text,
        )
        insert_after = 'filtered_headers[lk] = value\n'
        replacement = (
            'filtered_headers[lk] = value\n\n'
            '        # oauth-2025-04-20: required for OAuth Bearer token auth\n'
            '        filtered_headers["anthropic-beta"] = "oauth-2025-04-20"\n'
        )
        patched = patched.replace(insert_after, replacement, 1)

        if patched == text:
            return

        src_file.write_text(patched)
        for pyc in src_file.parent.glob("__pycache__/adapter*.pyc"):
            pyc.unlink(missing_ok=True)
        logger.info("Auto-patched ccproxy adapter: set anthropic-beta=oauth-2025-04-20")
    except Exception as exc:
        logger.warning("Could not auto-patch ccproxy adapter: %s", exc)


# =============================================================================
# High-level entry point
# =============================================================================


def maybe_start_ccproxy() -> subprocess.Popen | None:
    """Conditionally start ccproxy based on EurekaClaw settings.

    Reads ``settings.anthropic_auth_mode`` and ``settings.ccproxy_port``.
    When auth mode is ``"oauth"``:
    - Verifies ccproxy is installed and authenticated
    - Starts ccproxy (or reuses an existing instance on the same port)
    - Sets ``ANTHROPIC_BASE_URL`` / ``ANTHROPIC_API_KEY`` in the environment

    Returns:
        Popen handle if we started ccproxy, None if not needed or already running.

    Raises:
        RuntimeError: If ccproxy is unavailable or not authenticated.
    """
    from eurekaclaw.config import settings

    if settings.anthropic_auth_mode != "oauth":
        return None

    if not is_ccproxy_available():
        raise RuntimeError(
            "ccproxy is required for ANTHROPIC_AUTH_MODE=oauth but was not found.\n"
            f"Install it with: {_oauth_install_hint()}"
        )

    authed, msg = check_ccproxy_auth("claude_api")
    if not authed:
        raise RuntimeError(
            f"ccproxy Anthropic OAuth not authenticated: {msg}\n"
            "Run: ccproxy auth login claude_api"
        )

    port = settings.ccproxy_port
    if not (1 <= port <= 65535):
        raise ValueError(f"Invalid CCPROXY_PORT: {port}. Must be 1-65535.")

    _patch_ccproxy_oauth_header()

    proc = ensure_ccproxy(port)
    setup_ccproxy_env(port)

    if proc:
        logger.info("Started ccproxy on port %d", port)
    else:
        logger.info("Reusing existing ccproxy on port %d", port)
    return proc
