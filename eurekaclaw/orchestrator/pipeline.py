"""PipelineManager — builds and manages the tasks.json pipeline."""

from __future__ import annotations

import uuid

from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import Task, TaskPipeline


class PipelineManager:
    """Builds the standard research pipeline from a ResearchBrief."""

    def build(self, brief: ResearchBrief) -> TaskPipeline:
        """Build the standard pipeline.

        Stages: survey → ideation → direction_planning → theory → experiment → writer
        """
        pipeline_id = str(uuid.uuid4())

        # Allocate task IDs up front so depends_on can reference them
        t_survey     = str(uuid.uuid4())
        t_ideation   = str(uuid.uuid4())
        t_dir_plan   = str(uuid.uuid4())
        t_theory     = str(uuid.uuid4())
        t_experiment = str(uuid.uuid4())
        t_writer     = str(uuid.uuid4())

        tasks = [
            Task(
                task_id=t_survey,
                name="survey",
                agent_role="survey",
                description="Literature survey: arXiv, Semantic Scholar, citation graph",
                inputs={"domain": brief.domain, "query": brief.query},
                depends_on=[],
                gate_required=False,
            ),
            Task(
                task_id=t_ideation,
                name="ideation",
                agent_role="ideation",
                description="Generate research directions from survey findings",
                inputs={"domain": brief.domain},
                depends_on=[t_survey],
                gate_required=False,
            ),
            Task(
                task_id=t_dir_plan,
                name="direction_selection_gate",
                agent_role="orchestrator",
                description="Select research direction to pursue",
                inputs={},
                depends_on=[t_ideation],
                gate_required=False,
            ),
            Task(
                task_id=t_theory,
                name="theory",
                agent_role="theory",
                description="Theory Agent inner loop: formalize → prove → verify → refine",
                inputs={"domain": brief.domain},
                depends_on=[t_dir_plan],
                gate_required=False,
                max_retries=1,
            ),
            Task(
                task_id=t_experiment,
                name="experiment",
                agent_role="experiment",
                description="Empirical validation of theoretical bounds",
                inputs={},
                depends_on=[t_theory],
                gate_required=False,
                max_retries=0,  # retrying won't help: theorem is fixed, structural skip won't change
            ),
            Task(
                task_id=t_writer,
                name="writer",
                agent_role="writer",
                description="Write complete paper from all artifacts",
                inputs={},
                # Writer depends on theory, not experiment.  Experiment is a
                # side-validation that enriches the paper when applicable, but
                # its failure or skip (e.g. for purely structural theorems with
                # no measurable bounds) must never prevent the paper from being
                # written.  The writer reads exp_result from the bus if present.
                depends_on=[t_theory],
                gate_required=False,
            ),
        ]

        pipeline = TaskPipeline(
            pipeline_id=pipeline_id,
            session_id=brief.session_id,
            tasks=tasks,
        )
        return pipeline
