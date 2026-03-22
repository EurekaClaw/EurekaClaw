"""DomainPlugin — abstract base class for research domain plugins.

Each domain plugin packages everything needed to do research in a specific
mathematical/ML sub-field: simulation environments, domain-specific tools,
skills, benchmark problems, and workflow guidance for the agents.

Architecture:
    EurekaClaw (general pipeline)
        └── DomainPlugin (e.g. MABDomainPlugin)
                ├── register_tools()   → injects domain tools into ToolRegistry
                ├── get_skills_dirs()  → extra skill dirs the SkillRegistry loads
                ├── get_workflow_hint()→ research guidance injected into agent prompts
                └── get_benchmark()   → benchmark problems for evaluation

To add a new domain (e.g. game theory):
    1. Create eurekaclaw/domains/game_theory/__init__.py
    2. Subclass DomainPlugin, set name / keywords / description
    3. Implement register_tools() and the other methods
    4. Decorate with @register_domain
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from eurekaclaw.tools.registry import ToolRegistry

class DomainPlugin(ABC):
    """Abstract base class for all domain plugins."""

    # ── Class-level metadata (set on subclasses) ─────────────────────────────

    #: Short identifier, e.g. "mab", "game_theory", "stat_learning"
    name: str = ""

    #: Human-readable name shown in logs
    display_name: str = ""

    #: Keywords used for auto-detection from a domain / query string
    keywords: list[str] = []

    #: One-line description of what this domain covers
    description: str = ""

    # ── Interface ─────────────────────────────────────────────────────────────

    @abstractmethod
    def register_tools(self, registry: ToolRegistry) -> None:
        """Register domain-specific tools into the shared ToolRegistry.

        Called once by MetaOrchestrator after the default tools are loaded.
        """
        ...

    def get_skills_dirs(self) -> list[Path]:
        """Return extra skill directories the SkillRegistry should load from.

        Default: returns the `skills/` subdirectory next to __init__.py.
        """
        return []

    @abstractmethod
    def get_workflow_hint(self) -> str:
        """Return domain-specific guidance injected into agent system prompts.

        Should describe:
        - What makes this domain special (notation, conventions)
        - Which tools to prefer
        - How to structure proofs / experiments in this domain
        """
        ...

    def get_benchmark_problems(self, level: str) -> list[dict]:
        """Return benchmark problems for the given level ('level1'|'level2'|'level3').

        Returns an empty list if no benchmark is defined.
        """
        return []

    # ── Helpers ───────────────────────────────────────────────────────────────

    def __repr__(self) -> str:
        return f"<DomainPlugin: {self.name}>"
