"""
Quick smoke test for the three UI gates.

Tests:
  1. review_gate.py threading logic (no server needed)
  2. Server gate API endpoints (requires `eurekaclaw ui --port 8099` running)

Run:
  # Unit tests only (no server needed):
  python tests/test_gates.py

  # With server integration tests:
  eurekaclaw ui --port 8099 &
  python tests/test_gates.py --with-server
"""
import sys
import threading
import time

import pytest

sys.path.insert(0, ".")

# ── 1. Unit tests for review_gate threading ───────────────────────────────────

from eurekaclaw.ui.review_gate import (
    register_survey, wait_survey, submit_survey, is_survey_waiting,
    register_direction, wait_direction, submit_direction, is_direction_waiting,
    register_theory, wait_theory, submit_theory, reset_theory, is_theory_waiting,
    unregister_all, TheoryDecision,
)

PASS = "\033[32m✓\033[0m"
FAIL = "\033[31m✗\033[0m"

def check(label, cond):
    print(f"  {PASS if cond else FAIL}  {label}")
    if not cond:
        sys.exit(1)


def test_survey_gate():
    print("\n── Survey gate ──────────────────────────────────────")
    sid = "test-survey-001"
    register_survey(sid)
    check("is_waiting after register", is_survey_waiting(sid))

    result = []
    def waiter():
        d = wait_survey(sid, timeout=5)
        result.append(d)

    t = threading.Thread(target=waiter, daemon=True)
    t.start()
    time.sleep(0.1)

    ok = submit_survey(sid, ["2301.00001", "2301.00002"])
    check("submit returns True", ok)
    t.join(timeout=3)
    check("waiter unblocked", not t.is_alive())
    check("paper_ids received", result and result[0].paper_ids == ["2301.00001", "2301.00002"])

    # Skip (empty paper_ids)
    register_survey(sid)
    result2 = []
    t2 = threading.Thread(target=lambda: result2.append(wait_survey(sid, timeout=5)), daemon=True)
    t2.start()
    time.sleep(0.1)
    submit_survey(sid, [])
    t2.join(timeout=3)
    check("skip (empty list) unblocks", not t2.is_alive())
    check("empty paper_ids on skip", result2 and result2[0].paper_ids == [])

    unregister_all(sid)
    check("cleaned up", not is_survey_waiting(sid))


def test_direction_gate():
    print("\n── Direction gate ───────────────────────────────────")
    sid = "test-dir-001"
    register_direction(sid)
    check("is_waiting after register", is_direction_waiting(sid))

    result = []
    t = threading.Thread(target=lambda: result.append(wait_direction(sid, timeout=5)), daemon=True)
    t.start()
    time.sleep(0.1)

    ok = submit_direction(sid, "UCB1 achieves optimal regret in stochastic MAB")
    check("submit returns True", ok)
    t.join(timeout=3)
    check("waiter unblocked", not t.is_alive())
    check("direction received", result and "UCB1" in result[0].direction)

    unregister_all(sid)
    check("cleaned up", not is_direction_waiting(sid))


def test_theory_gate():
    print("\n── Theory gate ──────────────────────────────────────")
    sid = "test-theory-001"
    register_theory(sid)
    check("is_waiting after register", is_theory_waiting(sid))

    # Round 1: user approves
    result = []
    t = threading.Thread(target=lambda: result.append(wait_theory(sid, timeout=5)), daemon=True)
    t.start()
    time.sleep(0.1)
    ok = submit_theory(sid, TheoryDecision(approved=True))
    check("submit approve returns True", ok)
    t.join(timeout=3)
    check("waiter unblocked on approve", not t.is_alive())
    check("approved=True received", result and result[0].approved is True)

    # Round 2: user rejects, then reset, then approves
    reset_theory(sid)
    check("is_waiting after reset", is_theory_waiting(sid))

    result2 = []
    t2 = threading.Thread(target=lambda: result2.append(wait_theory(sid, timeout=5)), daemon=True)
    t2.start()
    time.sleep(0.1)
    submit_theory(sid, TheoryDecision(approved=False, lemma_id="lemma_3", reason="gap in induction"))
    t2.join(timeout=3)
    check("waiter unblocked on reject", not t2.is_alive())
    check("approved=False received", result2 and result2[0].approved is False)
    check("lemma_id received", result2 and result2[0].lemma_id == "lemma_3")
    check("reason received", result2 and "induction" in result2[0].reason)

    unregister_all(sid)
    check("cleaned up", not is_theory_waiting(sid))


def test_timeout():
    print("\n── Timeout behaviour ────────────────────────────────")
    sid = "test-timeout-001"
    register_survey(sid)
    d = wait_survey(sid, timeout=0.2)
    check("timeout returns empty SurveyDecision", d.paper_ids == [])
    unregister_all(sid)


# ── 2. Server API integration tests ──────────────────────────────────────────

def _server_reachable(port: int = 8099) -> bool:
    """Check if the UI server is running on the given port."""
    import urllib.request, urllib.error
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/api/runs", timeout=2)
        return True
    except (urllib.error.URLError, OSError):
        return False


@pytest.mark.skipif(not _server_reachable(), reason="UI server not running on port 8099")
def test_server(port=8099):
    import json, urllib.request, urllib.error

    base = f"http://127.0.0.1:{port}"
    print(f"\n── Server API (port {port}) ──────────────────────────")

    def post(path, payload):
        data = json.dumps(payload).encode()
        req = urllib.request.Request(f"{base}{path}", data=data,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return json.loads(r.read()), r.status
        except urllib.error.HTTPError as e:
            return json.loads(e.read()), e.code

    def get(path):
        with urllib.request.urlopen(f"{base}{path}", timeout=5) as r:
            return json.loads(r.read())

    # Create a run
    body, status = post("/api/runs", {
        "mode": "detailed",
        "domain": "test",
        "query": "test gate endpoints",
        "conjecture": "P != NP",
    })
    check(f"POST /api/runs → 201", status == 201)
    run_id = body.get("run_id", "")
    session_id = body.get("session_id", "")
    check("run_id present", bool(run_id))
    print(f"    run_id: {run_id}")

    # Wait briefly for session to initialise (session_id populated after EurekaSession())
    for _ in range(20):
        time.sleep(0.5)
        runs = get("/api/runs")
        run = next((r for r in runs.get("runs", []) if r["run_id"] == run_id), None)
        if run and run.get("session_id"):
            session_id = run["session_id"]
            break
    check("session_id populated", bool(session_id))
    print(f"    session_id: {session_id}")

    # Register gates manually (simulates what _execute_run does)
    from eurekaclaw.ui import review_gate as rg
    rg.register_survey(session_id)
    rg.register_direction(session_id)
    rg.register_theory(session_id)

    # Submit survey gate via API
    body2, status2 = post(f"/api/runs/{run_id}/gate/survey", {"paper_ids": ["2301.99999"]})
    check("POST /gate/survey → 200", status2 == 200)
    check("survey ok", body2.get("ok"))

    # Submit direction gate via API
    body3, status3 = post(f"/api/runs/{run_id}/gate/direction", {"direction": "test direction"})
    check("POST /gate/direction → 200", status3 == 200)
    check("direction ok", body3.get("ok"))

    # Submit theory gate (approve) via API
    body4, status4 = post(f"/api/runs/{run_id}/gate/theory", {"approved": True})
    check("POST /gate/theory → 200", status4 == 200)
    check("theory ok", body4.get("ok"))

    # Submit theory gate (reject) via API
    rg.reset_theory(session_id)
    body5, status5 = post(f"/api/runs/{run_id}/gate/theory", {
        "approved": False, "lemma_id": "l1", "reason": "bad proof"
    })
    check("POST /gate/theory (reject) → 200", status5 == 200)
    check("theory reject ok", body5.get("ok"))

    # 404 for unknown gate type
    body6, status6 = post(f"/api/runs/{run_id}/gate/unknown", {})
    check("POST /gate/unknown → 400", status6 == 400)

    rg.unregister_all(session_id)


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    test_survey_gate()
    test_direction_gate()
    test_theory_gate()
    test_timeout()

    if "--with-server" in sys.argv:
        port = 8099
        for arg in sys.argv:
            if arg.startswith("--port="):
                port = int(arg.split("=")[1])
        test_server(port)

    print("\n\033[32mAll tests passed.\033[0m\n")
