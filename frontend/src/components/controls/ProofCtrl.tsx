import { useRef } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { useUiStore } from '@/store/uiStore';
import { useElapsedTimer } from '@/hooks/useElapsedTimer';
import { apiPost } from '@/api/client';
import { getActiveOuterStage, friendlyInnerStage } from '@/lib/statusHelpers';
import { humanize } from '@/lib/formatters';
import { StageTrack } from './StageTrack';
import { TheoryFeedback } from './TheoryFeedback';
import type { SessionRun } from '@/types';

interface ProofCtrlProps {
  run: SessionRun;
  onRestartFast: () => void;
}

const RUNNING_LABELS: Record<string, string> = {
  survey:     'Reading papers',
  ideation:   'Generating ideas',
  theory:     'Proving the theorem',
  experiment: 'Running experiments',
  writer:     'Writing the paper',
};

export function ProofCtrl({ run, onRestartFast }: ProofCtrlProps) {
  const isPausingRequested = useSessionStore((s) => s.isPausingRequested);
  const setIsPausingRequested = useSessionStore((s) => s.setIsPausingRequested);
  const pauseRequestedAt = useSessionStore((s) => s.pauseRequestedAt);
  const setPauseRequestedAt = useSessionStore((s) => s.setPauseRequestedAt);
  const setActiveWsTab = useUiStore((s) => s.setActiveWsTab);
  const feedbackRef = useRef('');

  const status = run.status;
  const isRunning = status === 'running';
  const isPausing = status === 'pausing' || (status === 'running' && isPausingRequested);
  const isPaused = status === 'paused';
  const isResuming = status === 'resuming';

  const elapsed = useElapsedTimer(isPausing ? (pauseRequestedAt ?? null) : null);
  const elapsedText = elapsed < 2 ? '' : `${elapsed}s`;

  const pipeline = run.pipeline ?? [];
  const activeOuter = getActiveOuterStage(pipeline);
  const runningLabel = RUNNING_LABELS[activeOuter ?? ''] ?? 'Research in progress';
  const pauseDisabled = activeOuter === 'experiment' || activeOuter === 'writer';

  const handlePause = async () => {
    setIsPausingRequested(true);
    setPauseRequestedAt(new Date());
    onRestartFast();
    try {
      await apiPost(`/api/runs/${run.run_id}/pause`, {});
    } catch (err) {
      setIsPausingRequested(false);
      setPauseRequestedAt(null);
      alert(`Pause failed: ${(err as Error).message}`);
    }
  };

  const handleResume = async () => {
    const feedback = feedbackRef.current.trim();
    feedbackRef.current = '';
    setActiveWsTab('live');
    onRestartFast();
    try {
      await apiPost(`/api/runs/${run.run_id}/resume`, { feedback });
    } catch (err) {
      alert(`Resume failed: ${(err as Error).message}`);
    }
  };

  const handleCopyCmd = () => {
    if (!run.session_id) return;
    const cmd = `eurekaclaw resume ${run.session_id}`;
    navigator.clipboard.writeText(cmd).catch(() => {
      // fallback: select the element
    });
  };

  const pausedStageText = run.paused_stage
    ? `Paused while ${friendlyInnerStage(run.paused_stage) ?? humanize(run.paused_stage)}`
    : 'Ready to continue whenever you are';

  const hintText = pauseDisabled
    ? 'pause unavailable at this stage'
    : activeOuter === 'theory'
    ? 'progress saves at the next checkpoint'
    : 'pause takes effect once theorem-proving begins';

  return (
    <div className="proof-ctrl" id="proof-ctrl">
      {/* Top band: pipeline icons + pause pill inline, one breath */}
      <div className="proof-ctrl-top">
        <StageTrack run={run} />
        {isRunning && !isPausing && (
          <button
            className="proof-ctrl-pause-btn"
            id="pause-session-btn"
            aria-label="Pause research at the next safe checkpoint"
            title={hintText}
            disabled={pauseDisabled}
            onClick={() => void handlePause()}
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="4" width="4" height="16" rx="1.5"/><rect x="14" y="4" width="4" height="16" rx="1.5"/></svg>
            <span>Take a break</span>
          </button>
        )}
      </div>

      {/* Running footer: single inline status line, no separate card */}
      {isRunning && !isPausing && (
        <div className="proof-ctrl-running-footer" id="proof-ctrl-running">
          <span className="proof-ctrl-live-dot" aria-hidden="true" />
          <span className="proof-ctrl-live-label" id="proof-ctrl-live-label">{runningLabel}</span>
          <span className="proof-ctrl-live-sep" aria-hidden="true">·</span>
          <span className="proof-ctrl-live-hint" id="proof-ctrl-running-hint">{hintText}</span>
        </div>
      )}

      {/* State 2: Pausing */}
      {isPausing && (
        <div className="proof-ctrl-state" id="proof-ctrl-pausing">
          <div className="proof-ctrl-transition-bar proof-ctrl-transition-bar--pausing">
            <span className="pct-spinner pct-spinner--amber" aria-hidden="true" />
            <div className="proof-ctrl-status-text">
              <span className="proof-ctrl-status-label">Stopping…</span>
              <span className="proof-ctrl-transition-sub">Saving progress and halting the session</span>
            </div>
            <span className="proof-ctrl-elapsed" id="pause-elapsed" aria-live="polite">{elapsedText}</span>
          </div>
        </div>
      )}

      {/* State 3: Paused */}
      {isPaused && (
        <div className="proof-ctrl-state" id="proof-ctrl-paused">
          <div className="proof-ctrl-paused-card">
            <div className="proof-ctrl-paused-header">
              <span className="proof-ctrl-paused-icon" aria-hidden="true">☕</span>
              <div>
                <span className="proof-ctrl-paused-title">Research paused — progress saved</span>
                <span className="proof-ctrl-paused-subtitle" id="proof-ctrl-paused-stage">{pausedStageText}</span>
              </div>
            </div>
            <TheoryFeedback theoryState={run.artifacts?.theory_state} feedbackRef={feedbackRef} />
            <div className="proof-ctrl-paused-actions">
              <button className="proof-ctrl-resume-btn" id="resume-session-btn" aria-label="Continue research from saved checkpoint" onClick={() => void handleResume()}>
                <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                <span>Continue research</span>
              </button>
              <button className="proof-ctrl-copy-btn" id="copy-resume-cmd-btn" title="Copy terminal resume command" aria-label="Copy resume command" onClick={handleCopyCmd}>
                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                <span id="copy-resume-cmd-label">Copy terminal command</span>
              </button>
            </div>
            {run.session_id && (
              <code className="proof-ctrl-session-id" id="proof-ctrl-session-id" title={`eurekaclaw resume ${run.session_id}`}>
                {run.session_id.slice(0, 16)}…
              </code>
            )}
          </div>
        </div>
      )}

      {/* State 4: Resuming */}
      {isResuming && (
        <div className="proof-ctrl-state" id="proof-ctrl-resuming">
          <div className="proof-ctrl-transition-bar proof-ctrl-transition-bar--resuming">
            <span className="pct-spinner pct-spinner--green" aria-hidden="true" />
            <div className="proof-ctrl-status-text">
              <span className="proof-ctrl-status-label">Picking up where you left off…</span>
              <span className="proof-ctrl-transition-sub">Restoring your proof context — this takes just a moment</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
