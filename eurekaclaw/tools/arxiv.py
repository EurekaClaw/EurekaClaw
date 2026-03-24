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

    exact_match_mode: bool = False

    def input_schema(self) -> dict[str, Any]:
        schema = {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "",
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
        
        if self.exact_match_mode:
            schema["properties"]["query"]["description"] = (
                "The search query. You MUST use the 'AND' operator (e.g., 'title:attention AND title:all') "
                "to perform an exact match. Do NOT use standard loose search."
            )
        else:
            schema["properties"]["query"]["description"] = (
                "Search query string. Use space-separated keywords for broad, "
                "relevance-ranked results (e.g. \"sparse attention\" Rademacher "
                "complexity kernel transformer). Do NOT use abs:, title:, or AND "
                "operators — they restrict to exact matches and return far fewer papers."
            )
            
        return schema

    async def call(self, query: str, max_results: int = 8, sort_by: str = "relevance") -> str:
        try:
            import arxiv  # type: ignore
            from eurekaclaw.config import settings

            sort_map = {
                "relevance": arxiv.SortCriterion.Relevance,
                "lastUpdatedDate": arxiv.SortCriterion.LastUpdatedDate,
                "submittedDate": arxiv.SortCriterion.SubmittedDate,
            }
            capped = min(max_results, settings.arxiv_max_results)
            client = arxiv.Client(
                page_size=capped,
                delay_seconds=3.0,
                num_retries=3,
            )
            search = arxiv.Search(
                query=query,
                max_results=capped,
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
