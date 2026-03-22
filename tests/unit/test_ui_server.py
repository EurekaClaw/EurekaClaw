"""Unit tests for the lightweight EurekaClaw UI server utilities."""

from pathlib import Path

from eurekaclaw.ui.server import _infer_capabilities, _serialize_value, _write_env_updates
from eurekaclaw.types.tasks import InputSpec


def test_serialize_value_handles_pydantic_models():
    spec = InputSpec(mode="detailed", conjecture="test", domain="math", query="test")
    data = _serialize_value(spec)
    assert data["mode"] == "detailed"
    assert data["domain"] == "math"


def test_write_env_updates_updates_existing_and_new_keys(tmp_path: Path):
    env_path = tmp_path / ".env"
    env_path.write_text("A=1\nB=2\n")

    _write_env_updates(env_path, {"B": "3", "C": "4"})

    contents = env_path.read_text().splitlines()
    assert "A=1" in contents
    assert "B=3" in contents
    assert "C=4" in contents


def test_infer_capabilities_has_expected_keys():
    capabilities = _infer_capabilities()
    assert "python" in capabilities
    assert "model_access" in capabilities
    assert "lean4" in capabilities
