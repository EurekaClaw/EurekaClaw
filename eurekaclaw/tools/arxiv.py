"""arXiv search tool using the arxiv Python package."""

from __future__ import annotations

import json
import logging
from typing import Any

from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)


class ArxivSearchTool(BaseTool):
    name = "arxiv_search"
    description = (
        "Search arXiv for academic papers. Returns titles, authors, abstracts, "
        "arxiv IDs, and PDF links. Best for recent preprints in CS, math, and physics."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query string. Can include title:, author:, abs: prefixes.",
                },
                "max_results": {
                    "type": "integer",
                    "description": "Maximum number of results to return (default 8, max 20).",
                    "default": 8,
                },
                "sort_by": {
                    "type": "string",
                    "enum": ["relevance", "lastUpdatedDate", "submittedDate"],
                    "default": "relevance",
                },
            },
            "required": ["query"],
        }

    async def call(self, query: str, max_results: int = 8, sort_by: str = "relevance") -> str:
        try:
            import arxiv  # type: ignore
            from eurekaclaw.config import settings

            sort_map = {
                "relevance": arxiv.SortCriterion.Relevance,
                "lastUpdatedDate": arxiv.SortCriterion.LastUpdatedDate,
                "submittedDate": arxiv.SortCriterion.SubmittedDate,
            }
            client = arxiv.Client()
            search = arxiv.Search(
                query=query,
                max_results=min(max_results, settings.arxiv_max_results),
                sort_by=sort_map.get(sort_by, arxiv.SortCriterion.Relevance),
            )
            results = []
            for r in client.results(search):
                results.append(
                    {
                        "arxiv_id": r.entry_id.split("/abs/")[-1],
                        "title": r.title,
                        "authors": [a.name for a in r.authors[:5]],
                        "abstract": r.summary[:400] + ("..." if len(r.summary) > 400 else ""),
                        "published": r.published.isoformat() if r.published else "",
                        "pdf_url": r.pdf_url or "",
                        "categories": r.categories[:3],
                    }
                )
            return json.dumps(results, indent=2)
        except ImportError:
            return json.dumps({"error": "arxiv package not installed. Run: pip install arxiv"})
        except Exception as e:
            logger.exception("arXiv search failed")
            return json.dumps({"error": str(e)})
