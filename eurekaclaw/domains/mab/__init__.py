"""MAB (Multi-Armed Bandit) domain plugin for EurekaClaw."""

from __future__ import annotations

import json
import logging
from pathlib import Path

from eurekaclaw.domains.base import DomainPlugin
from eurekaclaw.domains import register_domain
from eurekaclaw.tools.registry import ToolRegistry

logger = logging.getLogger(__name__)

_SKILLS_DIR = Path(__file__).parent / "skills"
_BENCHMARK_DIR = Path(__file__).parent / "benchmark"


@register_domain
class MABDomainPlugin(DomainPlugin):
    """Domain plugin for stochastic multi-armed bandit theory research."""

    name = "mab"
    display_name = "Stochastic Multi-Armed Bandits"
    description = (
        "Regret bounds, concentration inequalities, and lower bounds for "
        "stochastic K-armed bandit problems (UCB, Thompson Sampling, etc.)"
    )
    keywords = [
        "bandit", "multi-armed", "mab", "ucb", "thompson", "regret",
        "exploration", "exploitation", "stochastic bandit",
    ]

    def register_tools(self, registry: ToolRegistry) -> None:
        from eurekaclaw.domains.mab.tools.bandit_tool import BanditExperimentTool
        registry.register(BanditExperimentTool())
        logger.debug("MAB domain: registered BanditExperimentTool")

    def get_skills_dirs(self) -> list[Path]:
        return [_SKILLS_DIR]

    def get_workflow_hint(self) -> str:
        from eurekaclaw.domains.mab.workflow import WORKFLOW_HINT
        return WORKFLOW_HINT

    def get_benchmark_problems(self, level: str) -> list[dict]:
        level_map = {"level1": "level1.json", "level2": "level2.json", "level3": "level3.json"}
        fname = level_map.get(level)
        if not fname:
            return []
        path = _BENCHMARK_DIR / fname
        if not path.exists():
            return []
        try:
            return json.loads(path.read_text())
        except Exception:
            return []
