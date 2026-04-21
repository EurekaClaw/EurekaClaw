"""Unit tests for WriterAgent._clean_proof_text markdown-to-LaTeX conversion.

Regression: asterisks inside math expressions (e.g. convolution `\\mu*\\nu`)
must not be interpreted as markdown italic delimiters, because that corrupts
the LaTeX output and causes pdflatex to fail with "Missing $ inserted".
"""

from eurekaclaw.agents.writer.agent import WriterAgent


def test_preserves_asterisk_inside_inline_math():
    """`\\(\\mu*\\nu\\)` must not become `\\(\\mu\\textit{\\nu\\)`."""
    raw = (
        "The convolution \\(\\mu*\\nu\\) is the law of "
        "\\(X+Y \\pmod 1\\) when independent.\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu" in out
    assert "\\textit{" not in out


def test_preserves_multiple_asterisks_across_math_spans():
    """Multiple math spans containing `*` must all survive intact."""
    raw = (
        "This yields \\(\\mu*\\nu=\\mu\\). "
        "Symmetry gives \\(\\nu*\\mu=\\mu\\), "
        "and taking \\(\\nu=\\mu\\) gives \\(\\mu*\\mu=\\mu\\).\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu=\\mu" in out
    assert "\\nu*\\mu=\\mu" in out
    assert "\\mu*\\mu=\\mu" in out
    assert "\\textit{" not in out


def test_preserves_asterisk_inside_display_math():
    """`\\[...*...\\]` must not be mangled."""
    raw = "We have\n\\[\n\\mu*\\nu=\\mu.\n\\]\nDone.\n"
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu=\\mu" in out
    assert "\\textit{" not in out


def test_still_converts_markdown_italic_in_prose():
    """Regression guard: legitimate *italic* prose must still convert."""
    raw = "Thus *this phrase* is emphasized.\n"
    out = WriterAgent._clean_proof_text(raw)
    assert "\\textit{this phrase}" in out


def test_still_converts_markdown_bold_in_prose():
    """Regression guard: legitimate **bold** prose must still convert."""
    raw = "Thus **this phrase** is emphasized.\n"
    out = WriterAgent._clean_proof_text(raw)
    assert "\\textit{this phrase}" in out


def test_mixed_math_and_italic_prose():
    """Math asterisks preserved; prose italics converted; both in same input."""
    raw = (
        "Informally, *the key idea* is that \\(\\mu*\\nu=\\mu\\).\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\textit{the key idea}" in out
    assert "\\mu*\\nu=\\mu" in out


def test_preserves_asterisk_inside_align_environment():
    """`align`/`align*` blocks must be protected just like `\\[...\\]`."""
    raw = (
        "We compute\n"
        "\\begin{align}\n"
        "\\mu*\\nu &= \\mu \\\\\n"
        "\\nu*\\mu &= \\mu.\n"
        "\\end{align}\n"
        "Done.\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu" in out
    assert "\\nu*\\mu" in out
    assert "\\textit{" not in out


def test_preserves_asterisk_inside_align_star_environment():
    """Starred math environments (no numbering) are common in proofs."""
    raw = (
        "\\begin{align*}\n"
        "\\mu*\\nu=\\mu, \\qquad \\nu*\\mu=\\mu.\n"
        "\\end{align*}\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu=\\mu" in out
    assert "\\nu*\\mu=\\mu" in out
    assert "\\textit{" not in out


def test_preserves_asterisk_inside_equation_environment():
    """`equation`/`equation*` blocks must be protected."""
    raw = (
        "\\begin{equation}\n"
        "\\mu*\\nu = \\mu.\n"
        "\\end{equation}\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu = \\mu" in out
    assert "\\textit{" not in out


def test_escaped_dollar_is_not_treated_as_math_delimiter():
    """`\\$` is a literal dollar sign in text, not a math delimiter.

    If `\\$` were mistaken for the start of a math region, surrounding
    `*italic*` would be masked inside that fake region and never converted.
    """
    raw = "The cost is \\$5 per *item*, while \\$10 covers *two*.\n"
    out = WriterAgent._clean_proof_text(raw)
    # Escaped dollars must be preserved verbatim.
    assert "\\$5" in out
    assert "\\$10" in out
    # Prose italics outside math must still convert.
    assert "\\textit{item}" in out
    assert "\\textit{two}" in out


def test_unescaped_dollar_prices_do_not_engulf_italic_between_them():
    """Bare `$5 ... *italic* ... $10` must not pair into a fake math region.

    If the two prose dollars are treated as math delimiters, `*italic*` sits
    inside the fake region, never gets converted, and the output still
    contains literal markdown.
    """
    raw = "The bounty is $5 for *one* and $10 for *two*.\n"
    out = WriterAgent._clean_proof_text(raw)
    assert "$5" in out
    assert "$10" in out
    assert "\\textit{one}" in out
    assert "\\textit{two}" in out


def test_escaped_double_dollar_is_not_treated_as_display_math():
    """`\\$\\$...\\$\\$` is two literal dollars, not a display-math block."""
    raw = "Prices \\$\\$ and more \\$\\$, with *emphasis* between.\n"
    out = WriterAgent._clean_proof_text(raw)
    assert "\\$\\$" in out
    assert "\\textit{emphasis}" in out


def test_preserves_asterisk_inside_gather_and_multline():
    """Less common but still valid display-math environments."""
    raw = (
        "\\begin{gather}\n"
        "\\mu*\\nu=\\mu \\\\\n"
        "\\nu*\\mu=\\mu\n"
        "\\end{gather}\n"
        "\\begin{multline*}\n"
        "\\mu*\\nu*\\rho=\\mu.\n"
        "\\end{multline*}\n"
    )
    out = WriterAgent._clean_proof_text(raw)
    assert "\\mu*\\nu=\\mu" in out
    assert "\\nu*\\mu=\\mu" in out
    assert "\\mu*\\nu*\\rho=\\mu" in out
    assert "\\textit{" not in out
