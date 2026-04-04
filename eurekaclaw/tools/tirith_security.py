"""Tirith pre-exec security scanning wrapper.

Runs the tirith binary as a subprocess to scan commands and text for
content-level threats (homograph URLs, pipe-to-interpreter, terminal
injection, etc.).

Exit code is the verdict source of truth:
  0 = allow, 1 = block, 2 = warn

JSON stdout enriches findings/summary but never overrides the verdict.
Operational failures (spawn error, timeout, unknown exit code) respect
the fail_open config setting.

Auto-install: if tirith is not found on PATH or at the configured path,
it is automatically downloaded from GitHub releases to
$EUREKACLAW_DIR/bin/tirith.  The download always verifies SHA-256
checksums.  When cosign is available on PATH, provenance verification
(GitHub Actions workflow signature) is also performed.  If cosign is not
installed, the download proceeds with SHA-256 verification only.

Ported from NousResearch/hermes-agent tools/tirith_security.py
(PRs #1256, #1452, #1626).
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import platform
import shutil
import stat
import subprocess
import tarfile
import tempfile
import threading
import time
from typing import Any

from eurekaclaw.config import settings

logger = logging.getLogger(__name__)

_REPO = "sheeki03/tirith"

# Cosign provenance verification — pinned to the specific release workflow
_COSIGN_IDENTITY_REGEXP = (
    f"^https://github.com/{_REPO}/"
    r"\.github/workflows/release\.yml@refs/tags/v"
)
_COSIGN_ISSUER = "https://token.actions.githubusercontent.com"

# ---------------------------------------------------------------------------
# Auto-install
# ---------------------------------------------------------------------------

# Cached path after first resolution.
_resolved_path: str | None = None
_INSTALL_FAILED = object()  # sentinel
_install_failure_reason: str = ""

# Background install thread coordination
_install_lock = threading.Lock()
_install_thread: threading.Thread | None = None

# Disk-persistent failure marker — avoids retry across process restarts
_MARKER_TTL = 86400  # 24 hours


def _eurekaclaw_bin_dir() -> str:
    """Return $EUREKACLAW_DIR/bin, creating it if needed."""
    d = str(settings.eurekaclaw_dir / "bin")
    os.makedirs(d, exist_ok=True)
    return d


def _failure_marker_path() -> str:
    return str(settings.eurekaclaw_dir / ".tirith-install-failed")


def _is_install_failed_on_disk() -> bool:
    """Check if a recent install failure was persisted to disk."""
    try:
        p = _failure_marker_path()
        mtime = os.path.getmtime(p)
        if (time.time() - mtime) >= _MARKER_TTL:
            return False
        return True
    except OSError:
        return False


def _mark_install_failed(reason: str = ""):
    try:
        p = _failure_marker_path()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(reason)
    except OSError:
        pass


def _clear_install_failed():
    try:
        os.unlink(_failure_marker_path())
    except OSError:
        pass


def _detect_target() -> str | None:
    """Return the Rust target triple for the current platform, or None."""
    system = platform.system()
    machine = platform.machine().lower()

    if system == "Darwin":
        plat = "apple-darwin"
    elif system == "Linux":
        plat = "unknown-linux-gnu"
    else:
        return None

    if machine in ("x86_64", "amd64"):
        arch = "x86_64"
    elif machine in ("aarch64", "arm64"):
        arch = "aarch64"
    else:
        return None

    return f"{arch}-{plat}"


def _download_file(url: str, dest: str, timeout: int = 10):
    """Download a URL to a local file."""
    import urllib.request

    req = urllib.request.Request(url)
    token = os.getenv("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"token {token}")
    with urllib.request.urlopen(req, timeout=timeout) as resp, open(dest, "wb") as f:
        shutil.copyfileobj(resp, f)


def _verify_checksum(archive_path: str, checksums_path: str, archive_name: str) -> bool:
    """Verify SHA-256 of the archive against checksums.txt."""
    expected = None
    with open(checksums_path) as f:
        for line in f:
            parts = line.strip().split("  ", 1)
            if len(parts) == 2 and parts[1] == archive_name:
                expected = parts[0]
                break
    if not expected:
        logger.warning("No checksum entry for %s", archive_name)
        return False

    sha = hashlib.sha256()
    with open(archive_path, "rb") as fb:
        for chunk in iter(lambda: fb.read(8192), b""):
            sha.update(chunk)
    actual = sha.hexdigest()
    if actual != expected:
        logger.warning("Checksum mismatch: expected %s, got %s", expected, actual)
        return False
    return True


def _verify_cosign(checksums_path: str, sig_path: str, cert_path: str) -> bool | None:
    """Verify cosign provenance signature on checksums.txt.

    Returns:
        True  — cosign verified successfully
        False — cosign found but verification failed (abort install)
        None  — cosign not available
    """
    cosign = shutil.which("cosign")
    if not cosign:
        return None

    try:
        result = subprocess.run(
            [
                cosign, "verify-blob",
                "--certificate", cert_path,
                "--signature", sig_path,
                "--certificate-identity-regexp", _COSIGN_IDENTITY_REGEXP,
                "--certificate-oidc-issuer", _COSIGN_ISSUER,
                checksums_path,
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0:
            logger.info("cosign provenance verification passed")
            return True
        logger.warning(
            "cosign verification failed (exit %d): %s",
            result.returncode,
            result.stderr.strip(),
        )
        return False
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.warning("cosign execution failed: %s", exc, exc_info=True)
        return None


def _install_tirith(*, log_failures: bool = True) -> tuple[str | None, str]:
    """Download and install tirith to $EUREKACLAW_DIR/bin/tirith.

    Returns (installed_path, failure_reason). On success failure_reason is "".
    """
    log = logger.warning if log_failures else logger.debug

    target = _detect_target()
    if not target:
        log(
            "tirith auto-install: unsupported platform %s/%s",
            platform.system(),
            platform.machine(),
        )
        return None, "unsupported_platform"

    archive_name = f"tirith-{target}.tar.gz"
    base_url = f"https://github.com/{_REPO}/releases/latest/download"

    tmpdir = tempfile.mkdtemp(prefix="tirith-install-")
    try:
        archive_path = os.path.join(tmpdir, archive_name)
        checksums_path = os.path.join(tmpdir, "checksums.txt")

        logger.info("tirith not found — downloading latest release for %s...", target)

        try:
            _download_file(f"{base_url}/{archive_name}", archive_path)
            _download_file(f"{base_url}/checksums.txt", checksums_path)
        except Exception as exc:
            log("tirith download failed: %s", exc, exc_info=True)
            return None, "download_failed"

        # Cosign provenance: preferred but not mandatory (PR #1626).
        cosign_verified = False
        if shutil.which("cosign"):
            sig_path = os.path.join(tmpdir, "checksums.txt.sig")
            cert_path = os.path.join(tmpdir, "checksums.txt.pem")
            try:
                _download_file(f"{base_url}/checksums.txt.sig", sig_path)
                _download_file(f"{base_url}/checksums.txt.pem", cert_path)
            except Exception as exc:
                logger.info(
                    "cosign artifacts unavailable (%s), proceeding with SHA-256 only",
                    exc,
                )
            else:
                cosign_result = _verify_cosign(checksums_path, sig_path, cert_path)
                if cosign_result is True:
                    cosign_verified = True
                elif cosign_result is False:
                    # Verification explicitly rejected — release may be tampered.
                    log("tirith install aborted: cosign provenance verification failed")
                    return None, "cosign_verification_failed"
                # None = cosign execution failure → proceed with SHA-256 only.
        else:
            logger.info(
                "cosign not on PATH — installing tirith with SHA-256 verification only "
                "(install cosign for full supply chain verification)"
            )

        if not _verify_checksum(archive_path, checksums_path, archive_name):
            return None, "checksum_failed"

        with tarfile.open(archive_path, "r:gz") as tar:
            for member in tar.getmembers():
                if (
                    member.name == "tirith" or member.name.endswith("/tirith")
                ) and ".." not in member.name:
                    member.name = "tirith"
                    tar.extract(member, tmpdir)
                    break
            else:
                log("tirith binary not found in archive")
                return None, "binary_not_in_archive"

        src = os.path.join(tmpdir, "tirith")
        dest = os.path.join(_eurekaclaw_bin_dir(), "tirith")
        shutil.move(src, dest)
        os.chmod(
            dest,
            os.stat(dest).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH,
        )

        verification = "cosign + SHA-256" if cosign_verified else "SHA-256 only"
        logger.info("tirith installed to %s (%s)", dest, verification)
        return dest, ""

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _is_explicit_path(configured_path: str) -> bool:
    """Return True if the user explicitly configured a non-default tirith path."""
    return configured_path != "tirith"


def _resolve_tirith_path() -> str:
    """Resolve the tirith binary path, auto-installing if necessary.

    If the user explicitly set a path (anything other than the bare "tirith"
    default), that path is authoritative — no auto-download.

    For the default "tirith":
    1. PATH lookup via shutil.which
    2. $EUREKACLAW_DIR/bin/tirith (previously auto-installed)
    3. Auto-install from GitHub releases

    Re-checks PATH/local bin even after a previous failure, so a manual
    install is picked up without restart.
    """
    global _resolved_path, _install_failure_reason

    # Fast path: successfully resolved on a previous call.
    if _resolved_path is not None and _resolved_path is not _INSTALL_FAILED:
        return _resolved_path

    configured = settings.tirith_bin
    explicit = _is_explicit_path(configured)
    expanded = os.path.expanduser(configured)

    # Explicit path: check it and stop. Never auto-download a replacement.
    if explicit:
        if os.path.isfile(expanded) and os.access(expanded, os.X_OK):
            _resolved_path = expanded
            return expanded
        found = shutil.which(expanded)
        if found:
            _resolved_path = found
            return found
        logger.warning(
            "Configured tirith path %r not found; scanning disabled",
            configured,
        )
        _resolved_path = _INSTALL_FAILED
        _install_failure_reason = "explicit_path_missing"
        return expanded

    # Default "tirith" — always re-run cheap local checks so a manual
    # install is picked up even after a previous network failure.
    found = shutil.which("tirith")
    if found:
        _resolved_path = found
        _install_failure_reason = ""
        _clear_install_failed()
        return found

    local_bin = os.path.join(_eurekaclaw_bin_dir(), "tirith")
    if os.path.isfile(local_bin) and os.access(local_bin, os.X_OK):
        _resolved_path = local_bin
        _install_failure_reason = ""
        _clear_install_failed()
        return local_bin

    # Local checks failed. If a previous install attempt already failed,
    # skip the network retry.
    if _resolved_path is _INSTALL_FAILED:
        return expanded

    # Check disk failure marker before attempting network download.
    if _is_install_failed_on_disk():
        _resolved_path = _INSTALL_FAILED
        return expanded

    # If a background install thread is running, don't start a parallel one.
    if _install_thread is not None and _install_thread.is_alive():
        return expanded

    installed, reason = _install_tirith()
    if installed:
        _resolved_path = installed
        _install_failure_reason = ""
        _clear_install_failed()
        return installed

    _resolved_path = _INSTALL_FAILED
    _install_failure_reason = reason
    _mark_install_failed(reason)
    return expanded


def ensure_installed(*, log_failures: bool = True):
    """Ensure tirith is available, downloading in background if needed.

    Quick PATH/local checks are synchronous; network download runs in a
    daemon thread so startup never blocks. Safe to call multiple times.

    Pass log_failures=False for quiet startup prefetch (PR #1452 pattern).
    """
    global _resolved_path, _install_thread

    if not settings.tirith_enabled:
        return None

    # Already resolved from a previous call
    if _resolved_path is not None and _resolved_path is not _INSTALL_FAILED:
        if os.path.isfile(_resolved_path) and os.access(_resolved_path, os.X_OK):
            return _resolved_path
        return None

    configured = settings.tirith_bin
    explicit = _is_explicit_path(configured)
    expanded = os.path.expanduser(configured)

    # Explicit path: synchronous check only, no download
    if explicit:
        if os.path.isfile(expanded) and os.access(expanded, os.X_OK):
            _resolved_path = expanded
            return expanded
        found = shutil.which(expanded)
        if found:
            _resolved_path = found
            return found
        _resolved_path = _INSTALL_FAILED
        return None

    # Default "tirith" — quick local checks first
    found = shutil.which("tirith")
    if found:
        _resolved_path = found
        _clear_install_failed()
        return found

    local_bin = os.path.join(_eurekaclaw_bin_dir(), "tirith")
    if os.path.isfile(local_bin) and os.access(local_bin, os.X_OK):
        _resolved_path = local_bin
        _clear_install_failed()
        return local_bin

    if _resolved_path is _INSTALL_FAILED:
        return None

    if _is_install_failed_on_disk():
        _resolved_path = _INSTALL_FAILED
        return None

    # Need to download — launch background thread so startup doesn't block
    if _install_thread is None or not _install_thread.is_alive():

        def _bg():
            global _resolved_path, _install_failure_reason
            with _install_lock:
                if _resolved_path is not None and _resolved_path is not _INSTALL_FAILED:
                    return

                # Re-check local paths (may have been installed by another process)
                f = shutil.which("tirith")
                if f:
                    _resolved_path = f
                    return

                lb = os.path.join(_eurekaclaw_bin_dir(), "tirith")
                if os.path.isfile(lb) and os.access(lb, os.X_OK):
                    _resolved_path = lb
                    return

                installed, reason = _install_tirith(log_failures=log_failures)
                if installed:
                    _resolved_path = installed
                    _install_failure_reason = ""
                    _clear_install_failed()
                else:
                    _resolved_path = _INSTALL_FAILED
                    _install_failure_reason = reason
                    _mark_install_failed(reason)

        _install_thread = threading.Thread(target=_bg, daemon=True)
        _install_thread.start()

    return None


# ---------------------------------------------------------------------------
# Main API
# ---------------------------------------------------------------------------

_MAX_FINDINGS = 50
_MAX_SUMMARY_LEN = 500


def check_security(text: str, context: str = "paste") -> dict[str, Any]:
    """Run tirith security scan on text.

    Exit code determines action (0=allow, 1=block, 2=warn). JSON enriches
    findings/summary. Spawn failures and timeouts respect fail_open config.

    Args:
        text: The text to scan (code, URL, command, etc.)
        context: "exec" for commands, "paste" for untrusted text

    Returns:
        {"action": "allow"|"warn"|"block", "findings": [...], "summary": str}
    """
    if not settings.tirith_enabled:
        return {"action": "allow", "findings": [], "summary": ""}

    tirith_path = _resolve_tirith_path()
    timeout = settings.tirith_timeout
    fail_open = settings.tirith_fail_open

    try:
        if context == "exec":
            cmd = [
                tirith_path, "check", "--json", "--non-interactive",
                "--shell", "posix", "--", text,
            ]
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=timeout,
            )
        else:
            cmd = [tirith_path, "paste", "--json", "--non-interactive"]
            result = subprocess.run(
                cmd, input=text, capture_output=True, text=True, timeout=timeout,
            )
    except OSError as exc:
        logger.warning("tirith spawn failed: %s", exc, exc_info=True)
        if fail_open:
            return {"action": "allow", "findings": [], "summary": f"tirith unavailable: {exc}"}
        return {"action": "block", "findings": [], "summary": f"tirith spawn failed (fail-closed): {exc}"}
    except subprocess.TimeoutExpired:
        logger.warning("tirith timed out after %ds", timeout)
        if fail_open:
            return {"action": "allow", "findings": [], "summary": f"tirith timed out ({timeout}s)"}
        return {"action": "block", "findings": [], "summary": f"tirith timed out (fail-closed)"}

    # Map exit code to action (source of truth)
    exit_code = result.returncode
    if exit_code == 0:
        action = "allow"
    elif exit_code == 1:
        action = "block"
    elif exit_code == 2:
        action = "warn"
    else:
        logger.warning("tirith returned unexpected exit code %d", exit_code)
        if fail_open:
            return {
                "action": "allow",
                "findings": [],
                "summary": f"tirith exit code {exit_code} (fail-open)",
            }
        return {
            "action": "block",
            "findings": [],
            "summary": f"tirith exit code {exit_code} (fail-closed)",
        }

    # Parse JSON for enrichment (never overrides the exit code verdict)
    findings: list[dict[str, Any]] = []
    summary = ""
    try:
        data = json.loads(result.stdout) if result.stdout.strip() else {}
        raw_findings = data.get("findings", [])
        findings = raw_findings[:_MAX_FINDINGS]
        summary = (data.get("summary", "") or "")[:_MAX_SUMMARY_LEN]
    except (json.JSONDecodeError, AttributeError):
        logger.debug("tirith JSON parse failed, using exit code only")
        if action == "block":
            summary = "security issue detected (details unavailable)"
        elif action == "warn":
            summary = "security warning detected (details unavailable)"

    return {"action": action, "findings": findings, "summary": summary}
