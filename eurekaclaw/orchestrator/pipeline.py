"""PipelineManager — builds a TaskPipeline from a YAML spec file."""

from __future__ import annotations

import re
import uuid
from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped]

from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import Task, TaskPipeline

# Bundled default spec, shipped with the package
_DEFAULT_SPEC = Path(__file__).parent / "pipelines" / "default_pipeline.yaml"


class PipelineManager:
    """Builds a TaskPipeline from a declarative YAML spec.

    The spec lists stages with symbolic ``depends_on`` names; this class
    resolves those names to runtime UUIDs and substitutes ``{{brief.*}}``
    placeholders in ``inputs`` values.
    """

    def build(
        self,
        brief: ResearchBrief,
        spec_path: Path | None = None,
    ) -> TaskPipeline:
        """Build a TaskPipeline from *spec_path* (defaults to default_pipeline.yaml).

        Args:
            brief: The ResearchBrief for this session.  Used for placeholder
                   substitution and as the source of session_id.
            spec_path: Path to a pipeline YAML spec.  When omitted the bundled
                       ``default_pipeline.yaml`` is used.
        """
        path = spec_path or _DEFAULT_SPEC
        spec = self._load_spec(path)
        return self._build_from_spec(spec, brief)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _load_spec(self, path: Path) -> dict[str, Any]:
        with path.open() as fh:
            return yaml.safe_load(fh)

    def _build_from_spec(
        self, spec: dict[str, Any], brief: ResearchBrief
    ) -> TaskPipeline:
        pipeline_id = str(uuid.uuid4())
        stages: list[dict[str, Any]] = spec.get("stages", [])

        # First pass: assign a UUID to each stage name
        name_to_id: dict[str, str] = {s["name"]: str(uuid.uuid4()) for s in stages}

        tasks: list[Task] = []
        for stage in stages:
            name: str = stage["name"]
            depends_on_names: list[str] = stage.get("depends_on", [])

            tasks.append(
                Task(
                    task_id=name_to_id[name],
                    name=name,
                    agent_role=stage["agent_role"],
                    description=stage.get("description", ""),
                    inputs=self._resolve_inputs(stage.get("inputs", {}), brief),
                    depends_on=[name_to_id[n] for n in depends_on_names],
                    gate_required=bool(stage.get("gate_required", False)),
                    max_retries=int(stage.get("max_retries", 3)),
                )
            )

        return TaskPipeline(
            pipeline_id=pipeline_id,
            session_id=brief.session_id,
            tasks=tasks,
        )

    def _resolve_inputs(
        self, inputs: dict[str, Any], brief: ResearchBrief
    ) -> dict[str, Any]:
        """Substitute ``{{brief.<field>}}`` placeholders in input values."""
        resolved: dict[str, Any] = {}
        for key, value in inputs.items():
            if isinstance(value, str):
                value = re.sub(
                    r"\{\{brief\.(\w+)\}\}",
                    lambda m: str(getattr(brief, m.group(1), "")),
                    value,
                )
            resolved[key] = value
        return resolved
