import { useState, useEffect } from 'react';
import { apiGet, apiPost } from '@/api/client';
import type { AppConfig } from '@/types';
import type { OAuthStatusResponse } from './configTypes';
import { LLMSection } from './LLMSection';
import { PipelineSection } from './PipelineSection';
import { OutputSection } from './OutputSection';
import { AdvancedSection } from './AdvancedSection';

interface ConfigResponse {
  config: AppConfig;
}

interface TestResponse {
  ok: boolean;
  message?: string;
  reply_preview?: string;
}

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
  const [codexStatus, setCodexStatus] = useState<OAuthStatusResponse | null>(null);
  const [codexImporting, setCodexImporting] = useState(false);
  const [openaiPkgStatus, setOpenaiPkgStatus] = useState<{ installed: boolean } | null>(null);
  const [installingOpenai, setInstallingOpenai] = useState(false);

  const rawBackend = (config.llm_backend as string) || 'anthropic';
  const backend = rawBackend === 'oauth' ? 'anthropic' : rawBackend;
  const authMode = rawBackend === 'oauth' ? 'oauth' : ((config.anthropic_auth_mode as string) || 'api_key');
  const codexAuthMode = (config.codex_auth_mode as string) || 'api_key';
  const showOauth = backend === 'anthropic' && authMode === 'oauth';
  const showCodex = backend === 'codex';
  const showCodexOauth = showCodex && codexAuthMode === 'oauth';

  useEffect(() => { void loadConfig(); }, []);
  useEffect(() => { if (showOauth) void checkOauthStatus(); }, [showOauth]);
  useEffect(() => { if (showCodexOauth) void checkCodexStatus(); }, [showCodexOauth]);
  useEffect(() => { if (showCodex) void checkOpenaiPkg(); }, [showCodex]);

  const setStatus = (msg: string, type: 'info' | 'ok' | 'error' = 'info') => {
    setSaveStatus(msg);
    setStatusType(type);
  };

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
      setOauthStatus(await apiGet<OAuthStatusResponse>('/api/oauth/status'));
    } catch {
      setOauthStatus(null);
    }
  };

  const checkCodexStatus = async () => {
    try {
      setCodexStatus(await apiGet<OAuthStatusResponse>('/api/codex/status'));
    } catch {
      setCodexStatus(null);
    }
  };

  const checkOpenaiPkg = async () => {
    try {
      setOpenaiPkgStatus(await apiGet<{ installed: boolean }>('/api/codex/package-status'));
    } catch {
      setOpenaiPkgStatus(null);
    }
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
    setStatus('Installing OAuth dependencies…', 'info');
    try {
      const result = await apiPost<{ ok: boolean; message: string }>('/api/oauth/install', {});
      if (result.ok) { setStatus('OAuth dependencies installed.', 'ok'); await checkOauthStatus(); }
      else setStatus(`Install failed: ${result.message}`, 'error');
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
        setStatus('OAuth login initiated. Complete authorization in your browser.', 'ok');
        setTimeout(() => void checkOauthStatus(), 3000);
      } else setStatus(`Login failed: ${result.message}`, 'error');
    } catch (err) {
      setStatus(`Login error: ${(err as Error).message}`, 'error');
    } finally {
      setLoggingIn(false);
    }
  };

  const importCodexCredentials = async () => {
    setCodexImporting(true);
    setStatus('Importing Codex CLI credentials…', 'info');
    try {
      const result = await apiPost<{ ok: boolean; message: string }>('/api/codex/login', {});
      if (result.ok) { setStatus('Codex credentials imported.', 'ok'); await checkCodexStatus(); }
      else setStatus(`Import failed: ${result.message}`, 'error');
    } catch (err) {
      setStatus(`Import error: ${(err as Error).message}`, 'error');
    } finally {
      setCodexImporting(false);
    }
  };

  const installOpenai = async () => {
    setInstallingOpenai(true);
    setStatus('Installing OpenAI package…', 'info');
    try {
      const result = await apiPost<{ ok: boolean; message: string }>('/api/codex/install', {});
      if (result.ok) {
        setStatus('OpenAI package installed.', 'ok');
        setOpenaiPkgStatus({ installed: true });
        onRefreshHealth?.();
      } else setStatus(`Install failed: ${result.message}`, 'error');
    } catch (err) {
      setStatus(`Install error: ${(err as Error).message}`, 'error');
    } finally {
      setInstallingOpenai(false);
    }
  };

  const testConnection = async (saveAfter: boolean) => {
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
        if (msg.includes('ccproxy') && msg.includes('not found')) {
          setStatus('ccproxy not found. Click "Install OAuth" to set it up.', 'error');
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
      const preview = result.reply_preview || 'OK';
      setStatus(saveAfter ? `Connected and saved. Preview: ${preview}` : `Connection verified. Preview: ${preview}`, 'ok');
    } catch (err) {
      setStatus(`Connection error: ${(err as Error).message}`, 'error');
    }
  };

  const val = (key: string) => String(config[key] ?? '');
  const checked = (key: string) => config[key] === true || config[key] === 'true';
  const sectionProps = { config, val, checked, handleChange };

  return (
    <form className="settings-form" id="config-form" onSubmit={(e) => void handleSubmit(e)}>
      <LLMSection
        {...sectionProps}
        oauthStatus={oauthStatus}
        codexStatus={codexStatus}
        openaiPkgStatus={openaiPkgStatus}
        onInstallOauth={() => void installOauth()}
        onLoginOauth={() => void loginOauth()}
        onImportCodex={() => void importCodexCredentials()}
        onInstallOpenai={() => void installOpenai()}
        onTestConnection={(save) => void testConnection(save)}
        installing={installing}
        loggingIn={loggingIn}
        codexImporting={codexImporting}
        installingOpenai={installingOpenai}
        saveStatus={saveStatus}
        statusType={statusType}
      />
      <PipelineSection {...sectionProps} />
      <OutputSection {...sectionProps} />
      <AdvancedSection {...sectionProps} />

      <div className="settings-bottom-bar">
        <div className="settings-bottom-actions">
          <button className="primary-btn" type="submit">Save all settings</button>
        </div>
      </div>
    </form>
  );
}
