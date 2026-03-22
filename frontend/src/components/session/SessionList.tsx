import { useState } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { useUiStore } from '@/store/uiStore';
import { formatRelativeTime, escapeHtml } from '@/lib/formatters';
import { titleCase } from '@/lib/formatters';
import { apiPost, apiDelete } from '@/api/client';
import type { SessionRun } from '@/types';

export function SessionList() {
  const sessions = useSessionStore((s) => s.sessions);
  const currentRunId = useSessionStore((s) => s.currentRunId);
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);
  const setSessions = useSessionStore((s) => s.setSessions);
  const setCurrentLogPage = useSessionStore((s) => s.setCurrentLogPage);
  const setActiveView = useUiStore((s) => s.setActiveView);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState('');

  const selectSession = (runId: string) => {
    if (runId === currentRunId) return;
    setCurrentRunId(runId);
    setCurrentLogPage(1);
    setActiveView('workspace');
  };

  const startRename = (e: React.MouseEvent, run: SessionRun) => {
    e.stopPropagation();
    setRenamingId(run.run_id);
    setRenameValue(run.name || run.input_spec?.query || run.input_spec?.domain || 'Untitled session');
  };

  const commitRename = async (runId: string) => {
    const val = renameValue.trim();
    setRenamingId(null);
    if (!val) return;
    try {
      await apiPost(`/api/runs/${runId}/rename`, { name: val });
      setSessions(
        sessions.map((s) => (s.run_id === runId ? { ...s, name: val } : s))
      );
    } catch {
      // silently ignore
    }
  };

  const handleRestart = async (e: React.MouseEvent, runId: string) => {
    e.stopPropagation();
    try {
      const newRun = await apiPost<SessionRun>(`/api/runs/${runId}/restart`, {});
      setSessions([newRun, ...sessions.filter((s) => s.run_id !== newRun.run_id)]);
      setCurrentRunId(newRun.run_id);
      setCurrentLogPage(1);
      setActiveView('workspace');
    } catch {
      // silently ignore
    }
  };

  const handleDelete = async (e: React.MouseEvent, runId: string) => {
    e.stopPropagation();
    if (!confirm('Delete this session? This cannot be undone.')) return;
    try {
      await apiDelete(`/api/runs/${runId}`);
      const updated = sessions.filter((s) => s.run_id !== runId);
      setSessions(updated);
      if (currentRunId === runId) {
        setCurrentRunId(null);
        setCurrentLogPage(1);
      }
    } catch (err) {
      alert(`Could not delete session: ${(err as Error).message}`);
    }
  };

  if (!sessions.length) {
    return (
      <div className="session-list">
        <p className="session-list-empty">No sessions yet.<br />Launch one to get started.</p>
      </div>
    );
  }

  return (
    <div className="session-list">
      {sessions.map((s) => {
        const rawName = s.name || s.input_spec?.query || s.input_spec?.domain || 'Untitled session';
        const displayName = rawName.length > 52 ? rawName.slice(0, 49) + '…' : rawName;
        const status = s.status || 'queued';
        const time = formatRelativeTime(s.created_at);
        const isActive = s.run_id === currentRunId;
        const isFailed = status === 'failed';
        const isPaused = status === 'paused';
        const isPausing = status === 'pausing';
        const isResuming = status === 'resuming';
        const isRunning = status === 'running' || status === 'queued';
        const isLive = isRunning || isPausing || isResuming;
        const canDelete = !isLive;
        const statusLabel = titleCase(status);
        const extraClass = isActive ? ' is-active' : isFailed ? ' is-failed' : '';

        return (
          <div
            key={s.run_id}
            className={`session-item${extraClass}`}
            data-run-id={s.run_id}
            onClick={() => selectSession(s.run_id)}
          >
            <div className="session-item-main">
              {renamingId === s.run_id ? (
                <input
                  className="session-rename-input"
                  value={renameValue}
                  maxLength={80}
                  autoFocus
                  onChange={(e) => setRenameValue(e.target.value)}
                  onBlur={() => void commitRename(s.run_id)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') e.currentTarget.blur();
                    if (e.key === 'Escape') setRenamingId(null);
                  }}
                  onClick={(e) => e.stopPropagation()}
                />
              ) : (
                <div className="session-item-name">{escapeHtml(displayName)}</div>
              )}
              <div className="session-item-meta">
                <span className={`session-status-dot ${status}`} aria-label={statusLabel} />
                <span>{time}</span>
                {isFailed && <span className="session-item-failed-tag">failed</span>}
                {isPaused && <span className="session-item-failed-tag session-item-paused-tag">paused</span>}
                {isPausing && <span className="session-item-failed-tag session-item-pausing-tag">pausing…</span>}
                {isResuming && <span className="session-item-failed-tag session-item-resuming-tag">resuming…</span>}
              </div>
            </div>
            <div className="session-item-actions">
              {isFailed && (
                <button
                  className="session-action-btn session-restart-sidebar-btn"
                  title="Restart session"
                  aria-label="Restart session"
                  onClick={(e) => void handleRestart(e, s.run_id)}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/></svg>
                </button>
              )}
              <button
                className="session-action-btn session-rename-sidebar-btn"
                title="Rename"
                aria-label="Rename session"
                onClick={(e) => startRename(e, s)}
              >
                <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
              </button>
              {canDelete && (
                <button
                  className="session-action-btn session-delete-btn"
                  title="Delete session"
                  aria-label="Delete session"
                  onClick={(e) => void handleDelete(e, s.run_id)}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
                </button>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export function SessionListShell() {
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);
  const setCurrentLogPage = useSessionStore((s) => s.setCurrentLogPage);
  const setActiveView = useUiStore((s) => s.setActiveView);

  const handleNewSession = () => {
    setCurrentRunId(null);
    setCurrentLogPage(1);
    setActiveView('workspace');
  };

  return (
    <section className="session-list-shell">
      <div className="session-list-header">
        <div className="session-list-title-group">
          <p className="sidebar-title">Sessions</p>
        </div>
        <button className="ghost-btn" onClick={handleNewSession}>+ New</button>
      </div>
      <SessionList />
    </section>
  );
}
