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
  const currentRun = useSessionStore((s) => s.currentRun());
  const setAvailableSkills = useSkillStore((s) => s.setAvailableSkills);

  const { restartFast } = usePolling();

  // Check tutorial skip on mount
  useEffect(() => {
    if (localStorage.getItem('eurekaclaw_tutorial_skipped') === '1') {
      setActiveView('workspace');
    } else {
      setActiveView('onboarding');
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
      </main>

      <AgentDrawer />
      <FlashOverlay />
    </div>
  );
}
