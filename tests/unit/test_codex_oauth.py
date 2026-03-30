"""Unit tests for the Codex OAuth integration.

Tests cover:
- auth/providers.py  — provider registry
- auth/token_store.py — persistent token storage
- codex_manager.py   — Codex CLI credential reading, token loading, env setup
- llm/factory.py     — codex backend alias resolves correctly
"""

import json
import os
import time
from pathlib import Path
from unittest.mock import patch

import pytest


# ============================================================================
# 1. Provider registry
# ============================================================================


def test_get_provider_openai_codex():
    from eurekaclaw.auth.providers import get_provider

    p = get_provider("openai-codex")
    assert p.name == "openai-codex"
    assert "openai.com" in p.device_code_url
    assert "openai.com" in p.token_url
    assert p.client_id == "app_eurekaclaw"
    assert "openai.api" in p.scopes


def test_get_provider_unknown_raises():
    from eurekaclaw.auth.providers import get_provider

    with pytest.raises(ValueError, match="Unknown provider"):
        get_provider("nonexistent-provider")


def test_list_providers_includes_codex():
    from eurekaclaw.auth.providers import list_providers

    providers = list_providers()
    assert "openai-codex" in providers

# ============================================================================
# 2. Token store (uses tmp_path to avoid touching real credentials)
# ============================================================================


def test_save_and_load_tokens(tmp_path):
    """Tokens saved to disk can be loaded back."""
    from eurekaclaw.auth import token_store

    with patch.object(token_store, "_creds_dir", return_value=tmp_path):
        token_store.save_tokens("openai-codex", {
            "access_token": "sk-test-123",
            "refresh_token": "rt-test-456",
            "expires_in": 3600,
        })

        loaded = token_store.load_tokens("openai-codex")
        assert loaded is not None
        assert loaded["access_token"] == "sk-test-123"
        assert loaded["refresh_token"] == "rt-test-456"
        assert "saved_at" in loaded


def test_load_tokens_missing_returns_none(tmp_path):
    from eurekaclaw.auth import token_store

    with patch.object(token_store, "_creds_dir", return_value=tmp_path):
        assert token_store.load_tokens("nonexistent") is None


def test_delete_tokens(tmp_path):
    from eurekaclaw.auth import token_store

    with patch.object(token_store, "_creds_dir", return_value=tmp_path):
        token_store.save_tokens("openai-codex", {"access_token": "x"})
        assert token_store.load_tokens("openai-codex") is not None

        token_store.delete_tokens("openai-codex")
        assert token_store.load_tokens("openai-codex") is None


def test_is_token_expired_not_expired():
    from eurekaclaw.auth.token_store import is_token_expired

    tokens = {
        "access_token": "sk-test",
        "expires_in": 3600,
        "saved_at": int(time.time()),
    }
    assert is_token_expired(tokens) is False


def test_is_token_expired_already_expired():
    from eurekaclaw.auth.token_store import is_token_expired

    tokens = {
        "access_token": "sk-test",
        "expires_in": 3600,
        "saved_at": int(time.time()) - 7200,  # saved 2 hours ago
    }
    assert is_token_expired(tokens) is True


def test_is_token_expired_no_expiry_returns_false():
    from eurekaclaw.auth.token_store import is_token_expired

    tokens = {"access_token": "sk-test"}
    assert is_token_expired(tokens) is False


def test_saved_file_permissions(tmp_path):
    """Credential files should be readable only by the owner (0o600)."""
    from eurekaclaw.auth import token_store

    with patch.object(token_store, "_creds_dir", return_value=tmp_path):
        token_store.save_tokens("openai-codex", {"access_token": "secret"})
        cred_file = tmp_path / "openai-codex.json"

        # On Windows and some non-POSIX filesystems, POSIX mode bits are not
        # reliably enforced or reported, so this assertion is only valid on
        # POSIX-like platforms.
        if os.name == "nt":
            pytest.skip("POSIX file permission bits are not reliable on Windows")
        mode = cred_file.stat().st_mode & 0o777
        assert mode == 0o600


# ============================================================================
# 3. Codex manager — reading Codex CLI credentials
# ============================================================================


class TestCodexManager:
    def _write_codex_auth(self, path: Path, access_token: str = "sk-codex-test"):
        """Helper: write a fake ~/.codex/auth.json."""
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({
            "auth_mode": "chatgpt",
            "tokens": {
                "access_token": access_token,
                "refresh_token": "rt-codex-test",
                "id_token": "eyJ-fake",
            },
            "last_refresh": "2026-03-24T00:00:00Z",
        }))

    def test_read_codex_cli_tokens_success(self, tmp_path):
        from eurekaclaw.codex_manager import _read_codex_cli_tokens

        auth_path = tmp_path / ".codex" / "auth.json"
        self._write_codex_auth(auth_path)

        with patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", auth_path):
            tokens = _read_codex_cli_tokens()

        assert tokens is not None
        assert tokens["access_token"] == "sk-codex-test"
        assert tokens["refresh_token"] == "rt-codex-test"
        assert tokens["auth_mode"] == "chatgpt"

    def test_read_codex_cli_tokens_missing_file(self, tmp_path):
        from eurekaclaw.codex_manager import _read_codex_cli_tokens

        missing_path = tmp_path / ".codex" / "auth.json"
        with patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", missing_path):
            assert _read_codex_cli_tokens() is None

    def test_read_codex_cli_tokens_malformed_json(self, tmp_path):
        from eurekaclaw.codex_manager import _read_codex_cli_tokens

        auth_path = tmp_path / ".codex" / "auth.json"
        auth_path.parent.mkdir(parents=True, exist_ok=True)
        auth_path.write_text("not valid json {{{")

        with patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", auth_path):
            assert _read_codex_cli_tokens() is None

    def test_read_codex_cli_tokens_empty_access_token(self, tmp_path):
        from eurekaclaw.codex_manager import _read_codex_cli_tokens

        auth_path = tmp_path / ".codex" / "auth.json"
        auth_path.parent.mkdir(parents=True, exist_ok=True)
        auth_path.write_text(json.dumps({
            "tokens": {"access_token": "", "refresh_token": "rt"},
        }))

        with patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", auth_path):
            assert _read_codex_cli_tokens() is None

    def test_setup_codex_env_sets_api_key(self):
        from eurekaclaw.codex_manager import setup_codex_env

        old = os.environ.get("OPENAI_COMPAT_API_KEY")
        try:
            setup_codex_env("sk-injected-token")
            assert os.environ["OPENAI_COMPAT_API_KEY"] == "sk-injected-token"
        finally:
            if old is not None:
                os.environ["OPENAI_COMPAT_API_KEY"] = old
            else:
                os.environ.pop("OPENAI_COMPAT_API_KEY", None)

    def test_load_valid_tokens_from_codex_cli(self, tmp_path):
        """When EurekaClaw store is empty, falls back to Codex CLI file."""
        from eurekaclaw.codex_manager import _load_valid_tokens
        from eurekaclaw.auth import token_store

        auth_path = tmp_path / ".codex" / "auth.json"
        self._write_codex_auth(auth_path, access_token="sk-from-cli")
        creds_dir = tmp_path / "creds"
        creds_dir.mkdir()

        with (
            patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", auth_path),
            patch.object(token_store, "_creds_dir", return_value=creds_dir),
        ):
            tokens = _load_valid_tokens()

        assert tokens is not None
        assert tokens["access_token"] == "sk-from-cli"

    def test_load_valid_tokens_prefers_eurekaclaw_store(self, tmp_path):
        """EurekaClaw's own store takes priority over Codex CLI file."""
        from eurekaclaw.codex_manager import _load_valid_tokens
        from eurekaclaw.auth import token_store

        # Write both sources with different tokens
        auth_path = tmp_path / ".codex" / "auth.json"
        self._write_codex_auth(auth_path, access_token="sk-from-cli")

        creds_dir = tmp_path / "creds"
        creds_dir.mkdir()

        with patch.object(token_store, "_creds_dir", return_value=creds_dir):
            # Pre-populate EurekaClaw store with a non-expired token
            token_store.save_tokens("openai-codex", {
                "access_token": "sk-from-store",
                "refresh_token": "rt-store",
                "expires_in": 3600,
            })

        with (
            patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", auth_path),
            patch.object(token_store, "_creds_dir", return_value=creds_dir),
        ):
            tokens = _load_valid_tokens()

        assert tokens is not None
        assert tokens["access_token"] == "sk-from-store"

    def test_load_valid_tokens_none_when_no_credentials(self, tmp_path):
        """Returns None when neither store nor CLI file exists."""
        from eurekaclaw.codex_manager import _load_valid_tokens
        from eurekaclaw.auth import token_store

        missing_path = tmp_path / ".codex" / "auth.json"
        creds_dir = tmp_path / "creds"
        creds_dir.mkdir()

        with (
            patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", missing_path),
            patch.object(token_store, "_creds_dir", return_value=creds_dir),
        ):
            assert _load_valid_tokens() is None

    def test_maybe_setup_codex_auth_skips_when_not_oauth(self):
        """No-op when codex_auth_mode != 'oauth'."""
        from eurekaclaw.codex_manager import maybe_setup_codex_auth

        with patch("eurekaclaw.config.settings") as mock_settings:
            mock_settings.codex_auth_mode = "api_key"
            # Should return without doing anything
            maybe_setup_codex_auth()

    def test_maybe_setup_codex_auth_raises_when_no_creds(self, tmp_path):
        """Raises RuntimeError when oauth mode is set but no credentials exist."""
        from eurekaclaw.codex_manager import maybe_setup_codex_auth
        from eurekaclaw.auth import token_store

        missing_path = tmp_path / ".codex" / "auth.json"
        creds_dir = tmp_path / "creds"
        creds_dir.mkdir()

        with (
            patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", missing_path),
            patch.object(token_store, "_creds_dir", return_value=creds_dir),
            patch("eurekaclaw.config.settings") as mock_settings,
        ):
            mock_settings.codex_auth_mode = "oauth"
            with pytest.raises(RuntimeError, match="no OpenAI Codex credentials found"):
                maybe_setup_codex_auth()

    def test_maybe_setup_codex_auth_injects_token(self, tmp_path):
        """Full end-to-end: oauth mode + valid CLI file → env var set."""
        from eurekaclaw.codex_manager import maybe_setup_codex_auth
        from eurekaclaw.auth import token_store

        auth_path = tmp_path / ".codex" / "auth.json"
        self._write_codex_auth(auth_path, access_token="sk-e2e-test")
        creds_dir = tmp_path / "creds"
        creds_dir.mkdir()

        old = os.environ.get("OPENAI_COMPAT_API_KEY")
        try:
            with (
                patch("eurekaclaw.codex_manager._CODEX_CLI_AUTH_PATH", auth_path),
                patch.object(token_store, "_creds_dir", return_value=creds_dir),
                patch("eurekaclaw.config.settings") as mock_settings,
            ):
                mock_settings.codex_auth_mode = "oauth"
                maybe_setup_codex_auth()

            assert os.environ["OPENAI_COMPAT_API_KEY"] == "sk-e2e-test"
        finally:
            if old is not None:
                os.environ["OPENAI_COMPAT_API_KEY"] = old
            else:
                os.environ.pop("OPENAI_COMPAT_API_KEY", None)


# ============================================================================
# 4. LLM factory — codex backend alias
# ============================================================================


class TestFactoryCodexBackend:
    def test_codex_alias_resolves_to_openai_compat(self):
        from eurekaclaw.llm.factory import _BACKEND_ALIASES

        assert "codex" in _BACKEND_ALIASES
        resolved_backend, base_url = _BACKEND_ALIASES["codex"]
        assert resolved_backend == "openai_compat"
        assert base_url == "https://api.openai.com/v1"

    def test_create_client_codex_backend(self):
        """create_client(backend='codex') calls OpenAICompatAdapter with correct args when auth_mode=api_key."""
        from unittest.mock import MagicMock

        MockCls = MagicMock()
        fake_module = MagicMock(OpenAICompatAdapter=MockCls)

        import sys
        with patch.dict(sys.modules, {"eurekaclaw.llm.openai_compat": fake_module}):
            # Re-import to pick up the patched module
            import importlib
            import eurekaclaw.llm.factory as factory_mod
            importlib.reload(factory_mod)

            with patch("eurekaclaw.config.settings") as mock_settings:
                mock_settings.codex_auth_mode = "api_key"
                mock_settings.llm_backend = "codex"
                mock_settings.openai_compat_base_url = ""
                mock_settings.openai_compat_api_key = ""
                mock_settings.codex_model = "o4-mini"

                factory_mod.create_client(
                    backend="codex",
                    openai_api_key="sk-test-key",
                    openai_model="o4-mini",
                )

                MockCls.assert_called_once_with(
                    base_url="https://api.openai.com/v1",
                    api_key="sk-test-key",
                    default_model="o4-mini",
                )

    def test_create_client_codex_reads_env_api_key(self):
        """When backend=codex (api_key mode), factory reads OPENAI_COMPAT_API_KEY from env."""
        from unittest.mock import MagicMock

        MockCls = MagicMock()
        fake_module = MagicMock(OpenAICompatAdapter=MockCls)

        old = os.environ.get("OPENAI_COMPAT_API_KEY")
        try:
            os.environ["OPENAI_COMPAT_API_KEY"] = "sk-from-env"

            import sys
            with patch.dict(sys.modules, {"eurekaclaw.llm.openai_compat": fake_module}):
                import importlib
                import eurekaclaw.llm.factory as factory_mod
                importlib.reload(factory_mod)

                with patch("eurekaclaw.config.settings") as mock_settings:
                    mock_settings.codex_auth_mode = "api_key"
                    mock_settings.llm_backend = "codex"
                    mock_settings.openai_compat_base_url = ""
                    mock_settings.openai_compat_api_key = ""
                    mock_settings.codex_model = "o4-mini"

                    factory_mod.create_client(
                        backend="codex",
                        openai_model="o4-mini",
                    )

                    MockCls.assert_called_once()
                    _, kwargs = MockCls.call_args
                    assert kwargs["api_key"] == "sk-from-env"
        finally:
            if old is not None:
                os.environ["OPENAI_COMPAT_API_KEY"] = old
            else:
                os.environ.pop("OPENAI_COMPAT_API_KEY", None)
