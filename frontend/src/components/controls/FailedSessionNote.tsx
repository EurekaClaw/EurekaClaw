import { useSessionStore } from '@/store/sessionStore';
import { apiPost } from '@/api/client';
import type { SessionRun } from '@/types';

interface FailedSessionNoteProps {
  run: SessionRun;
}

export function FailedSessionNote({ run }: FailedSessionNoteProps) {
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);
  const setCurrentLogPage = useSessionStore((s) => s.setCurrentLogPage);

  const handleRestart = async () => {
    try {
      const newRun = await apiPost<SessionRun>(`/api/runs/${run.run_id}/restart`, {});
      setSessions([newRun, ...sessions.filter((s) => s.run_id !== newRun.run_id)]);
      setCurrentRunId(newRun.run_id);
      setCurrentLogPage(1);
    } catch (err) {
      alert(`Restart failed: ${(err as Error).message}`);
    }
  };

  const errMsg = run.error ? `Error: ${run.error}` : '';

  return (
    <div className="failed-session-note" id="failed-session-note">
      <div className="failed-session-note-header">
        <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
        <span className="failed-session-note-title">Session failed</span>
      </div>
      <p className="failed-session-note-body">This session encountered an error. Restart it with the same inputs, or start a new session.</p>
      {errMsg && <p className="failed-session-note-error" id="failed-session-error-text">{errMsg}</p>}
      <div className="failed-session-actions">
        <button className="failed-restart-btn" id="restart-session-btn" onClick={() => void handleRestart()}>
          <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/></svg>
          Restart with same inputs
        </button>
      </div>
    </div>
  );
}
