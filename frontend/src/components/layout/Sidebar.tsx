import { useUiStore } from '@/store/uiStore';
import { SessionListShell } from '@/components/session/SessionList';

export function Sidebar() {
  const activeView = useUiStore((s) => s.activeView);
  const setActiveView = useUiStore((s) => s.setActiveView);
  const setCurrentWizardStep = useUiStore((s) => s.setCurrentWizardStep);

  const handleTutorialBtn = () => {
    localStorage.removeItem('eurekaclaw_tutorial_skipped');
    setCurrentWizardStep(0);
    setActiveView('onboarding');
  };

  return (
    <>
      <aside className="sidebar">
        <div className="brand-block">
          <div className="brand-mark" aria-hidden="true">
            <img src="/logo-claw.png" alt="" className="brand-mark-image" />
          </div>
          <h1>EurekaClaw</h1>
        </div>

        <nav className="nav-stack" aria-label="Primary">
          <button
            className={`nav-item${activeView === 'workspace' ? ' is-active' : ''}`}
            data-view-target="workspace"
            onClick={() => setActiveView('workspace')}
          >
            Research
          </button>
          <button
            className={`nav-item${activeView === 'skills' ? ' is-active' : ''}`}
            data-view-target="skills"
            onClick={() => setActiveView('skills')}
          >
            Skills
          </button>
        </nav>

        <SessionListShell />

        <hr className="nav-divider sidebar-bottom-divider" />
        <button
          className={`nav-item nav-item--settings${activeView === 'systems' ? ' is-active' : ''}`}
          data-view-target="systems"
          onClick={() => setActiveView('systems')}
        >
          Settings
        </button>
      </aside>

      <button
        className="tutorial-btn"
        id="tutorial-btn"
        title="Setup guide &amp; tutorials"
        aria-label="Open setup guide"
        onClick={handleTutorialBtn}
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <circle cx="12" cy="12" r="10"/>
          <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
          <line x1="12" y1="17" x2="12.01" y2="17"/>
        </svg>
        <span>Guide</span>
      </button>
    </>
  );
}
