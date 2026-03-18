"""Semantic Scholar API tool."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from eurekaclaw.config import settings
from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)

S2_BASE = "https://api.semanticscholar.org/graph/v1"
FIELDS = "title,authors,year,abstract,citationCount,externalIds,url,venue"


class SemanticScholarTool(BaseTool):
    name = "semantic_scholar_search"
    description = (
        "Search Semantic Scholar for academic papers. Returns structured metadata "
        "including citation counts, abstracts, and DOIs. Good for finding highly-cited work."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "limit": {"type": "integer", "default": 10, "description": "Max results (default 10)"},
                "year_range": {
                    "type": "string",
                    "description": "Year range filter e.g. '2020-2024' or '2022-'",
                },
            },
            "required": ["query"],
        }

    async def call(self, query: str, limit: int = 10, year_range: str | None = None) -> str:
        headers = {}
        if settings.s2_api_key:
            headers["x-api-key"] = settings.s2_api_key

        params: dict[str, Any] = {
            "query": query,
            "limit": min(limit, 50),
            "fields": FIELDS,
        }
        if year_range:
            params["year"] = year_range

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                r = await client.get(f"{S2_BASE}/paper/search", params=params, headers=headers)
                r.raise_for_status()
                data = r.json()

            papers = []
            for p in data.get("data", []):
                papers.append(
                    {
                        "s2_id": p.get("paperId", ""),
                        "title": p.get("title", ""),
                        "authors": [a["name"] for a in p.get("authors", [])[:5]],
                        "year": p.get("year"),
                        "abstract": (p.get("abstract") or "")[:400],
                        "citation_count": p.get("citationCount", 0),
                        "venue": p.get("venue", ""),
                        "arxiv_id": (p.get("externalIds") or {}).get("ArXiv", ""),
                        "url": p.get("url", ""),
                    }
                )
            return json.dumps(papers, indent=2)
        except httpx.HTTPStatusError as e:
            return json.dumps({"error": f"S2 API error {e.response.status_code}: {e.response.text[:200]}"})
        except Exception as e:
            logger.exception("Semantic Scholar search failed")
            return json.dumps({"error": str(e)})
