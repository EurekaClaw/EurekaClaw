import type { SessionRun } from '@/types';
import { getActiveOuterStage } from '@/lib/statusHelpers';
import { AGENT_MANIFEST } from '@/lib/agentManifest';
import { agentNarrativeLine } from '@/lib/agentManifest';
import { friendlyInnerStage } from '@/lib/statusHelpers';
import { titleCase, escapeHtml, humanize } from '@/lib/formatters';

interface LivePanelProps {
  run: SessionRun | null;
}

export function LivePanel({ run }: LivePanelProps) {
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
  const launchHtmlUrl = run.launch_html_url;
  const launchHtmlLink = launchHtmlUrl ? (
    <p className="live-html-link-row">
      <a className="live-html-link" href={launchHtmlUrl} target="_blank" rel="noreferrer">
        Open run HTML log
      </a>
    </p>
  ) : null;

  // Direction gate (read-only fallback when ideation done with 0 directions)
  const brief = arts.research_brief ?? {};
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

  // Theory review gate — shown in ProofPanel, prompt user to switch tab
  const theoryReviewTask = pipeline.find((t) => t.name === 'theory_review_gate');
  if (theoryReviewTask?.status === 'awaiting_gate') {
    return (
      <div className="live-activity-area">
        <div className="direction-gate-card">
          <p className="direction-gate-heading">🔍 Proof ready for review</p>
          <p className="drawer-muted">
            The theory agent has completed a proof attempt. Switch to the{' '}
            <strong>Proof</strong> tab to review the proof sketch and approve or flag a concern.
          </p>
        </div>
      </div>
    );
  }

  if (status === 'running' || status === 'queued') {
    const innerStage = run.paused_stage || '';
    const innerLabel = innerStage ? `while ${friendlyInnerStage(innerStage) ?? humanize(innerStage)}` : '';
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
          {launchHtmlLink}
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
          {launchHtmlLink}
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
          {launchHtmlLink}
        </div>
      </div>
    );
  }

  if (status === 'completed') {
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
          {launchHtmlLink}
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
          {launchHtmlLink}
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
