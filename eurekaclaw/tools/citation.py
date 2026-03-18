"""Citation manager tool — bibliography CRUD operations."""

from __future__ import annotations

import json
import logging
from typing import Any

from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)


class CitationManagerTool(BaseTool):
    name = "citation_manager"
    description = (
        "Manage bibliography entries. Can generate BibTeX from paper metadata, "
        "format citations, and retrieve existing bibliography entries."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["generate_bibtex", "format_cite", "list_entries"],
                    "description": "Action to perform.",
                },
                "paper_data": {
                    "type": "object",
                    "description": "Paper metadata for generate_bibtex action.",
                    "properties": {
                        "title": {"type": "string"},
                        "authors": {"type": "array", "items": {"type": "string"}},
                        "year": {"type": "integer"},
                        "venue": {"type": "string"},
                        "arxiv_id": {"type": "string"},
                    },
                },
                "cite_key": {
                    "type": "string",
                    "description": "BibTeX citation key for format_cite action.",
                },
            },
            "required": ["action"],
        }

    async def call(
        self,
        action: str,
        paper_data: dict[str, Any] | None = None,
        cite_key: str | None = None,
    ) -> str:
        if action == "generate_bibtex" and paper_data:
            return self._generate_bibtex(paper_data)
        if action == "format_cite" and cite_key:
            return json.dumps({"cite": f"\\cite{{{cite_key}}}"})
        return json.dumps({"error": f"Unsupported action: {action}"})

    def _generate_bibtex(self, paper_data: dict[str, Any]) -> str:
        title = paper_data.get("title", "Unknown Title")
        authors = paper_data.get("authors", [])
        year = paper_data.get("year", "")
        venue = paper_data.get("venue", "")
        arxiv_id = paper_data.get("arxiv_id", "")

        # Generate cite key: first-author-year
        first_author = (authors[0].split()[-1] if authors else "unknown").lower()
        key = f"{first_author}{year}"

        if arxiv_id:
            entry_type = "@article"
            venue_field = f"  journal = {{arXiv preprint arXiv:{arxiv_id}}},\n"
        else:
            entry_type = "@inproceedings"
            venue_field = f"  booktitle = {{{venue}}},\n" if venue else ""

        bibtex = (
            f"{entry_type}{{{key},\n"
            f"  title = {{{{{title}}}}},\n"
            f"  author = {{{' and '.join(authors)}}},\n"
            f"  year = {{{year}}},\n"
            f"{venue_field}"
            f"}}"
        )
        return json.dumps({"cite_key": key, "bibtex": bibtex})
