import { useUiStore } from '@/store/uiStore';
import { SessionListShell } from '@/components/session/SessionList';

export function Sidebar() {
  const activeView = useUiStore((s) => s.activeView);
  const setActiveView = useUiStore((s) => s.setActiveView);

  return (
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
  );
}
