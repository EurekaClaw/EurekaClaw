import { useUiStore } from '@/store/uiStore';
import { LivePanel } from './LivePanel';
import { ProofPanel } from './ProofPanel';
import { PaperPanel } from './PaperPanel';
import { LogsPanel } from './LogsPanel';
import type { SessionRun } from '@/types';

interface WorkspaceTabsProps {
  run: SessionRun | null;
}

const TABS = [
  { key: 'live', label: 'Live' },
  { key: 'proof', label: 'Proof' },
  { key: 'paper', label: 'Paper' },
  { key: 'logs', label: 'Logs' },
] as const;

type TabKey = typeof TABS[number]['key'];

export function WorkspaceTabs({ run }: WorkspaceTabsProps) {
  const activeWsTab = useUiStore((s) => s.activeWsTab);
  const setActiveWsTab = useUiStore((s) => s.setActiveWsTab);

  return (
    <div className="workspace-main-col">
      <div className="ws-tab-bar" role="tablist" aria-label="Workspace views">
        {TABS.map((tab) => (
          <button
            key={tab.key}
            className={`ws-tab${activeWsTab === tab.key ? ' is-active' : ''}`}
            data-ws-tab={tab.key}
            role="tab"
            aria-selected={activeWsTab === tab.key}
            aria-controls={`ws-panel-${tab.key}`}
            onClick={() => setActiveWsTab(tab.key as TabKey)}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className={`ws-panel${activeWsTab === 'live' ? ' is-visible' : ''}`} id="ws-panel-live" role="tabpanel">
        <LivePanel run={run} />
      </div>
      <div className={`ws-panel${activeWsTab === 'proof' ? ' is-visible' : ''}`} id="ws-panel-proof" role="tabpanel">
        <ProofPanel run={run} />
      </div>
      <div className={`ws-panel${activeWsTab === 'paper' ? ' is-visible' : ''}`} id="ws-panel-paper" role="tabpanel">
        <PaperPanel run={run} />
      </div>
      <div className={`ws-panel${activeWsTab === 'logs' ? ' is-visible' : ''}`} id="ws-panel-logs" role="tabpanel">
        <LogsPanel run={run} />
      </div>
    </div>
  );
}
