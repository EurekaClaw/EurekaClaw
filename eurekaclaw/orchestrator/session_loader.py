"""SessionLoader — reconstruct a runnable session from persisted artifacts."""

from __future__ import annotations

import logging
from pathlib import Path

from eurekaclaw.config import settings
from eurekaclaw.knowledge_bus.bus import KnowledgeBus
from eurekaclaw.types.artifacts import ResearchBrief
from eurekaclaw.types.tasks import TaskPipeline

logger = logging.getLogger(__name__)


class SessionLoader:
    """Reconstruct bus, brief, and pipeline from a persisted session directory."""

    @staticmethod
    def load(session_id: str) -> tuple[KnowledgeBus, ResearchBrief, TaskPipeline]:
        """Load a session from disk.

        Args:
            session_id: Full or partial (prefix, min 8 chars) session ID.

        Returns:
            (bus, brief, pipeline) tuple ready for PaperQAHandler.

        Raises:
            FileNotFoundError: Session directory not found.
            ValueError: No paper LaTeX found in session artifacts.
        """
        session_dir = SessionLoader._resolve_session_dir(session_id)
        resolved_id = session_dir.name

        bus = KnowledgeBus.load(resolved_id, session_dir)

        brief = bus.get_research_brief()
        if brief is None:
            raise FileNotFoundError(
                f"No research_brief.json in session {resolved_id}"
            )

        pipeline = bus.get_pipeline()
        if pipeline is None:
            raise FileNotFoundError(
                f"No pipeline.json in session {resolved_id}"
            )

        # Extract LaTeX from writer task outputs
        latex = ""
        writer_task = next(
            (t for t in pipeline.tasks if t.name == "writer"), None
        )
        if writer_task and writer_task.outputs:
            latex = writer_task.outputs.get("latex_paper", "")

        # Fallback: check for paper.tex on disk
        if not latex:
            tex_path = session_dir / "paper.tex"
            if tex_path.is_file():
                latex = tex_path.read_text(encoding="utf-8")

        if not latex:
            raise ValueError(
                f"No paper LaTeX found in session {resolved_id}. "
                "The writer may not have completed successfully."
            )

        bus.put("paper_qa_latex", latex)

        return bus, brief, pipeline

    @staticmethod
    def _resolve_session_dir(session_id: str) -> Path:
        """Resolve full or partial session ID to a directory path."""
        runs_dir = settings.runs_dir

        # Exact match
        exact = runs_dir / session_id
        if exact.is_dir():
            return exact

        # Prefix match (min 8 chars)
        if len(session_id) >= 8:
            matches = [
                d for d in runs_dir.iterdir()
                if d.is_dir() and d.name.startswith(session_id)
            ]
            if len(matches) == 1:
                return matches[0]
            if len(matches) > 1:
                names = ", ".join(m.name[:16] + "..." for m in matches[:5])
                raise FileNotFoundError(
                    f"Ambiguous session ID '{session_id}' matches {len(matches)} "
                    f"sessions: {names}. Use a longer prefix."
                )

        raise FileNotFoundError(
            f"Session '{session_id}' not found in {runs_dir}"
        )

    @staticmethod
    def list_sessions() -> list[dict]:
        """List all persisted sessions, sorted by modification time (newest first).

        Returns list of dicts with keys: session_id, domain, query, status, has_paper, modified.
        """
        import json

        runs_dir = settings.runs_dir
        if not runs_dir.is_dir():
            return []

        sessions = []
        for session_dir in runs_dir.iterdir():
            if not session_dir.is_dir():
                continue
            brief_path = session_dir / "research_brief.json"
            if not brief_path.exists():
                continue

            try:
                brief = json.loads(brief_path.read_text(encoding="utf-8"))
            except Exception:
                continue

            # Determine status from pipeline
            status = "unknown"
            pipeline_path = session_dir / "pipeline.json"
            if pipeline_path.exists():
                try:
                    pipeline = json.loads(
                        pipeline_path.read_text(encoding="utf-8")
                    )
                    tasks = pipeline.get("tasks", [])
                    if tasks:
                        if all(
                            t.get("status") in ("completed", "skipped")
                            for t in tasks
                        ):
                            status = "completed"
                        elif any(t.get("status") == "failed" for t in tasks):
                            status = "failed"
                        else:
                            status = tasks[-1].get("status", "unknown")
                except Exception:
                    pass

            # Check if paper exists
            has_paper = False
            if pipeline_path.exists():
                try:
                    pipeline = json.loads(
                        pipeline_path.read_text(encoding="utf-8")
                    )
                    writer = next(
                        (t for t in pipeline.get("tasks", []) if t.get("name") == "writer"),
                        None,
                    )
                    if writer and writer.get("outputs", {}).get("latex_paper"):
                        has_paper = True
                except Exception:
                    pass
            if not has_paper:
                has_paper = (session_dir / "paper.tex").is_file()

            sessions.append({
                "session_id": session_dir.name,
                "domain": brief.get("domain", ""),
                "query": brief.get("query", ""),
                "status": status,
                "has_paper": has_paper,
                "modified": session_dir.stat().st_mtime,
            })

        sessions.sort(key=lambda s: s["modified"], reverse=True)
        return sessions
