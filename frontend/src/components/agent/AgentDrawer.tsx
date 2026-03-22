import { useEffect } from 'react';
import { useUiStore } from '@/store/uiStore';
import { useSessionStore } from '@/store/sessionStore';
import { AGENT_MANIFEST } from '@/lib/agentManifest';
import { statusClass, } from '@/lib/statusHelpers';
import { titleCase } from '@/lib/formatters';
import { SurveyDrawerBody } from './SurveyDrawerBody';
import { IdeationDrawerBody } from './IdeationDrawerBody';
import { TheoryDrawerBody } from './TheoryDrawerBody';
import { ExperimentDrawerBody } from './ExperimentDrawerBody';
import { WriterDrawerBody } from './WriterDrawerBody';

export function AgentDrawer() {
  const openAgentDrawerRole = useUiStore((s) => s.openAgentDrawerRole);
  const setOpenAgentDrawerRole = useUiStore((s) => s.setOpenAgentDrawerRole);
  const currentRun = useSessionStore((s) => s.currentRun());

  const isOpen = openAgentDrawerRole !== null;

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpenAgentDrawerRole(null);
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [setOpenAgentDrawerRole]);

  if (!isOpen || !openAgentDrawerRole) return null;

  const manifest = AGENT_MANIFEST.find((a) => a.role === openAgentDrawerRole);
  if (!manifest) return null;

  const pipeline = currentRun?.pipeline ?? [];
  const taskMap = new Map(pipeline.map((t) => [t.agent_role, t]));
  const task = taskMap.get(openAgentDrawerRole);
  const st = task?.status ?? 'pending';
  const arts = currentRun?.artifacts ?? {};

  const renderBody = () => {
    if (openAgentDrawerRole === 'survey') return <SurveyDrawerBody arts={arts} />;
    if (openAgentDrawerRole === 'ideation') return <IdeationDrawerBody arts={arts} run={currentRun} />;
    if (openAgentDrawerRole === 'theory') return <TheoryDrawerBody arts={arts} />;
    if (openAgentDrawerRole === 'experiment') return <ExperimentDrawerBody arts={arts} />;
    if (openAgentDrawerRole === 'writer') return <WriterDrawerBody run={currentRun} />;
    return <p className="drawer-empty">No detail available for this agent.</p>;
  };

  return (
    <>
      <div
        className="agent-drawer-backdrop"
        id="agent-drawer-backdrop"
        onClick={() => setOpenAgentDrawerRole(null)}
      />
      <aside className="agent-drawer is-open" id="agent-drawer" aria-hidden="false">
        <div className="agent-drawer-header">
          <div className="agent-drawer-title-group">
            <span className="agent-drawer-icon" id="agent-drawer-icon" aria-hidden="true">{manifest.icon}</span>
            <div>
              <h3 className="agent-drawer-title" id="agent-drawer-title">{manifest.name}</h3>
              <span className={`agent-drawer-status status-pill ${statusClass(st)}`} id="agent-drawer-status">
                {titleCase(st)}
              </span>
            </div>
          </div>
          <button
            className="ghost-btn agent-drawer-close"
            id="close-agent-drawer-btn"
            aria-label="Close agent detail"
            onClick={() => setOpenAgentDrawerRole(null)}
          >
            Close ×
          </button>
        </div>
        <div className="agent-drawer-body" id="agent-drawer-body">
          {renderBody()}
        </div>
      </aside>
    </>
  );
}
