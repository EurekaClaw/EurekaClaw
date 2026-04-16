import type { SessionRun, PipelineTask } from '@/types';
import { getActiveOuterStage } from '@/lib/statusHelpers';
import { AGENT_MANIFEST, STAGE_TASK_MAP } from '@/lib/agentManifest';
import { agentNarrativeLine } from '@/lib/agentManifest';
import { friendlyInnerStage } from '@/lib/statusHelpers';
import { titleCase, escapeHtml, humanize, formatLocalTimestamp, parseServerTimestamp } from '@/lib/formatters';

function pipelineEventLabel(taskName: string, status: string, error?: string): string {
  const role = STAGE_TASK_MAP[taskName] || taskName;
  const manifest = AGENT_MANIFEST.find((a) => a.role === role);
  const name = manifest?.name || titleCase(taskName);
  if (status === 'completed') return `${name} completed`;
  if (status === 'failed') return `${name} failed${error ? ': ' + error.slice(0, 80) : ''}`;
  if (status === 'in_progress' || status === 'running') return `${name} running...`;
  if (status === 'skipped') return `${name} skipped`;
  return `${name} ${status}`;
}

function PipelineTimeline({ tasks, run }: { tasks: PipelineTask[]; run: SessionRun }) {
  const events: { time: string | undefined; label: string; failed: boolean }[] = [];

  // Session creation event
  if (run.created_at) {
    events.push({ time: run.created_at, label: 'Session created', failed: false });
  }

  // Two events per task: started + completed/failed
  for (const t of tasks) {
    if (t.started_at) {
      events.push({
        time: t.started_at,
        label: pipelineEventLabel(t.name, 'in_progress'),
        failed: false,
      });
    }
    if (t.completed_at && t.status === 'completed') {
      events.push({
        time: t.completed_at,
        label: pipelineEventLabel(t.name, 'completed'),
        failed: false,
      });
    }
    if (t.status === 'failed') {
      events.push({
        time: t.completed_at || t.started_at,
        label: pipelineEventLabel(t.name, 'failed', t.error_message),
        failed: true,
      });
    }
    if (t.status === 'skipped') {
      events.push({
        time: t.started_at || t.completed_at,
        label: pipelineEventLabel(t.name, 'skipped'),
        failed: false,
      });
    }
  }

  events.sort((a, b) => {
    const tA = parseServerTimestamp(a.time)?.getTime() ?? 0;
    const tB = parseServerTimestamp(b.time)?.getTime() ?? 0;
    return tA - tB;
  });

  if (!events.length) return null;

  return (
    <div className="pipeline-timeline">
      {events.map((ev, i) => (
        <div key={i} className={`pipeline-event${ev.failed ? ' pipeline-event--failed' : ''}`}>
          <span className="pipeline-event-dot" />
          <span className="pipeline-event-label">{ev.label}</span>
          <span className="pipeline-event-time">{formatLocalTimestamp(ev.time)}</span>
        </div>
      ))}
    </div>
  );
}

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
  const pipelineTimeline = <PipelineTimeline tasks={pipeline} run={run} />;
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
          <p className="live-stage-label" style={{ color: 'var(--ok)' }}>Research complete</p>
          {dir && <blockquote className="drawer-direction-quote">{dir}</blockquote>}
          {hypothesis && !dir && <blockquote className="drawer-direction-quote">{hypothesis}</blockquote>}
          <p className="drawer-muted">Switch to the <strong>Paper</strong> tab to review the draft and ask questions, or <strong>Proof</strong> for the theorem sketch.</p>
          {pipelineTimeline}
          {launchHtmlLink}
        </div>
      </div>
    );
  }

  if (status === 'failed') {
    return (
      <div className="live-activity-area">
        <div className="live-thinking-view">
          <p className="live-stage-label" style={{ color: 'var(--warn)' }}>Session failed</p>
          {run.error && <p className="drawer-muted">{run.error}</p>}
          {pipelineTimeline}
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
