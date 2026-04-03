import { useState } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { apiPost } from '@/api/client';
import type { SessionRun } from '@/types';

interface FailedSessionNoteProps {
  run: SessionRun;
}

export function FailedSessionNote({ run }: FailedSessionNoteProps) {
  const [showTheoryStages, setShowTheoryStages] = useState(false);
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

  const handleResume = async () => {
    try {
      await apiPost(`/api/runs/${run.run_id}/resume`, { feedback: '' });
    } catch (err) {
      alert(`Resume failed: ${(err as Error).message}`);
    }
  };

  const handleRestartFromIdeation = async () => {
    try {
      const resumedRun = await apiPost<SessionRun>(`/api/runs/${run.run_id}/restart-from-ideation`, {});
      setSessions([resumedRun, ...sessions.filter((s) => s.run_id !== resumedRun.run_id)]);
      setCurrentRunId(resumedRun.run_id);
      setCurrentLogPage(1);
    } catch (err) {
      alert(`Restart from ideation failed: ${(err as Error).message}`);
    }
  };

  const handleRestartFromTheory = async () => {
    try {
      const resumedRun = await apiPost<SessionRun>(`/api/runs/${run.run_id}/restart-from-theory`, {});
      setSessions([resumedRun, ...sessions.filter((s) => s.run_id !== resumedRun.run_id)]);
      setCurrentRunId(resumedRun.run_id);
      setCurrentLogPage(1);
    } catch (err) {
      alert(`Restart from theory failed: ${(err as Error).message}`);
    }
  };

  const handleRestartFromTheorySubstage = async (substage: string) => {
    try {
      const resumedRun = await apiPost<SessionRun>(`/api/runs/${run.run_id}/restart-from-theory-stage`, { substage });
      setSessions([resumedRun, ...sessions.filter((s) => s.run_id !== resumedRun.run_id)]);
      setCurrentRunId(resumedRun.run_id);
      setCurrentLogPage(1);
    } catch (err) {
      alert(`Restart from theory stage failed: ${(err as Error).message}`);
    }
  };

  const isRetryable = run.error_category === 'retryable';
  const hasCheckpoint = run.has_checkpoint === true;
  const surveyReady = Boolean(
    run.artifacts?.research_brief &&
    (
      (run.artifacts?.research_brief?.open_problems?.length ?? 0) > 0 ||
      (run.artifacts?.bibliography?.papers?.length ?? 0) > 0
    ),
  );
  const theoryReady = Boolean(
    run.artifacts?.research_brief && (
      Boolean(run.artifacts?.research_brief?.selected_direction) ||
      (run.artifacts?.research_brief?.directions?.length ?? 0) > 0 ||
      run.input_spec?.mode === 'detailed'
    ),
  );
  const hasTheoryState = Boolean(run.artifacts?.theory_state);
  const theorySubstages = [
    ['paper_reader', 'Paper Reader'],
    ['gap_analyst', 'Gap Analyst'],
    ['proof_architect', 'Proof Architect'],
    ['lemma_developer', 'Lemma Developer'],
    ['assembler', 'Assembler'],
    ['theorem_crystallizer', 'Theorem Crystallizer'],
    ['consistency_checker', 'Consistency Checker'],
  ] as const;
  const errMsg = run.error ? `Error: ${run.error}` : '';

  return (
    <div className="failed-session-note" id="failed-session-note">
      <div className="failed-session-note-header">
        <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
        <span className="failed-session-note-title">Session failed</span>
        {isRetryable && (
          <span className="failed-session-note-badge retryable">Transient error</span>
        )}
      </div>
      <p className="failed-session-note-body">
        {isRetryable && hasCheckpoint
          ? 'This session hit a temporary error (rate limit, server overload, or network issue). You can resume from the last checkpoint without losing progress.'
          : isRetryable
            ? 'This session hit a temporary error. Restart it with the same inputs to try again.'
            : 'This session encountered an error. Restart it with the same inputs, or start a new session.'}
      </p>
      {errMsg && <p className="failed-session-note-error" id="failed-session-error-text">{errMsg}</p>}
      <div className="failed-session-actions">
        {surveyReady && (
          <button className="failed-ideation-btn" id="restart-from-ideation-btn" onClick={() => void handleRestartFromIdeation()}>
            <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 5v14"/><path d="m19 12-7 7-7-7"/></svg>
            Restart from ideation
          </button>
        )}
        {theoryReady && (
          <>
            <button className="failed-ideation-btn" id="restart-from-theory-btn" onClick={() => void handleRestartFromTheory()}>
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 3v18"/><path d="M5 10h14"/></svg>
              Restart from theory
            </button>
            <button
              className="failed-ideation-btn"
              id="toggle-theory-stage-restart-btn"
              onClick={() => setShowTheoryStages((v) => !v)}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
              {showTheoryStages ? 'Hide theory stage restarts' : 'Restart from theory substage'}
            </button>
          </>
        )}
        {theoryReady && showTheoryStages && (
          <div className="failed-theory-stage-actions">
            {theorySubstages.map(([substage, label]) => (
              <button
                key={substage}
                className="failed-stage-btn"
                disabled={!hasTheoryState && substage !== 'paper_reader'}
                onClick={() => void handleRestartFromTheorySubstage(substage)}
                title={!hasTheoryState && substage !== 'paper_reader'
                  ? 'This run has no saved theory state yet; start from Paper Reader or full Theory.'
                  : ''}
              >
                {label}
              </button>
            ))}
          </div>
        )}
        {isRetryable && hasCheckpoint && (
          <button className="failed-resume-btn" id="resume-session-btn" onClick={() => void handleResume()}>
            <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="5 3 19 12 5 21 5 3"/></svg>
            Resume from checkpoint
          </button>
        )}
        <button className="failed-restart-btn" id="restart-session-btn" onClick={() => void handleRestart()}>
          <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/></svg>
          Restart with same inputs
        </button>
      </div>
    </div>
  );
}
