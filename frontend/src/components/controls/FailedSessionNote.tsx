import { useState } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { apiPost } from '@/api/client';
import type { SessionRun } from '@/types';

interface FailedSessionNoteProps {
  run: SessionRun;
}

export function FailedSessionNote({ run }: FailedSessionNoteProps) {
  const [showMoreOptions, setShowMoreOptions] = useState(false);
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
  const canResume = isRetryable && hasCheckpoint;
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
  const hasMoreOptions = surveyReady || theoryReady;

  const theorySubstages = [
    ['paper_reader', 'Paper Reader'],
    ['gap_analyst', 'Gap Analyst'],
    ['proof_architect', 'Proof Architect'],
    ['lemma_developer', 'Lemma Developer'],
    ['assembler', 'Assembler'],
    ['theorem_crystallizer', 'Theorem Crystallizer'],
    ['consistency_checker', 'Consistency Checker'],
  ] as const;

  const headline = canResume
    ? 'Session paused by a temporary error'
    : isRetryable
      ? 'Session stopped — transient error'
      : 'Session failed';

  const subhead = canResume
    ? "Your progress is saved. Resume to pick up where it stopped."
    : isRetryable
      ? 'Restart with the same inputs and it should complete.'
      : 'Restart, or jump back to a specific stage below.';

  const cardClass = `failed-session-note${isRetryable ? ' is-retryable' : ' is-fatal'}`;

  return (
    <div className={cardClass} id="failed-session-note">
      <div className="failed-session-note-header">
        <span className="failed-session-note-icon" aria-hidden="true">
          <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
            <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"/>
            <line x1="12" y1="9" x2="12" y2="13"/>
            <line x1="12" y1="17" x2="12.01" y2="17"/>
          </svg>
        </span>
        <div className="failed-session-note-heading">
          <span className="failed-session-note-title">{headline}</span>
          <span className="failed-session-note-subtitle">{subhead}</span>
        </div>
        {isRetryable && (
          <span className="failed-session-note-badge retryable" aria-label="Transient error">Transient</span>
        )}
      </div>

      {run.error && (
        <details className="failed-session-note-error-details" id="failed-session-error-details">
          <summary className="failed-session-note-error-summary">
            <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
            <span>View error details</span>
          </summary>
          <pre className="failed-session-note-error-text" id="failed-session-error-text">{run.error}</pre>
        </details>
      )}

      <div className="failed-session-actions">
        <div className="failed-session-actions-primary">
          {canResume && (
            <button
              className="failed-action-btn failed-action-btn--primary"
              id="resume-session-btn"
              onClick={() => void handleResume()}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><polygon points="5 3 19 12 5 21 5 3"/></svg>
              <span>Resume from checkpoint</span>
            </button>
          )}
          <button
            className={`failed-action-btn ${canResume ? 'failed-action-btn--ghost' : 'failed-action-btn--primary'}`}
            id="restart-session-btn"
            onClick={() => void handleRestart()}
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/></svg>
            <span>Restart with same inputs</span>
          </button>
        </div>

        {hasMoreOptions && (
          <div className="failed-session-advanced">
            <button
              className={`failed-advanced-toggle${showMoreOptions ? ' is-open' : ''}`}
              id="toggle-more-restart-options-btn"
              aria-expanded={showMoreOptions}
              onClick={() => setShowMoreOptions((v) => !v)}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
              <span>{showMoreOptions ? 'Hide more options' : 'Restart from an earlier stage'}</span>
            </button>

            {showMoreOptions && (
              <div className="failed-advanced-options">
                {surveyReady && (
                  <button
                    className="failed-stage-option"
                    id="restart-from-ideation-btn"
                    onClick={() => void handleRestartFromIdeation()}
                  >
                    <span className="failed-stage-option-label">From ideation</span>
                    <span className="failed-stage-option-sub">Keep papers, regenerate ideas</span>
                  </button>
                )}
                {theoryReady && (
                  <button
                    className="failed-stage-option"
                    id="restart-from-theory-btn"
                    onClick={() => void handleRestartFromTheory()}
                  >
                    <span className="failed-stage-option-label">From theory</span>
                    <span className="failed-stage-option-sub">Keep ideas, restart proving</span>
                  </button>
                )}
                {theoryReady && (
                  <button
                    className={`failed-stage-option failed-stage-option--expander${showTheoryStages ? ' is-open' : ''}`}
                    id="toggle-theory-stage-restart-btn"
                    aria-expanded={showTheoryStages}
                    onClick={() => setShowTheoryStages((v) => !v)}
                  >
                    <span className="failed-stage-option-label">
                      <span>From a theory substage</span>
                      <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </span>
                    <span className="failed-stage-option-sub">
                      {showTheoryStages ? 'Hide substages' : 'Choose the exact checkpoint'}
                    </span>
                  </button>
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
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
