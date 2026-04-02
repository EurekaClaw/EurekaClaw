import { AuthGuidance } from './AuthGuidance';
import type { OAuthStatusResponse, ConfigSectionProps } from './configTypes';

const BACKENDS = [
  { key: 'anthropic', label: 'Anthropic', desc: 'Claude models via API key or OAuth' },
  { key: 'codex', label: 'OpenAI (Codex)', desc: 'OpenAI Codex via API key or OAuth' },
  { key: 'openai_compat', label: 'OpenAI Compatible', desc: 'OpenRouter, vLLM, LM Studio, etc.' },
] as const;

const AUTH_MODES = [
  { key: 'api_key', label: 'API Key', desc: 'Paste your Anthropic API key' },
  { key: 'oauth', label: 'OAuth', desc: 'Login via ccproxy (Claude Pro/Max)' },
] as const;

const CODEX_AUTH_MODES = [
  { key: 'api_key', label: 'API Key', desc: 'Paste your OpenAI API key' },
  { key: 'oauth', label: 'Codex CLI', desc: 'Use ChatGPT Plus/Pro subscription via Codex CLI' },
] as const;

const CODEX_OAUTH_MODELS = ['gpt-5.1-codex-mini', 'gpt-5.1-codex', 'gpt-5-codex-mini', 'gpt-5-codex'] as const;
const CODEX_APIKEY_MODELS = ['o4-mini', 'o3', 'gpt-4.1', 'gpt-4.1-mini'] as const;

interface LLMSectionProps extends ConfigSectionProps {
  oauthStatus: OAuthStatusResponse | null;
  codexStatus: OAuthStatusResponse | null;
  openaiPkgStatus: { installed: boolean } | null;
  onInstallOauth: () => void;
  onLoginOauth: () => void;
  onImportCodex: () => void;
  onInstallOpenai: () => void;
  onTestConnection: (saveAfter: boolean) => void;
  installing: boolean;
  loggingIn: boolean;
  codexImporting: boolean;
  installingOpenai: boolean;
  saveStatus: string;
  statusType: 'info' | 'ok' | 'error';
}

export function LLMSection({
  config, val, handleChange,
  oauthStatus, codexStatus, openaiPkgStatus,
  onInstallOauth, onLoginOauth, onImportCodex, onInstallOpenai, onTestConnection,
  installing, loggingIn, codexImporting, installingOpenai,
  saveStatus, statusType,
}: LLMSectionProps) {
  const rawBackend = (config.llm_backend as string) || 'anthropic';
  const backend = rawBackend === 'oauth' ? 'anthropic' : rawBackend;
  const authMode = rawBackend === 'oauth' ? 'oauth' : ((config.anthropic_auth_mode as string) || 'api_key');
  const codexAuthMode = (config.codex_auth_mode as string) || 'api_key';
  const ccproxyPort = String(config.ccproxy_port || '8000');

  const showOauth = backend === 'anthropic' && authMode === 'oauth';
  const showApiKey = backend === 'anthropic' && authMode === 'api_key';
  const showOpenAiCompat = backend === 'openai_compat';
  const showCodex = backend === 'codex';
  const showCodexApiKey = showCodex && codexAuthMode === 'api_key';
  const showCodexOauth = showCodex && codexAuthMode === 'oauth';

  return (
    <section className="settings-section">
      <div className="settings-section-header">
        <span className="settings-section-icon">🔗</span>
        <div>
          <h3 className="settings-section-title">LLM Connection</h3>
          <p className="settings-section-desc">Choose your AI backend and authentication</p>
        </div>
      </div>

      <div className="settings-card-group">
        <p className="settings-field-label">Backend provider</p>
        <div className="settings-card-row settings-card-row--half">
          {BACKENDS.map((b) => (
            <button
              key={b.key}
              type="button"
              className={`settings-option-card${backend === b.key ? ' is-active' : ''}`}
              onClick={() => handleChange('llm_backend', b.key)}
            >
              <span className="settings-option-label">{b.label}</span>
              <span className="settings-option-desc">{b.desc}</span>
            </button>
          ))}
        </div>
      </div>

      {backend === 'anthropic' && (
        <div className="settings-card-group">
          <p className="settings-field-label">Authentication</p>
          <div className="settings-card-row settings-card-row--half">
            {AUTH_MODES.map((a) => (
              <button
                key={a.key}
                type="button"
                className={`settings-option-card${authMode === a.key ? ' is-active' : ''}`}
                onClick={() => handleChange('anthropic_auth_mode', a.key)}
              >
                <span className="settings-option-label">{a.label}</span>
                <span className="settings-option-desc">{a.desc}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {showApiKey && (
        <label className="settings-field">
          <span className="settings-field-label">Anthropic API Key</span>
          <input type="password" name="anthropic_api_key" placeholder="sk-ant-…" value={val('anthropic_api_key')} onChange={(e) => handleChange('anthropic_api_key', e.target.value)} />
        </label>
      )}

      {showOauth && (
        <>
          <label className="settings-field">
            <span className="settings-field-label">ccproxy port</span>
            <input type="number" name="ccproxy_port" min={1} max={65535} value={val('ccproxy_port')} onChange={(e) => handleChange('ccproxy_port', e.target.value)} />
          </label>
          <div className="settings-oauth-panel">
            <div className="settings-oauth-status">
              <span className={`settings-oauth-dot${oauthStatus?.installed && oauthStatus?.authenticated ? ' is-ok' : ''}`} />
              <span className="settings-oauth-text">
                {!oauthStatus ? 'Checking OAuth status…' :
                 !oauthStatus.installed ? 'ccproxy not installed' :
                 !oauthStatus.authenticated ? 'Not authenticated' :
                 oauthStatus.message}
              </span>
            </div>
            <div className="settings-oauth-actions">
              {(!oauthStatus || !oauthStatus.installed) && (
                <button className="settings-oauth-btn" type="button" disabled={installing} onClick={onInstallOauth}>
                  {installing ? 'Installing…' : 'Install OAuth dependencies'}
                </button>
              )}
              {oauthStatus?.installed && !oauthStatus.authenticated && (
                <button className="settings-oauth-btn settings-oauth-btn--login" type="button" disabled={loggingIn} onClick={onLoginOauth}>
                  {loggingIn ? 'Opening browser…' : 'Login with Anthropic'}
                </button>
              )}
              {oauthStatus?.installed && oauthStatus.authenticated && (
                <span className="settings-oauth-ok">Ready</span>
              )}
            </div>
          </div>
        </>
      )}

      {showOpenAiCompat && (
        <div className="settings-field-group">
          <label className="settings-field">
            <span className="settings-field-label">Base URL</span>
            <input type="text" name="openai_compat_base_url" placeholder="https://api.openrouter.ai/v1" value={val('openai_compat_base_url')} onChange={(e) => handleChange('openai_compat_base_url', e.target.value)} />
          </label>
          <label className="settings-field">
            <span className="settings-field-label">API Key</span>
            <input type="password" name="openai_compat_api_key" value={val('openai_compat_api_key')} onChange={(e) => handleChange('openai_compat_api_key', e.target.value)} />
          </label>
          <label className="settings-field">
            <span className="settings-field-label">Model</span>
            <input type="text" name="openai_compat_model" placeholder="gpt-4o" value={val('openai_compat_model')} onChange={(e) => handleChange('openai_compat_model', e.target.value)} />
          </label>
        </div>
      )}

      {showCodex && (
        <div className="codex-panel">
          <div className="codex-auth-section">
            <p className="settings-field-label">Authentication</p>
            <div className="codex-segment-control">
              {CODEX_AUTH_MODES.map((a) => (
                <button
                  key={a.key}
                  type="button"
                  className={`codex-segment-btn${codexAuthMode === a.key ? ' is-active' : ''}`}
                  onClick={() => handleChange('codex_auth_mode', a.key)}
                >
                  <span className="codex-segment-label">{a.label}</span>
                </button>
              ))}
            </div>
            <p className="codex-auth-hint">
              {codexAuthMode === 'oauth'
                ? 'Routes through ChatGPT backend — billed to your ChatGPT Plus/Pro subscription. Requires Codex-specific models.'
                : 'Uses Chat Completions API — billed to your OpenAI API credits'}
            </p>
          </div>

          {showCodexApiKey && (
            <label className="settings-field">
              <span className="settings-field-label">OpenAI API Key</span>
              <input type="password" name="openai_compat_api_key" placeholder="sk-…" value={val('openai_compat_api_key')} onChange={(e) => handleChange('openai_compat_api_key', e.target.value)} />
            </label>
          )}

          {showCodexOauth && (
            <div className="codex-setup-checklist">
              <div className={`codex-check-item${codexStatus?.authenticated ? ' is-done' : ''}`}>
                <div className="codex-check-icon">
                  {codexStatus?.authenticated
                    ? <svg width="16" height="16" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="8" fill="var(--ok)"/><path d="M4.5 8.5L7 11L11.5 5.5" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>
                    : <svg width="16" height="16" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="7" stroke="var(--muted)" strokeWidth="1.5" strokeDasharray="3 2"/><text x="8" y="11" textAnchor="middle" fill="var(--muted)" fontSize="9" fontWeight="600">1</text></svg>
                  }
                </div>
                <div className="codex-check-body">
                  <span className="codex-check-title">Codex CLI credentials</span>
                  <span className="codex-check-desc">
                    {!codexStatus ? 'Checking…' : codexStatus.authenticated ? 'Token imported and ready' : 'Run codex auth login, then import'}
                  </span>
                </div>
                {(!codexStatus || !codexStatus.authenticated) && (
                  <button className="codex-check-btn" type="button" disabled={codexImporting} onClick={onImportCodex}>
                    {codexImporting ? 'Importing…' : 'Import'}
                  </button>
                )}
              </div>
              <div className={`codex-check-item${openaiPkgStatus?.installed ? ' is-done' : ''}`}>
                <div className="codex-check-icon">
                  {openaiPkgStatus?.installed
                    ? <svg width="16" height="16" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="8" fill="var(--ok)"/><path d="M4.5 8.5L7 11L11.5 5.5" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>
                    : <svg width="16" height="16" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="7" stroke="var(--muted)" strokeWidth="1.5" strokeDasharray="3 2"/><text x="8" y="11" textAnchor="middle" fill="var(--muted)" fontSize="9" fontWeight="600">2</text></svg>
                  }
                </div>
                <div className="codex-check-body">
                  <span className="codex-check-title">OpenAI Python package</span>
                  <span className="codex-check-desc">
                    {!openaiPkgStatus ? 'Checking…' : openaiPkgStatus.installed ? 'Installed' : 'Required dependency for API calls'}
                  </span>
                </div>
                {openaiPkgStatus && !openaiPkgStatus.installed && (
                  <button className="codex-check-btn" type="button" disabled={installingOpenai} onClick={onInstallOpenai}>
                    {installingOpenai ? 'Installing…' : 'Install'}
                  </button>
                )}
              </div>
            </div>
          )}

          <div className="codex-model-section">
            <label className="settings-field">
              <span className="settings-field-label">Model</span>
              <input type="text" name="codex_model" placeholder="o4-mini" value={val('codex_model')} onChange={(e) => handleChange('codex_model', e.target.value)} />
            </label>
            <div className="codex-model-chips">
              {(codexAuthMode === 'oauth' ? CODEX_OAUTH_MODELS : CODEX_APIKEY_MODELS).map((m) => (
                <button key={m} type="button" className={`codex-model-chip${val('codex_model') === m ? ' is-active' : ''}`} onClick={() => handleChange('codex_model', m)}>
                  {m}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      <AuthGuidance backend={backend} authMode={showCodex ? codexAuthMode : authMode} ccproxyPort={ccproxyPort} />

      {(backend === 'anthropic' || backend === 'openai_compat') && (
        <div className="settings-inline-row">
          <label className="settings-field">
            <span className="settings-field-label">Primary model</span>
            <input type="text" name="eurekaclaw_model" placeholder="claude-sonnet-4-20250514" value={val('eurekaclaw_model')} onChange={(e) => handleChange('eurekaclaw_model', e.target.value)} />
          </label>
          <label className="settings-field">
            <span className="settings-field-label">Fast model</span>
            <input type="text" name="eurekaclaw_fast_model" placeholder="claude-haiku-4-20250414" value={val('eurekaclaw_fast_model')} onChange={(e) => handleChange('eurekaclaw_fast_model', e.target.value)} />
          </label>
        </div>
      )}

      <div className="settings-action-row">
        <button className="secondary-btn" type="button" onClick={() => onTestConnection(false)}>Test connection</button>
        <button className="primary-btn" type="button" onClick={() => onTestConnection(true)}>Save &amp; test</button>
      </div>
      {saveStatus && (
        <p className={`settings-status-msg settings-status-msg--${statusType}`}>{saveStatus}</p>
      )}
    </section>
  );
}
