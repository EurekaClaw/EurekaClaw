"""Tests for the shared REWRITE_MARKER_PREFIX constant.

The `..._used_in_*` tests grep the imported module source for quoted
occurrences of the literal "↻ Rewrite requested:" (colon-anchored, so
prose that mentions "↻ Rewrite requested" without the trailing colon
does not trip the regex). Using `inspect.getsource(module)` keeps the
tests cwd-independent — they read the module as imported, not a file
at a hard-coded relative path.
"""

import inspect
import re


def test_rewrite_marker_prefix_exact_value():
    from eurekaclaw.ui.constants import REWRITE_MARKER_PREFIX

    assert REWRITE_MARKER_PREFIX == '↻ Rewrite requested: '


def test_rewrite_marker_prefix_used_in_server():
    """server.py._append_paper_qa_rewrite_marker writes entries whose
    content starts with REWRITE_MARKER_PREFIX — enforced by grep."""
    import eurekaclaw.ui.server as server

    src = inspect.getsource(server)
    open_coded = re.findall(r'["\']↻ Rewrite requested:', src)
    assert open_coded == [], (
        f"server.py still contains open-coded rewrite markers: {open_coded}"
    )
    assert "REWRITE_MARKER_PREFIX" in src


def test_rewrite_marker_prefix_used_in_paper_qa_handler():
    import eurekaclaw.orchestrator.paper_qa_handler as handler

    src = inspect.getsource(handler)
    open_coded = re.findall(r'["\']↻ Rewrite requested:', src)
    assert open_coded == [], (
        f"paper_qa_handler.py still contains open-coded rewrite markers: {open_coded}"
    )
    assert "REWRITE_MARKER_PREFIX" in src
