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

export function ConfigForm() {
  const [config, setConfig] = useState<AppConfig>({});
  const [saveStatus, setSaveStatus] = useState('Config values are loaded from the live backend.');

  const backend = (config.llm_backend as string) || 'anthropic';
  const authMode = (config.anthropic_auth_mode as string) || 'api_key';
  const ccproxyPort = String(config.ccproxy_port || '8000');

  const showBackendAnthropicOnly = backend === 'anthropic';
  const showOauth = backend === 'anthropic' && authMode === 'oauth';
  const showOpenAiCompat = backend === 'openai_compat';
  const showMinimax = backend === 'minimax';
  const showApiKey = backend === 'anthropic' && authMode === 'api_key';

  useEffect(() => {
    void loadConfig();
  }, []);

  const loadConfig = async () => {
    try {
      const data = await apiGet<ConfigResponse>('/api/config');
      setConfig(data.config ?? {});
    } catch (err) {
      setSaveStatus(`Could not load config: ${(err as Error).message}`);
    }
  };

  const handleChange = (name: string, value: string | boolean) => {
    setConfig((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaveStatus('Saving configuration...');
    try {
      await apiPost('/api/config', config);
      setSaveStatus('Configuration saved to the live backend and .env.');
    } catch (err) {
      setSaveStatus(`Could not save config: ${(err as Error).message}`);
    }
  };

  const testConnection = async (saveAfter = false) => {
    setSaveStatus(saveAfter ? 'Testing connection before saving...' : 'Testing connection...');
    try {
      const result = await apiPost<TestResponse>('/api/auth/test', config);
      if (!result.ok) {
        setSaveStatus(`Connection failed: ${result.message ?? 'unknown'}`);
        return;
      }
      if (saveAfter) {
        await apiPost('/api/config', config);
        await loadConfig();
        setSaveStatus(`Connection verified and config saved. Reply preview: ${result.reply_preview || 'OK'}`);
        return;
      }
      setSaveStatus(`Connection verified. Reply preview: ${result.reply_preview || 'OK'}`);
      setTimeout(() => setSaveStatus((prev) => prev.startsWith('Connection verified.') ? 'Config values are loaded from the live backend.' : prev), 5000);
    } catch (err) {
      setSaveStatus(`Could not test connection: ${(err as Error).message}`);
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
    <form className="config-form" id="config-form" onSubmit={(e) => void handleSubmit(e)}>
      <label>
        <span>LLM backend</span>
        <select name="llm_backend" value={val('llm_backend') || 'anthropic'} onChange={(e) => handleChange('llm_backend', e.target.value)}>
          <option value="anthropic">anthropic</option>
          <option value="openai_compat">openai_compat</option>
          <option value="minimax">minimax</option>
        </select>
      </label>

      {showBackendAnthropicOnly && (
        <label>
          <span>Auth mode</span>
          <select name="anthropic_auth_mode" value={val('anthropic_auth_mode') || 'api_key'} onChange={(e) => handleChange('anthropic_auth_mode', e.target.value)}>
            <option value="api_key">api_key</option>
            <option value="oauth">oauth</option>
          </select>
        </label>
      )}

      {showOauth && (
        <label>
          <span>ccproxy port</span>
          <input type="number" name="ccproxy_port" min={1} max={65535} value={val('ccproxy_port')} onChange={(e) => handleChange('ccproxy_port', e.target.value)} />
        </label>
      )}

      <label>
        <span>Primary model</span>
        <input type="text" name="eurekaclaw_model" value={val('eurekaclaw_model')} onChange={(e) => handleChange('eurekaclaw_model', e.target.value)} />
      </label>
      <label>
        <span>Fast model</span>
        <input type="text" name="eurekaclaw_fast_model" value={val('eurekaclaw_fast_model')} onChange={(e) => handleChange('eurekaclaw_fast_model', e.target.value)} />
      </label>
      <label>
        <span>Theory pipeline</span>
        <select name="theory_pipeline" value={val('theory_pipeline') || 'default'} onChange={(e) => handleChange('theory_pipeline', e.target.value)}>
          <option value="default">default</option>
          <option value="memory_guided">memory_guided</option>
        </select>
      </label>
      <label>
        <span>Theory iterations</span>
        <input type="number" name="theory_max_iterations" min={1} value={val('theory_max_iterations')} onChange={(e) => handleChange('theory_max_iterations', e.target.value)} />
      </label>
      <label>
        <span>Gate mode</span>
        <select name="gate_mode" value={val('gate_mode') || 'auto'} onChange={(e) => handleChange('gate_mode', e.target.value)}>
          <option value="auto">auto — pause for human when confidence is low</option>
          <option value="human">human — always pause for review</option>
          <option value="none">none — fully autonomous</option>
        </select>
      </label>
      <label>
        <span>Experiment mode</span>
        <select name="experiment_mode" value={val('experiment_mode') || 'auto'} onChange={(e) => handleChange('experiment_mode', e.target.value)}>
          <option value="auto">auto — run only when quantitative bounds are found</option>
          <option value="true">true — always run validation stage</option>
          <option value="false">false — always skip validation stage</option>
        </select>
      </label>

      <details className="full-width token-limits-details">
        <summary>Token limits per call type</summary>
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

      <label>
        <span>Auto verify confidence</span>
        <input type="number" name="auto_verify_confidence" min={0} max={1} step={0.01} value={val('auto_verify_confidence')} onChange={(e) => handleChange('auto_verify_confidence', e.target.value)} />
      </label>
      <label>
        <span>Verifier pass confidence</span>
        <input type="number" name="verifier_pass_confidence" min={0} max={1} step={0.01} value={val('verifier_pass_confidence')} onChange={(e) => handleChange('verifier_pass_confidence', e.target.value)} />
      </label>
      <label>
        <span>Output format</span>
        <select name="output_format" value={val('output_format') || 'latex'} onChange={(e) => handleChange('output_format', e.target.value)}>
          <option value="latex">latex</option>
          <option value="markdown">markdown</option>
        </select>
      </label>
      <label className="switch-field">
        <span className="switch-field-copy"><strong>PDF deep read</strong></span>
        <span className="switch-control">
          <input type="checkbox" name="paper_reader_use_pdf" checked={checked('paper_reader_use_pdf')} onChange={(e) => handleChange('paper_reader_use_pdf', e.target.checked)} />
          <span className="switch-slider" aria-hidden="true" />
        </span>
      </label>
      <label>
        <span>Coarse read papers</span>
        <input type="number" name="paper_reader_abstract_papers" min={1} max={20} step={1} value={val('paper_reader_abstract_papers')} onChange={(e) => handleChange('paper_reader_abstract_papers', e.target.value)} />
      </label>
      <label>
        <span>Deep read papers</span>
        <input type="number" name="paper_reader_pdf_papers" min={0} max={20} step={1} value={val('paper_reader_pdf_papers')} onChange={(e) => handleChange('paper_reader_pdf_papers', e.target.value)} />
      </label>

      {showApiKey && (
        <label className="full-width">
          <span>Anthropic API key</span>
          <input type="password" name="anthropic_api_key" placeholder="Optional if using oauth" value={val('anthropic_api_key')} onChange={(e) => handleChange('anthropic_api_key', e.target.value)} />
        </label>
      )}
      {showOpenAiCompat && (
        <>
          <label className="full-width">
            <span>OpenAI-compatible base URL</span>
            <input type="text" name="openai_compat_base_url" value={val('openai_compat_base_url')} onChange={(e) => handleChange('openai_compat_base_url', e.target.value)} />
          </label>
          <label className="full-width">
            <span>OpenAI-compatible API key</span>
            <input type="password" name="openai_compat_api_key" value={val('openai_compat_api_key')} onChange={(e) => handleChange('openai_compat_api_key', e.target.value)} />
          </label>
          <label className="full-width">
            <span>OpenAI-compatible model</span>
            <input type="text" name="openai_compat_model" value={val('openai_compat_model')} onChange={(e) => handleChange('openai_compat_model', e.target.value)} />
          </label>
        </>
      )}
      {showMinimax && (
        <>
          <label className="full-width">
            <span>Minimax API key</span>
            <input type="password" name="minimax_api_key" value={val('minimax_api_key')} onChange={(e) => handleChange('minimax_api_key', e.target.value)} />
          </label>
          <label className="full-width">
            <span>Minimax model</span>
            <input type="text" name="minimax_model" placeholder="MiniMax-Text-01" value={val('minimax_model')} onChange={(e) => handleChange('minimax_model', e.target.value)} />
          </label>
        </>
      )}

      <label className="full-width">
        <span>EurekaClaw directory</span>
        <input type="text" name="eurekaclaw_dir" placeholder="~/.eurekaclaw" value={val('eurekaclaw_dir')} onChange={(e) => handleChange('eurekaclaw_dir', e.target.value)} />
      </label>

      <div className="action-row full-width">
        <button className="secondary-btn" type="button" id="test-connection-btn" onClick={() => void testConnection(false)}>
          Test connection
        </button>
        <button className="secondary-btn" type="button" id="save-and-test-btn" onClick={() => void testConnection(true)}>
          Save and test
        </button>
        <button className="primary-btn" type="submit">Save config</button>
        <p className="inline-note" id="config-save-status">{saveStatus}</p>
      </div>

      <AuthGuidance backend={backend} authMode={authMode} ccproxyPort={ccproxyPort} />
    </form>
  );
}
