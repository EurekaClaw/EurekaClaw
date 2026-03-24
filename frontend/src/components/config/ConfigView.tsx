import { useEffect, useState } from 'react';
import { apiGet, apiPost } from '@/api/client';
import { statusClass } from '@/lib/statusHelpers';
import { titleCase } from '@/lib/formatters';
import { ConfigForm } from './ConfigForm';
import type { CapabilitiesMap } from '@/types';

interface CapabilitiesResponse {
  capabilities: CapabilitiesMap;
}

export function ConfigView() {
  const [capabilities, setCapabilities] = useState<CapabilitiesMap>({});
  const [capError, setCapError] = useState('');
  const [leanStatus, setLeanStatus] = useState('');
  const [leanStatusType, setLeanStatusType] = useState<'info' | 'ok' | 'error'>('info');
  const [installingLean, setInstallingLean] = useState(false);

  useEffect(() => {
    void loadCapabilities();
  }, []);

  const loadCapabilities = async () => {
    try {
      const data = await apiGet<CapabilitiesResponse>('/api/capabilities');
      setCapabilities(data.capabilities ?? {});
    } catch (err) {
      setCapError((err as Error).message);
    }
  };

  const capEntries = Object.entries(capabilities);
  const allOk = capEntries.length > 0 && capEntries.every(([, v]) => v.status === 'online' || v.status === 'active' || v.status === 'complete');
  const leanCapability = capabilities.lean4;

  const installLean4 = async () => {
    setInstallingLean(true);
    setLeanStatus('Installing Lean4 via elan…');
    setLeanStatusType('info');
    try {
      const result = await apiPost<{ ok: boolean; message: string }>('/api/lean4/install', {});
      setLeanStatus(result.message);
      setLeanStatusType(result.ok ? 'ok' : 'error');
      await loadCapabilities();
    } catch (err) {
      setLeanStatus((err as Error).message);
      setLeanStatusType('error');
    } finally {
      setInstallingLean(false);
    }
  };

  return (
    <div className="settings-page">
      {/* Health banner */}
      <div className={`settings-health-banner${allOk ? ' is-ok' : capError ? ' is-error' : ''}`}>
        <div className="settings-health-icon">
          {capError ? '⚠' : allOk ? '✓' : '…'}
        </div>
        <div className="settings-health-body">
          <p className="settings-health-title">
            {capError ? 'System status unavailable' : allOk ? 'All systems operational' : 'Checking system status…'}
          </p>
          <div className="settings-health-pills">
            {capError ? (
              <span className={`status-pill ${statusClass('missing')}`}>{capError}</span>
            ) : (
              capEntries.map(([key, value]) => (
                <span key={key} className={`status-pill ${statusClass(value.status)}`}>
                  {titleCase(key)}: {value.detail}
                </span>
              ))
            )}
          </div>
          {leanCapability && leanCapability.status !== 'available' && !capError && (
            <div className="settings-health-cta">
              <p className="settings-health-cta-copy">
                Lean4 is not installed yet. Install it locally to enable formal verification.
              </p>
              <button
                className="settings-tool-btn"
                type="button"
                disabled={installingLean}
                onClick={() => void installLean4()}
              >
                {installingLean ? 'Installing Lean4…' : 'Install Lean4'}
              </button>
            </div>
          )}
          {leanStatus && (
            <p className={`settings-status-msg settings-status-msg--${leanStatusType}`}>{leanStatus}</p>
          )}
        </div>
      </div>

      {/* Main config form */}
      <ConfigForm onRefreshHealth={loadCapabilities} />
    </div>
  );
}
