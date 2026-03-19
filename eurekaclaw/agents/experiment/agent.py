"""ExperimentAgent — validates theoretical results empirically via code execution."""

from __future__ import annotations

import json
import logging
import uuid

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.artifacts import ExperimentResult, NumericalBound
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)


def _to_float(v, default: float = 0.0) -> float:
    """Safely convert v to float; extract the first number from a string if needed."""
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        import re
        m = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", v)
        if m:
            return float(m.group())
    return default


class ExperimentAgent(BaseAgent):
    """Generates and executes Python experiments to validate theoretical bounds.

    Uses the ResourceAnalyst math↔code mapping to generate validation code
    and the CodeExecutionTool to run it in a sandboxed environment.
    """

    role = AgentRole.EXPERIMENT

    def get_tool_names(self) -> list[str]:
        return ["execute_python", "run_bandit_experiment", "wolfram_alpha"]

    def _role_system_prompt(self, task: Task) -> str:
        return """\
You are the Experiment Agent of EurekaClaw. Your role is to empirically validate \
theoretical results through numerical experiments.

Your process:
1. Read the proven theorems and their bounds from the theory state
2. Write Python code to empirically measure the quantities in the bounds
3. Compare theoretical predictions vs. empirical measurements
4. Report the alignment score (1.0 = theory exactly matches experiment)
5. Design ablations to test robustness of the bounds

Requirements:
- For bandit/MAB theory: prefer run_bandit_experiment (faster, reproducible, no imports needed)
- For other experiments: write self-contained Python code using execute_python
- Use numpy, scipy, matplotlib as needed in Python code
- Always print results clearly to stdout
- Vary at least 3 parameter configurations
- For each configuration, report: theoretical bound, empirical value, ratio
"""

    async def execute(self, task: Task) -> AgentResult:
        brief = self.bus.get_research_brief()
        theory_state = self.bus.get_theory_state()
        resource_analysis = self.bus.get("resource_analysis") or {}

        if not theory_state:
            return self._make_result(task, False, {}, error="No TheoryState found on bus")

        validation_code_hint = resource_analysis.get("validation_code", "")
        math_to_code = resource_analysis.get("math_to_code", {})

        proven_summary = "\n".join(
            f"[{lid}] {rec.proof_text[:300]}"
            for lid, rec in list(theory_state.proven_lemmas.items())[:3]
        )

        user_message = f"""\
Validate the following proven theorems experimentally:

Domain: {brief.domain if brief else "unknown"}
Theorem: {theory_state.formal_statement}
Informal: {theory_state.informal_statement}

Proven lemmas summary:
{proven_summary or "(no proven lemmas yet)"}

Math-to-code hints:
{json.dumps(math_to_code, indent=2)[:500] if math_to_code else "(none)"}

Validation code hint:
{validation_code_hint[:500] if validation_code_hint else "(none)"}

Please:
1. Write Python code that empirically measures the key quantities
2. Execute it using the execute_python tool
3. Compare the theoretical bounds against empirical measurements
4. Report alignment scores for each bound

After executing, summarize the results as JSON with this exact schema
(theoretical and empirical MUST be numbers — use null if unavailable):
{{
  "bounds": [
    {{
      "name": "bound name",
      "theoretical": 1.23,
      "empirical": 1.05,
      "aligned": true
    }}
  ],
  "alignment_score": 0.85,
  "summary": "one paragraph summary",
  "code": "complete_python_code_string"
}}
"""

        try:
            text, tokens = await self.run_agent_loop(task, user_message, max_turns=10)
            result_data = self._parse_experiment_output(text)

            # Build ExperimentResult
            bounds = [
                NumericalBound(
                    name=b.get("name", ""),
                    theoretical=b.get("theoretical"),
                    empirical=b.get("empirical"),
                    aligned=b.get("aligned"),
                )
                for b in result_data.get("bounds", [])
            ]

            exp_result = ExperimentResult(
                session_id=theory_state.session_id,
                experiment_id=str(uuid.uuid4()),
                description=result_data.get("summary", ""),
                code=result_data.get("code", ""),
                outputs=result_data.get("outputs", {}),
                bounds=bounds,
                alignment_score=_to_float(result_data.get("alignment_score", 0.0)),
                succeeded=bool(_to_float(result_data.get("alignment_score", 0)) > 0),
            )
            self.bus.put_experiment_result(exp_result)

            self.memory.log_event(
                self.role.value,
                f"Experiment: alignment_score={exp_result.alignment_score:.2f}, "
                f"{len(bounds)} bounds validated",
            )

            return self._make_result(
                task,
                success=exp_result.succeeded,
                output=result_data,
                text_summary=f"Alignment score: {exp_result.alignment_score:.2f}",
                token_usage=tokens,
            )

        except Exception as e:
            logger.exception("Experiment agent failed")
            return self._make_result(task, False, {}, error=str(e))

    def _parse_experiment_output(self, text: str) -> dict:
        for delim_start, delim_end in [("```json", "```"), ("{", None)]:
            try:
                if delim_start in text:
                    start = text.index(delim_start) + len(delim_start)
                    if delim_end:
                        end = text.index(delim_end, start)
                        return json.loads(text[start:end].strip())
                    else:
                        end = text.rindex("}") + 1
                        return json.loads(text[text.index("{"):end])
            except (json.JSONDecodeError, ValueError):
                continue
        return {"bounds": [], "alignment_score": 0.0, "summary": text[:500], "code": ""}
