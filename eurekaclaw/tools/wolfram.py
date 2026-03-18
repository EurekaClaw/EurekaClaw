"""Wolfram Alpha tool for symbolic math queries."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from eurekaclaw.config import settings
from eurekaclaw.tools.base import BaseTool

logger = logging.getLogger(__name__)


class WolframAlphaTool(BaseTool):
    name = "wolfram_alpha"
    description = (
        "Query Wolfram Alpha for symbolic math computations: integrals, limits, "
        "series expansions, equation solving, combinatorics, etc."
    )

    def input_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Mathematical query in natural language or standard notation.",
                },
            },
            "required": ["query"],
        }

    async def call(self, query: str) -> str:
        if not settings.wolfram_app_id:
            return json.dumps({"error": "Wolfram Alpha APP_ID not configured. Set WOLFRAM_APP_ID."})
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                r = await client.get(
                    "http://api.wolframalpha.com/v2/query",
                    params={
                        "input": query,
                        "appid": settings.wolfram_app_id,
                        "output": "json",
                        "format": "plaintext",
                    },
                )
                r.raise_for_status()
                data = r.json()

            pods = data.get("queryresult", {}).get("pods", [])
            if not pods:
                return json.dumps({"result": "No results from Wolfram Alpha."})

            results = []
            for pod in pods[:5]:
                subpods = pod.get("subpods", [])
                text = "; ".join(s.get("plaintext", "") for s in subpods if s.get("plaintext"))
                if text:
                    results.append({"title": pod.get("title", ""), "result": text})

            return json.dumps(results, indent=2)
        except Exception as e:
            logger.exception("Wolfram Alpha query failed")
            return json.dumps({"error": str(e)})
