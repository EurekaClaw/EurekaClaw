import { useEffect } from 'react';
import { useUiStore } from '@/store/uiStore';
import { useSkillStore } from '@/store/skillStore';
import { usePolling } from '@/hooks/usePolling';
import { apiGet } from '@/api/client';
import { Sidebar } from '@/components/layout/Sidebar';
import { FlashOverlay } from '@/components/layout/FlashOverlay';
import { NewSessionForm } from '@/components/session/NewSessionForm';
import { SessionDetailPane } from '@/components/session/SessionDetailPane';
import { SkillsView } from '@/components/skills/SkillsView';
import { ConfigView } from '@/components/config/ConfigView';
import { OnboardingView } from '@/components/onboarding/OnboardingView';
import { AgentDrawer } from '@/components/agent/AgentDrawer';
import { useSessionStore } from '@/store/sessionStore';
import type { Skill } from '@/types';

interface SkillsResponse {
  skills: Skill[];
}

export function App() {
  const activeView = useUiStore((s) => s.activeView);
  const setActiveView = useUiStore((s) => s.setActiveView);
  const setCurrentWizardStep = useUiStore((s) => s.setCurrentWizardStep);
  const currentRun = useSessionStore((s) => s.currentRun());
  const setAvailableSkills = useSkillStore((s) => s.setAvailableSkills);

  const { restartFast } = usePolling();

  // On first visit (no persisted view), show onboarding unless tutorial was skipped
  useEffect(() => {
    const hasPersistedView = localStorage.getItem('eurekaclaw_ui');
    if (!hasPersistedView) {
      if (localStorage.getItem('eurekaclaw_tutorial_skipped') === '1') {
        setActiveView('workspace');
      } else {
        setActiveView('onboarding');
      }
    }
  }, [setActiveView]);

  // Load skills on mount
  useEffect(() => {
    void (async () => {
      try {
        const data = await apiGet<SkillsResponse>('/api/skills');
        setAvailableSkills(data.skills ?? []);
      } catch {
        // silently ignore
      }
    })();
  }, [setAvailableSkills]);

  const isWorkspaceView = activeView === 'workspace';

  const handleGuideClick = () => {
    localStorage.removeItem('eurekaclaw_tutorial_skipped');
    setCurrentWizardStep(0);
    setActiveView('onboarding');
  };

  return (
    <div className="app-shell">
      <Sidebar />

      <main className="main-shell">
        <section
          className={`view${activeView === 'workspace' ? ' is-visible' : ''}`}
          data-view="workspace"
        >
          {isWorkspaceView && (
            currentRun
              ? <SessionDetailPane run={currentRun} onRestartFast={restartFast} />
              : <NewSessionForm />
          )}
        </section>

        <section
          className={`view${activeView === 'skills' ? ' is-visible' : ''}`}
          data-view="skills"
        >
          {activeView === 'skills' && <SkillsView />}
        </section>

        <section
          className={`view${activeView === 'onboarding' ? ' is-visible' : ''}`}
          data-view="onboarding"
        >
          {activeView === 'onboarding' && <OnboardingView />}
        </section>

        <section
          className={`view${activeView === 'systems' ? ' is-visible' : ''}`}
          data-view="systems"
        >
          {activeView === 'systems' && <ConfigView />}
        </section>
        <button
          className="tutorial-btn"
          title="Setup guide &amp; tutorials"
          aria-label="Open setup guide"
          onClick={handleGuideClick}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/>
            <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
            <line x1="12" y1="17" x2="12.01" y2="17"/>
          </svg>
          <span>Guide</span>
        </button>
      </main>

      <AgentDrawer />
      <FlashOverlay />
    </div>
  );
}
