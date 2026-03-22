import { useState } from 'react';
import type { SessionRun } from '@/types';
import { useSessionStore } from '@/store/sessionStore';
import { apiPost } from '@/api/client';
import { getActiveOuterStage } from '@/lib/statusHelpers';
import { AGENT_MANIFEST } from '@/lib/agentManifest';
import { agentNarrativeLine } from '@/lib/agentManifest';
import { friendlyInnerStage } from '@/lib/statusHelpers';
import { titleCase, escapeHtml } from '@/lib/formatters';

interface LivePanelProps {
  run: SessionRun | null;
}

export function LivePanel({ run }: LivePanelProps) {
  const [surveyPaperInput, setSurveyPaperInput] = useState('');
  const [surveyGateDismissed, setSurveyGateDismissed] = useState('');
  const [retrying, setRetrying] = useState(false);
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);
  if (!run) {
    return (
      <div className="live-activity-area">
        <div className="live-idle-state">
          <span>🔬</span>
          <p>Start a session to see live research activity.</p>
        </div>
      </div>
    );
  }

  const status = run.status;
  const pipeline = run.pipeline ?? [];
  const arts = run.artifacts ?? {};
  const activeOuter = getActiveOuterStage(pipeline);

  // Direction gate
  const brief = arts.research_brief ?? {};
  // directions is ResearchDirection[] from backend (not string[])
  const dirs = brief.directions ?? [];
  const ideationDone = pipeline.some(
    (t) => (t.name === 'ideation' || t.name === 'direction_selection_gate') && t.status === 'completed'
  );
  if (ideationDone && dirs.length === 0 && status !== 'completed' && status !== 'failed') {
    const conj = run.input_spec?.conjecture || run.input_spec?.query || '';
    return (
      <div className="live-activity-area">
        <div className="direction-gate-card">
          <p className="direction-gate-heading">📍 No research directions were generated</p>
          <p className="drawer-muted">Ideation returned no candidate directions. EurekaClaw will use your original conjecture as the proof target:</p>
          {conj && <blockquote className="drawer-direction-quote">{conj}</blockquote>}
          <p className="drawer-muted">The theory agent will proceed with this direction. If you'd like to guide the proof differently, pause the session and use the feedback box below.</p>
        </div>
      </div>
    );
  }

  // Empty survey gate — survey completed but found 0 papers
  const surveyDone = pipeline.some((t) => t.name === 'survey' && t.status === 'completed');
  const papers = arts.bibliography?.papers ?? [];
  const showSurveyGate =
    surveyDone &&
    papers.length === 0 &&
    status !== 'completed' &&
    status !== 'failed' &&
    surveyGateDismissed !== run.run_id;

  const handleRetryWithPapers = async () => {
    const ids = surveyPaperInput.split(/[\n,]+/).map((s) => s.trim()).filter(Boolean);
    if (!ids.length) return;
    setRetrying(true);
    try {
      const spec = run.input_spec ?? {};
      const newRun = await apiPost<SessionRun>('/api/runs', {
        mode: spec.mode || 'reference',
        domain: spec.domain || '',
        query: spec.query || '',
        conjecture: spec.conjecture || undefined,
        paper_ids: ids,
        additional_context: spec.additional_context || '',
        selected_skills: spec.selected_skills || [],
      });
      setSessions([newRun, ...sessions.filter((s) => s.run_id !== newRun.run_id)]);
      setCurrentRunId(newRun.run_id);
      setSurveyPaperInput('');
    } catch (err) {
      alert(`Could not start new session: ${(err as Error).message}`);
    } finally {
      setRetrying(false);
    }
  };

  if (showSurveyGate && (status === 'running' || status === 'queued')) {
    const innerStage = run.paused_stage || '';
    const innerLabel = innerStage ? `while ${friendlyInnerStage(innerStage) ?? innerStage}` : '';
    const stageName = activeOuter
      ? AGENT_MANIFEST.find((a) => a.role === activeOuter)?.name || titleCase(activeOuter)
      : 'Setting up';
    const taskMap = new Map(pipeline.map((t) => [t.agent_role, t]));
    const narrative = agentNarrativeLine(activeOuter || 'survey', taskMap, run);
    return (
      <div className="live-activity-area">
        <div className="survey-gate-card">
          <p className="survey-gate-heading">📚 Survey complete — 0 papers found</p>
          <p className="drawer-muted">
            The literature survey did not find any relevant papers. You can provide specific paper IDs or titles to retry, or let the pipeline continue without papers.
          </p>
          <textarea
            className="survey-gate-input"
            rows={3}
            placeholder={'arXiv IDs or titles, comma-separated\ne.g. 1706.03762, 2005.14165'}
            value={surveyPaperInput}
            onChange={(e) => setSurveyPaperInput(e.target.value)}
          />
          <div className="survey-gate-actions">
            <button
              className="primary-btn"
              disabled={retrying || !surveyPaperInput.trim()}
              onClick={() => void handleRetryWithPapers()}
            >
              {retrying ? 'Starting…' : 'Retry with these papers'}
            </button>
            <button
              className="ghost-btn"
              onClick={() => setSurveyGateDismissed(run.run_id)}
            >
              Continue without papers
            </button>
          </div>
        </div>
        <div className="live-thinking-view" style={{ marginTop: '16px' }}>
          <div className="thinking-dots" aria-label="Working">
            <span className="thinking-dot" />
            <span className="thinking-dot" />
            <span className="thinking-dot" />
          </div>
          <p className="live-stage-label">{stageName} {innerLabel}</p>
          <p className="drawer-muted live-stage-sub">{escapeHtml(narrative)}</p>
        </div>
      </div>
    );
  }

  if (status === 'running' || status === 'queued') {
    const innerStage = run.paused_stage || '';
    const innerLabel = innerStage ? `while ${friendlyInnerStage(innerStage) ?? innerStage}` : '';
    const stageName = activeOuter
      ? AGENT_MANIFEST.find((a) => a.role === activeOuter)?.name || titleCase(activeOuter)
      : 'Setting up';
    const taskMap = new Map(pipeline.map((t) => [t.agent_role, t]));
    const narrative = agentNarrativeLine(activeOuter || 'survey', taskMap, run);
    return (
      <div className="live-activity-area">
        <div className="live-thinking-view">
          <div className="thinking-dots" aria-label="Working">
            <span className="thinking-dot" />
            <span className="thinking-dot" />
            <span className="thinking-dot" />
          </div>
          <p className="live-stage-label">{stageName} {innerLabel}</p>
          <p className="drawer-muted live-stage-sub">{escapeHtml(narrative)}</p>
        </div>
      </div>
    );
  }

  if (status === 'paused' || status === 'pausing') {
    return (
      <div className="live-activity-area">
        <div className="live-thinking-view">
          <p className="live-stage-label" style={{ color: 'var(--amber)' }}>⏸ Session paused</p>
          <p className="drawer-muted">Use the Resume button to continue, or add feedback below to guide the next proof attempt.</p>
        </div>
      </div>
    );
  }

  if (status === 'resuming') {
    return (
      <div className="live-activity-area">
        <div className="live-thinking-view">
          <div className="thinking-dots" aria-label="Resuming">
            <span className="thinking-dot" />
            <span className="thinking-dot" />
            <span className="thinking-dot" />
          </div>
          <p className="live-stage-label" style={{ color: 'var(--green)' }}>Resuming proof…</p>
          <p className="drawer-muted">Restoring your proof context and continuing from the last checkpoint.</p>
        </div>
      </div>
    );
  }

  if (status === 'completed') {
    // selected_direction is a ResearchDirection object; show title + hypothesis
    const selDir = brief.selected_direction;
    const dir = selDir ? (selDir.title || '') : '';
    const hypothesis = selDir ? (selDir.hypothesis || '') : '';
    return (
      <div className="live-activity-area">
        <div className="live-thinking-view">
          <p className="live-stage-label" style={{ color: 'var(--green)' }}>✓ Research complete</p>
          {dir && <blockquote className="drawer-direction-quote">{dir}</blockquote>}
          {hypothesis && !dir && <blockquote className="drawer-direction-quote">{hypothesis}</blockquote>}
          <p className="drawer-muted">Switch to the <strong>Paper</strong> tab to read the draft, or <strong>Proof</strong> for the theorem sketch.</p>
        </div>
      </div>
    );
  }

  if (status === 'failed') {
    return (
      <div className="live-activity-area">
        <div className="live-thinking-view">
          <p className="live-stage-label" style={{ color: 'var(--red)' }}>✗ Session failed</p>
          <p className="drawer-muted">{run.error || 'An error occurred. Check the Logs tab for details.'}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="live-activity-area">
      <div className="live-idle-state"><span>🔬</span><p>Waiting for session to begin…</p></div>
    </div>
  );
}
