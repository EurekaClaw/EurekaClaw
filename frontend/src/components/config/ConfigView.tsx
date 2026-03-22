import { useEffect, useState } from 'react';
import { apiGet } from '@/api/client';
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
        </div>
      </div>

      {/* Main config form */}
      <ConfigForm onRefreshHealth={loadCapabilities} />
    </div>
  );
}
