"""ExperimentAgent — validates theoretical results empirically via code execution.

The experiment stage is *optional*: it only runs when the proven theorem contains
measurable numerical quantities (bounds, rates, probabilities, approximation ratios).
For purely structural or algebraic theorems (existence proofs, graph-theoretic
identities, algebraic equalities without numeric bounds) the agent skips itself
cleanly so the writer is not blocked.

Detection heuristics (applied to the formal statement + resource analysis):
  Quantitative signals  → run experiments
  Structural signals    → skip

The writer's dependency has been changed from experiment → theory so this skip
never prevents the paper from being generated.
"""

from __future__ import annotations

import json
import logging
import re
import uuid

from eurekaclaw.agents.base import BaseAgent
from eurekaclaw.types.agents import AgentResult, AgentRole
from eurekaclaw.types.artifacts import ExperimentResult, NumericalBound
from eurekaclaw.types.tasks import Task

logger = logging.getLogger(__name__)

# ── Quantitative markers ────────────────────────────────────────────────────
# Present in bounds / rates / sample-complexity results — experiment is useful.
_QUANTITATIVE_PATTERNS: list[re.Pattern] = [
    re.compile(r"\\[Oo]mega\s*\("),            # \Omega(
    re.compile(r"\\[Tt]heta\s*\("),            # \Theta(
    re.compile(r"\\mathcal\{O\}\s*\("),        # \mathcal{O}(
    re.compile(r"\bO\s*\("),                   # O(
    re.compile(r"\\leq|\\geq|\\le\b|\\ge\b"),  # inequality symbols
    re.compile(r"\\epsilon|\\delta|\\varepsilon"),  # error/confidence params
    re.compile(r"\\frac\{"),                   # fractions (numeric ratios)
    re.compile(r"\bsample complexity\b", re.I),
    re.compile(r"\bregret\b", re.I),
    re.compile(r"\bconvergence rate\b", re.I),
    re.compile(r"\bwith probability\b", re.I),
    re.compile(r"\bapproximation ratio\b", re.I),
    re.compile(r"\bgenerali[sz]ation (error|bound)\b", re.I),
    re.compile(r"\d+\.\d+"),                   # literal decimal numbers
]

# ── Structural markers ──────────────────────────────────────────────────────
# Present in existence / algebraic / combinatorial proofs — skip experiment.
_STRUCTURAL_PATTERNS: list[re.Pattern] = [
    re.compile(r"\\exists\s"),                 # existence quantifier
    re.compile(r"\bthere exists\b", re.I),
    re.compile(r"\bis (a |an )?(bijection|isomorphism|homomorphism)\b", re.I),
    re.compile(r"\bfor all (groups?|rings?|fields?|modules?)\b", re.I),
    re.compile(r"\bplanar\b", re.I),
    re.compile(r"\bchromatic\b", re.I),
    re.compile(r"\bNP-(hard|complete)\b", re.I),
    re.compile(r"\bundecidable\b", re.I),
]


def _has_measurable_bounds(formal_statement: str, resource_analysis: dict) -> tuple[bool, str]:
    """Decide whether the theorem warrants numerical experiments.

    Returns (should_run, reason_string).

    Strategy (scored):
    +2 for each quantitative pattern match in the formal statement
    -3 for each structural pattern match
    +3 if resource_analysis.math_to_code is non-empty  (ResourceAnalyst found code analogs)
    +2 if resource_analysis.validation_code is non-trivial (> 50 chars)

    Threshold: score > 0 → run experiments.
    """
    score = 0
    matched_signals: list[str] = []
    blocked_signals: list[str] = []

    stmt = formal_statement or ""

    for pat in _QUANTITATIVE_PATTERNS:
        if pat.search(stmt):
            score += 2
            matched_signals.append(pat.pattern)

    for pat in _STRUCTURAL_PATTERNS:
        if pat.search(stmt):
            score -= 3
            blocked_signals.append(pat.pattern)

    if resource_analysis.get("math_to_code"):
        score += 3
        matched_signals.append("math_to_code non-empty")

    validation_code = resource_analysis.get("validation_code", "")
    if isinstance(validation_code, str) and len(validation_code) > 50:
        score += 2
        matched_signals.append("validation_code present")

    if score > 0:
        return True, f"Quantitative signals detected (score={score}): {matched_signals[:3]}"
    else:
        reason = "No measurable numerical bounds detected"
        if blocked_signals:
            reason += f" (structural signals: {blocked_signals[:2]})"
        if matched_signals:
            reason += f"; quantitative signals too weak (score={score})"
        return False, reason


def _to_float(v, default: float = 0.0) -> float:
    """Safely convert v to float; extract the first number from a string if needed."""
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        m = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", v)
        if m:
            return float(m.group())
    return default


class ExperimentAgent(BaseAgent):
    """Generates and executes Python experiments to validate theoretical bounds.

    Skips automatically when the proven theorem has no measurable numerical
    quantities (purely structural / algebraic / existence theorems).
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

        # ── Early skip: controlled by EXPERIMENT_MODE env var ────────────────
        from eurekaclaw.config import settings
        mode = settings.experiment_mode
        if mode == "false":
            should_run, reason = False, "Experiment disabled via EXPERIMENT_MODE=false"
        elif mode == "true":
            should_run, reason = True, "Experiment forced via EXPERIMENT_MODE=true"
        else:  # "auto"
            should_run, reason = _has_measurable_bounds(
                theory_state.formal_statement, resource_analysis
            )
        if not should_run:
            logger.info("Experiment stage skipped: %s", reason)
            # Put an empty placeholder on the bus so the writer doesn't look
            # for a result that was never produced, and include a clear note.
            empty_result = ExperimentResult(
                session_id=theory_state.session_id,
                experiment_id=str(uuid.uuid4()),
                description=f"Skipped: {reason}",
                code="",
                outputs={},
                bounds=[],
                alignment_score=0.0,
                succeeded=False,
            )
            self.bus.put_experiment_result(empty_result)
            return self._make_result(
                task,
                success=True,   # not a failure — intentional skip
                output={"skipped": True, "reason": reason},
                text_summary=f"Experiment skipped: {reason}",
            )

        # ── Run experiments ───────────────────────────────────────────────────
        validation_code_hint = resource_analysis.get("validation_code", "")
        math_to_code = resource_analysis.get("math_to_code", {})

        # Separate verified vs low-confidence lemmas
        verified_lemmas = {
            lid: rec for lid, rec in theory_state.proven_lemmas.items() if rec.verified
        }
        low_conf_lemmas = {
            lid: rec for lid, rec in theory_state.proven_lemmas.items() if not rec.verified
        }

        proven_summary = "\n".join(
            f"[{lid}] {'[VERIFIED]' if rec.verified else '[LOW CONFIDENCE]'} {rec.proof_text[:300]}"
            for lid, rec in list(theory_state.proven_lemmas.items())[:5]
        )

        # Build targeted checks for low-confidence lemmas
        low_conf_section = ""
        if low_conf_lemmas:
            items = []
            for lid, rec in low_conf_lemmas.items():
                node = theory_state.lemma_dag.get(lid)
                stmt = node.statement[:200] if node else lid
                items.append(f"  - [{lid}]: {stmt}")
            low_conf_section = (
                f"\nLOW-CONFIDENCE LEMMAS (not formally verified — MUST test numerically):\n"
                + "\n".join(items)
                + "\n\nFor each low-confidence lemma, write a dedicated numerical test that:\n"
                "  1. Samples random instances where the lemma's hypothesis holds\n"
                "  2. Checks whether the lemma's conclusion holds in each instance\n"
                "  3. Reports a violation rate (0.0 = never violated = good)\n"
                "  4. Flags the lemma as 'numerically_suspect' if violation_rate > 0.01\n"
            )

        user_message = f"""\
Validate the following proven theorems experimentally:

Domain: {brief.domain if brief else "unknown"}
Theorem: {theory_state.formal_statement}
Informal: {theory_state.informal_statement}

Proven lemmas summary:
{proven_summary or "(no proven lemmas yet)"}
{low_conf_section}
Math-to-code hints:
{json.dumps(math_to_code, indent=2)[:500] if math_to_code else "(none)"}

Validation code hint:
{validation_code_hint[:500] if validation_code_hint else "(none)"}

Please:
1. Write Python code that empirically measures the key quantities
2. Execute it using the execute_python tool
3. For each LOW-CONFIDENCE lemma, run the dedicated numerical test described above
4. Compare theoretical bounds against empirical measurements
5. Report alignment scores for each bound

After executing, summarize the results as JSON:
{{
  "bounds": [
    {{
      "name": "bound name",
      "theoretical": 1.23,
      "empirical": 1.05,
      "aligned": true
    }}
  ],
  "lemma_checks": [
    {{
      "lemma_id": "hoeffding_concentration",
      "violation_rate": 0.0,
      "n_trials": 1000,
      "numerically_suspect": false
    }}
  ],
  "alignment_score": 0.85,
  "summary": "one paragraph summary",
  "code": "complete_python_code_string"
}}
"""

        try:
            text, tokens = await self.run_agent_loop(task, user_message, max_turns=5)
            result_data = self._parse_experiment_output(text)

            bounds = [
                NumericalBound(
                    name=b.get("name", ""),
                    theoretical=b.get("theoretical"),
                    empirical=b.get("empirical"),
                    aligned=b.get("aligned"),
                )
                for b in result_data.get("bounds", [])
            ]

            alignment_score = _to_float(result_data.get("alignment_score", 0.0))
            succeeded = alignment_score > 0

            # Flag any lemma that failed numerical testing back onto theory_state
            lemma_checks = result_data.get("lemma_checks", [])
            suspect_lemmas = [
                c["lemma_id"] for c in lemma_checks
                if c.get("numerically_suspect") and c.get("lemma_id")
            ]
            if suspect_lemmas:
                logger.warning(
                    "Numerically suspect lemmas (violation_rate > 1%%): %s", suspect_lemmas
                )
                # Store on bus so gate + writer can surface the warning
                self.bus.put("numerically_suspect_lemmas", suspect_lemmas)

            exp_result = ExperimentResult(
                session_id=theory_state.session_id,
                experiment_id=str(uuid.uuid4()),
                description=result_data.get("summary", ""),
                code=result_data.get("code", ""),
                outputs={**result_data.get("outputs", {}), "lemma_checks": lemma_checks},
                bounds=bounds,
                alignment_score=alignment_score,
                succeeded=succeeded,
            )
            self.bus.put_experiment_result(exp_result)

            self.memory.log_event(
                self.role.value,
                f"Experiment: alignment_score={exp_result.alignment_score:.2f}, "
                f"{len(bounds)} bounds validated",
            )

            # Produce a meaningful error string on soft-failure so the task log
            # shows a useful message instead of the silent blank "(no message)".
            if not succeeded:
                error_msg = (
                    result_data.get("summary")
                    or f"Alignment score is 0 — agent produced no valid numerical bounds. "
                       f"Parsed bounds: {[b.get('name') for b in result_data.get('bounds', [])]}"
                )
            else:
                error_msg = ""

            return self._make_result(
                task,
                success=succeeded,
                output=result_data,
                text_summary=f"Alignment score: {exp_result.alignment_score:.2f}",
                error=error_msg,
                token_usage=tokens,
            )

        except Exception as e:
            logger.exception("Experiment agent failed")
            error_msg = str(e) or f"Experiment agent raised {type(e).__name__} with no message"
            return self._make_result(task, False, {}, error=error_msg)

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
