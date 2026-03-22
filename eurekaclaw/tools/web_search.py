"""Web search tool — supports Brave Search API or SerpAPI, degrades gracefully."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from eurekaclaw.config import settings
from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)


class WebSearchTool(BaseTool):
    name = "web_search"
    description = (
        "Search the web for information. Useful for finding recent news, blog posts, "
        "documentation, or supplementary material not on arXiv."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "count": {"type": "integer", "default": 5, "description": "Number of results"},
            },
            "required": ["query"],
        }

    async def call(self, query: str, count: int = 5) -> str:
        if settings.brave_search_api_key:
            return await self._brave_search(query, count)
        if settings.serpapi_key:
            return await self._serpapi_search(query, count)
        return json.dumps({"error": "No web search API key configured. Set BRAVE_SEARCH_API_KEY or SERPAPI_KEY."})

    async def _brave_search(self, query: str, count: int) -> str:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                r = await client.get(
                    "https://api.search.brave.com/res/v1/web/search",
                    params={"q": query, "count": min(count, 20)},
                    headers={"Accept": "application/json", "X-Subscription-Token": settings.brave_search_api_key},
                )
                r.raise_for_status()
                data = r.json()
            results = [
                {"title": w.get("title", ""), "url": w.get("url", ""), "description": w.get("description", "")[:300]}
                for w in data.get("web", {}).get("results", [])[:count]
            ]
            return json.dumps(results, indent=2)
        except Exception as e:
            logger.exception("Brave search failed")
            return json.dumps({"error": str(e)})

    async def _serpapi_search(self, query: str, count: int) -> str:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                r = await client.get(
                    "https://serpapi.com/search",
                    params={"q": query, "num": min(count, 10), "api_key": settings.serpapi_key, "engine": "google"},
                )
                r.raise_for_status()
                data = r.json()
            results = [
                {"title": w.get("title", ""), "url": w.get("link", ""), "description": w.get("snippet", "")[:300]}
                for w in data.get("organic_results", [])[:count]
            ]
            return json.dumps(results, indent=2)
        except Exception as e:
            logger.exception("SerpAPI search failed")
            return json.dumps({"error": str(e)})
