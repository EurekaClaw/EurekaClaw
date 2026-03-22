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

  return (
    <div className="systems-grid">
      <article className="panel">
        <div className="panel-header">
          <div>
            <p className="eyebrow">Health</p>
            <h3>System status</h3>
          </div>
        </div>
        <div className="capability-list" id="capability-list">
          {capError ? (
            <div className="capability-row">
              <span>Capabilities unavailable</span>
              <span className={`status-pill ${statusClass('missing')}`}>{capError}</span>
            </div>
          ) : (
            Object.entries(capabilities).map(([key, value]) => (
              <div key={key} className="capability-row">
                <span>{titleCase(key)}</span>
                <span className={`status-pill ${statusClass(value.status)}`}>{value.detail}</span>
              </div>
            ))
          )}
        </div>
      </article>

      <article className="panel config-panel">
        <div className="panel-header">
          <div>
            <p className="eyebrow">Configuration</p>
            <h3>Settings</h3>
          </div>
        </div>
        <ConfigForm />
      </article>
    </div>
  );
}
