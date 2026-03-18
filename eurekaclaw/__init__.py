"""
EurekaClaw — Multi-agent system for theoretical research.

Synthesizes proof-heavy, formalism-rich, math-dense research domains (ML theory,
physics, CS theory, pure math) via a layered agent architecture with a unique
Theory Agent proof-reasoning loop.
"""

from __future__ import annotations

__version__ = "0.1.0"
__all__ = ["EurekaSession", "run_research"]


def __getattr__(name: str):
    """Lazy-load top-level names to avoid heavy import side effects at import time."""
    if name in ("EurekaSession", "run_research"):
        from eurekaclaw.main import EurekaSession, run_research  # noqa: F401
        globals()["EurekaSession"] = EurekaSession
        globals()["run_research"] = run_research
        return globals()[name]
    raise AttributeError(f"module 'eurekaclaw' has no attribute {name!r}")
