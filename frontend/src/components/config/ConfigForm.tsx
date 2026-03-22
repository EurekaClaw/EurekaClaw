import { useState, useEffect } from 'react';
import { apiGet, apiPost } from '@/api/client';
import { AuthGuidance } from './AuthGuidance';
import type { AppConfig } from '@/types';

interface ConfigResponse {
  config: AppConfig;
}

interface TestResponse {
  ok: boolean;
  message?: string;
  reply_preview?: string;
}

interface OAuthStatusResponse {
  installed: boolean;
  authenticated: boolean;
  message: string;
}

const BACKENDS = [
  { key: 'anthropic', label: 'Anthropic', desc: 'Claude models via API key or OAuth' },
  { key: 'openai_compat', label: 'OpenAI Compatible', desc: 'OpenRouter, vLLM, LM Studio, etc.' },
] as const;

const AUTH_MODES = [
  { key: 'api_key', label: 'API Key', desc: 'Paste your Anthropic API key' },
  { key: 'oauth', label: 'OAuth', desc: 'Login via ccproxy (Claude Pro/Max)' },
] as const;

const GATE_MODES = [
  { key: 'auto', label: 'Smart', desc: 'Pause when confidence is low' },
  { key: 'human', label: 'Always review', desc: 'Pause at every gate' },
  { key: 'none', label: 'Autonomous', desc: 'Fully automatic, no pauses' },
] as const;

interface Props {
  onRefreshHealth?: () => void;
}

export function ConfigForm({ onRefreshHealth }: Props) {
  const [config, setConfig] = useState<AppConfig>({});
  const [saveStatus, setSaveStatus] = useState('');
  const [statusType, setStatusType] = useState<'info' | 'ok' | 'error'>('info');
  const [installing, setInstalling] = useState(false);
  const [oauthStatus, setOauthStatus] = useState<OAuthStatusResponse | null>(null);
  const [loggingIn, setLoggingIn] = useState(false);

  const backend = (config.llm_backend as string) || 'anthropic';
  const authMode = (config.anthropic_auth_mode as string) || 'api_key';
  const ccproxyPort = String(config.ccproxy_port || '8000');

  const showOauth = backend === 'anthropic' && authMode === 'oauth';
  const showApiKey = backend === 'anthropic' && authMode === 'api_key';
  const showOpenAiCompat = backend === 'openai_compat';

  useEffect(() => {
    void loadConfig();
  }, []);

  useEffect(() => {
    if (showOauth) void checkOauthStatus();
  }, [showOauth]);

  const loadConfig = async () => {
    try {
      const data = await apiGet<ConfigResponse>('/api/config');
      setConfig(data.config ?? {});
    } catch (err) {
      setStatus(`Could not load config: ${(err as Error).message}`, 'error');
    }
  };

  const checkOauthStatus = async () => {
    try {
      const data = await apiGet<OAuthStatusResponse>('/api/oauth/status');
      setOauthStatus(data);
    } catch {
      setOauthStatus(null);
    }
  };

  const setStatus = (msg: string, type: 'info' | 'ok' | 'error' = 'info') => {
    setSaveStatus(msg);
    setStatusType(type);
  };

  const handleChange = (name: string, value: string | boolean) => {
    setConfig((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('Saving…', 'info');
    try {
      await apiPost('/api/config', config);
      setStatus('Configuration saved successfully.', 'ok');
      onRefreshHealth?.();
    } catch (err) {
      setStatus(`Save failed: ${(err as Error).message}`, 'error');
    }
  };

  const installOauth = async () => {
    setInstalling(true);
    setStatus('Installing OAuth dependencies (pip install -e \'.[oauth]\')…', 'info');
    try {
      const result = await apiPost<{ ok: boolean; message: string }>('/api/oauth/install', {});
      if (result.ok) {
        setStatus('OAuth dependencies installed. Checking status…', 'ok');
        await checkOauthStatus();
      } else {
        setStatus(`Install failed: ${result.message}`, 'error');
      }
    } catch (err) {
      setStatus(`Install error: ${(err as Error).message}`, 'error');
    } finally {
      setInstalling(false);
    }
  };

  const loginOauth = async () => {
    setLoggingIn(true);
    setStatus('Starting OAuth login — check your browser…', 'info');
    try {
      const result = await apiPost<{ ok: boolean; message: string }>('/api/oauth/login', {});
      if (result.ok) {
        setStatus('OAuth login initiated. Complete authorization in your browser, then click "Save & test".', 'ok');
        // Re-check status after a short delay
        setTimeout(() => void checkOauthStatus(), 3000);
      } else {
        setStatus(`Login failed: ${result.message}`, 'error');
      }
    } catch (err) {
      setStatus(`Login error: ${(err as Error).message}`, 'error');
    } finally {
      setLoggingIn(false);
    }
  };

  const testConnection = async (saveAfter = false) => {
    // For OAuth: save config first, then test (which triggers ccproxy + authorize)
    if (showOauth && saveAfter) {
      setStatus('Saving config and testing OAuth connection…', 'info');
      try {
        await apiPost('/api/config', config);
        await loadConfig();
        onRefreshHealth?.();
      } catch (err) {
        setStatus(`Save failed: ${(err as Error).message}`, 'error');
        return;
      }
    }

    setStatus(saveAfter ? 'Testing & saving…' : 'Testing connection…', 'info');
    try {
      const result = await apiPost<TestResponse>('/api/auth/test', config);
      if (!result.ok) {
        const msg = result.message ?? 'unknown error';
        // If OAuth not installed, show install hint
        if (msg.includes('ccproxy') && msg.includes('not found')) {
          setStatus('ccproxy not found. Click "Install OAuth" below to set it up.', 'error');
        } else if (msg.includes('not authenticated')) {
          setStatus('OAuth not authenticated. Click "Login with Anthropic" to authorize.', 'error');
        } else {
          setStatus(`Connection failed: ${msg}`, 'error');
        }
        return;
      }
      if (saveAfter && !showOauth) {
        await apiPost('/api/config', config);
        await loadConfig();
        onRefreshHealth?.();
      }
      setStatus(`Connected and saved. Preview: ${result.reply_preview || 'OK'}`, 'ok');
    } catch (err) {
      setStatus(`Connection error: ${(err as Error).message}`, 'error');
    }
  };

  const val = (key: string) => String(config[key] ?? '');
  const checked = (key: string) => config[key] === true || config[key] === 'true';

  const sliderKeys = [
    { name: 'max_tokens_agent', label: 'Agent loop', min: 1024, max: 20480, step: 512 },
    { name: 'max_tokens_prover', label: 'Prover', min: 512, max: 20480, step: 256 },
    { name: 'max_tokens_planner', label: 'Planner', min: 512, max: 16384, step: 256 },
    { name: 'max_tokens_architect', label: 'Architect', min: 512, max: 16384, step: 256 },
    { name: 'max_tokens_decomposer', label: 'Decomposer', min: 256, max: 16384, step: 256 },
    { name: 'max_tokens_assembler', label: 'Assembler', min: 512, max: 20480, step: 256 },
    { name: 'max_tokens_formalizer', label: 'Formalizer / Refiner', min: 256, max: 16384, step: 256 },
    { name: 'max_tokens_crystallizer', label: 'TheoremCrystallizer', min: 256, max: 20480, step: 256 },
    { name: 'max_tokens_analyst', label: 'Analyst', min: 256, max: 16384, step: 256 },
    { name: 'max_tokens_sketch', label: 'Sketch', min: 256, max: 8192, step: 256 },
    { name: 'max_tokens_verifier', label: 'Verifier', min: 128, max: 16384, step: 128 },
    { name: 'max_tokens_compress', label: 'Context compress', min: 128, max: 4096, step: 128 },
  ];

  return (
    <form className="settings-form" id="config-form" onSubmit={(e) => void handleSubmit(e)}>
      {/* ── Section 1: LLM Connection ───────────────────────────── */}
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

            {/* OAuth status & action buttons */}
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
                  <button
                    className="settings-oauth-btn"
                    type="button"
                    disabled={installing}
                    onClick={() => void installOauth()}
                  >
                    {installing ? 'Installing…' : 'Install OAuth dependencies'}
                  </button>
                )}
                {oauthStatus?.installed && !oauthStatus.authenticated && (
                  <button
                    className="settings-oauth-btn settings-oauth-btn--login"
                    type="button"
                    disabled={loggingIn}
                    onClick={() => void loginOauth()}
                  >
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

        <AuthGuidance backend={backend} authMode={authMode} ccproxyPort={ccproxyPort} />

        {/* Primary / Fast model — only for Anthropic */}
        {backend === 'anthropic' && (
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

        {/* Connection test buttons */}
        <div className="settings-action-row">
          <button className="secondary-btn" type="button" onClick={() => void testConnection(false)}>
            Test connection
          </button>
          <button className="primary-btn" type="button" onClick={() => void testConnection(true)}>
            Save &amp; test
          </button>
        </div>
      </section>

      {/* ── Section 2: Pipeline ──────────────────────────────────── */}
      <section className="settings-section">
        <div className="settings-section-header">
          <span className="settings-section-icon">⚙</span>
          <div>
            <h3 className="settings-section-title">Pipeline</h3>
            <p className="settings-section-desc">Control how EurekaClaw runs proofs</p>
          </div>
        </div>

        <div className="settings-inline-row">
          <label className="settings-field">
            <span className="settings-field-label">Theory pipeline</span>
            <select name="theory_pipeline" value={val('theory_pipeline') || 'default'} onChange={(e) => handleChange('theory_pipeline', e.target.value)}>
              <option value="default">Default</option>
              <option value="memory_guided">Memory-guided</option>
            </select>
          </label>
          <label className="settings-field">
            <span className="settings-field-label">Max iterations</span>
            <input type="number" name="theory_max_iterations" min={1} value={val('theory_max_iterations')} onChange={(e) => handleChange('theory_max_iterations', e.target.value)} />
          </label>
        </div>

        <div className="settings-card-group">
          <p className="settings-field-label">Human-in-the-loop</p>
          <div className="settings-card-row">
            {GATE_MODES.map((g) => (
              <button
                key={g.key}
                type="button"
                className={`settings-option-card${(val('gate_mode') || 'auto') === g.key ? ' is-active' : ''}`}
                onClick={() => handleChange('gate_mode', g.key)}
              >
                <span className="settings-option-label">{g.label}</span>
                <span className="settings-option-desc">{g.desc}</span>
              </button>
            ))}
          </div>
        </div>

        <label className="settings-field">
          <span className="settings-field-label">Experiment mode</span>
          <select name="experiment_mode" value={val('experiment_mode') || 'auto'} onChange={(e) => handleChange('experiment_mode', e.target.value)}>
            <option value="auto">Auto — run when quantitative bounds found</option>
            <option value="true">Always run validation</option>
            <option value="false">Skip validation</option>
          </select>
        </label>
      </section>

      {/* ── Section 3: Output & Paper ────────────────────────────── */}
      <section className="settings-section">
        <div className="settings-section-header">
          <span className="settings-section-icon">📄</span>
          <div>
            <h3 className="settings-section-title">Output &amp; Paper</h3>
            <p className="settings-section-desc">Paper reader and output format</p>
          </div>
        </div>

        <div className="settings-inline-row">
          <label className="settings-field">
            <span className="settings-field-label">Output format</span>
            <select name="output_format" value={val('output_format') || 'latex'} onChange={(e) => handleChange('output_format', e.target.value)}>
              <option value="latex">LaTeX</option>
              <option value="markdown">Markdown</option>
            </select>
          </label>
          <label className="settings-field">
            <span className="settings-field-label">Coarse read papers</span>
            <input type="number" name="paper_reader_abstract_papers" min={1} max={20} value={val('paper_reader_abstract_papers')} onChange={(e) => handleChange('paper_reader_abstract_papers', e.target.value)} />
          </label>
          <label className="settings-field">
            <span className="settings-field-label">Deep read papers</span>
            <input type="number" name="paper_reader_pdf_papers" min={0} max={20} value={val('paper_reader_pdf_papers')} onChange={(e) => handleChange('paper_reader_pdf_papers', e.target.value)} />
          </label>
        </div>

        <label className="switch-field">
          <span className="switch-field-copy"><strong>PDF deep read</strong> — download and parse full PDFs from arXiv</span>
          <span className="switch-control">
            <input type="checkbox" name="paper_reader_use_pdf" checked={checked('paper_reader_use_pdf')} onChange={(e) => handleChange('paper_reader_use_pdf', e.target.checked)} />
            <span className="switch-slider" aria-hidden="true" />
          </span>
        </label>
      </section>

      {/* ── Section 4: Advanced ──────────────────────────────────── */}
      <section className="settings-section">
        <div className="settings-section-header">
          <span className="settings-section-icon">🔧</span>
          <div>
            <h3 className="settings-section-title">Advanced</h3>
            <p className="settings-section-desc">Confidence thresholds, directories, and token limits</p>
          </div>
        </div>

        <div className="settings-inline-row">
          <label className="settings-field">
            <span className="settings-field-label">Auto-verify confidence</span>
            <input type="number" name="auto_verify_confidence" min={0} max={1} step={0.01} value={val('auto_verify_confidence')} onChange={(e) => handleChange('auto_verify_confidence', e.target.value)} />
          </label>
          <label className="settings-field">
            <span className="settings-field-label">Verifier pass confidence</span>
            <input type="number" name="verifier_pass_confidence" min={0} max={1} step={0.01} value={val('verifier_pass_confidence')} onChange={(e) => handleChange('verifier_pass_confidence', e.target.value)} />
          </label>
        </div>

        <label className="settings-field">
          <span className="settings-field-label">Data directory</span>
          <input type="text" name="eurekaclaw_dir" placeholder="~/.eurekaclaw" value={val('eurekaclaw_dir')} onChange={(e) => handleChange('eurekaclaw_dir', e.target.value)} />
        </label>

        <details className="settings-details">
          <summary>Token limits per agent</summary>
          <fieldset className="token-limits-group">
            {sliderKeys.map(({ name, label, min, max, step }) => (
              <label key={name} className="slider-label">
                <span>{label} <em id={`${name}-val`}>{val(name)}</em></span>
                <input
                  type="range"
                  name={name}
                  min={min}
                  max={max}
                  step={step}
                  value={val(name) || String(min)}
                  onChange={(e) => handleChange(name, e.target.value)}
                />
              </label>
            ))}
          </fieldset>
        </details>
      </section>

      {/* ── Bottom action bar ────────────────────────────────────── */}
      <div className="settings-bottom-bar">
        <div className="settings-bottom-actions">
          <button className="primary-btn" type="submit">Save all settings</button>
        </div>
        {saveStatus && (
          <p className={`settings-status-msg settings-status-msg--${statusType}`}>{saveStatus}</p>
        )}
      </div>
    </form>
  );
}
