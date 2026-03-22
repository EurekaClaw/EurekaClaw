import { useState } from 'react';
import type { SessionRun } from '@/types';
import { getActiveOuterStage } from '@/lib/statusHelpers';
import { AGENT_MANIFEST } from '@/lib/agentManifest';
import { agentNarrativeLine } from '@/lib/agentManifest';
import { friendlyInnerStage } from '@/lib/statusHelpers';
import { titleCase, escapeHtml, humanize } from '@/lib/formatters';
import { apiPost } from '@/api/client';

interface LivePanelProps {
  run: SessionRun | null;
}

function SurveyGateForm({ run }: { run: SessionRun }) {
  const [paperText, setPaperText] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(skipPapers: boolean) {
    setSubmitting(true);
    try {
      const paperIds = skipPapers
        ? []
        : paperText
            .split(/[\n,]+/)
            .map((s) => s.trim())
            .filter(Boolean);
      await apiPost(`/api/runs/${run.run_id}/gate/survey`, { paper_ids: paperIds });
    } catch (err) {
      console.error('Survey gate submit failed:', err);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="live-activity-area">
      <div className="direction-gate-card">
        <p className="direction-gate-heading">📄 Survey found no papers</p>
        <p className="drawer-muted">
          The survey agent could not find relevant papers. You can provide paper IDs or arXiv IDs
          to retry, or continue without papers.
        </p>
        <textarea
          className="gate-textarea"
          placeholder="Enter paper IDs or arXiv IDs, one per line or comma-separated…"
          value={paperText}
          onChange={(e) => setPaperText(e.target.value)}
          rows={4}
          disabled={submitting}
        />
        <div className="gate-btn-row">
          <button
            className="btn btn-primary"
            disabled={submitting || !paperText.trim()}
            onClick={() => handleSubmit(false)}
          >
            Retry with these papers
          </button>
          <button
            className="btn btn-secondary"
            disabled={submitting}
            onClick={() => handleSubmit(true)}
          >
            Continue without papers
          </button>
        </div>
      </div>
    </div>
  );
}

function DirectionGateForm({ run }: { run: SessionRun }) {
  const brief = run.artifacts?.research_brief ?? {};
  const openProblems = brief.open_problems ?? [];
  const conjecture = run.input_spec?.conjecture || run.input_spec?.query || '';
  const [dirText, setDirText] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(direction: string) {
    setSubmitting(true);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/direction`, { direction });
    } catch (err) {
      console.error('Direction gate submit failed:', err);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="live-activity-area">
      <div className="direction-gate-card">
        <p className="direction-gate-heading">🧭 No research directions generated</p>
        <p className="drawer-muted">
          The ideation agent returned no candidate directions. Please provide a research direction
          to proceed, or use your original conjecture.
        </p>
        {openProblems.length > 0 && (
          <>
            <p className="drawer-muted" style={{ marginTop: '8px', fontWeight: 600 }}>
              Open problems found by survey:
            </p>
            <ul className="gate-problem-list">
              {openProblems.slice(0, 5).map((p, i) => (
                <li key={i}>{String(p).slice(0, 140)}</li>
              ))}
            </ul>
          </>
        )}
        <textarea
          className="gate-textarea"
          placeholder="Enter a research direction or hypothesis…"
          value={dirText}
          onChange={(e) => setDirText(e.target.value)}
          rows={3}
          disabled={submitting}
        />
        <div className="gate-btn-row">
          <button
            className="btn btn-primary"
            disabled={submitting || !dirText.trim()}
            onClick={() => handleSubmit(dirText.trim())}
          >
            Use this direction
          </button>
          {conjecture && (
            <button
              className="btn btn-secondary"
              disabled={submitting}
              onClick={() => handleSubmit(conjecture)}
            >
              Use original conjecture
            </button>
          )}
        </div>
      </div>
    </div>
  );
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

  // Survey gate
  const surveyTask = pipeline.find((t) => t.name === 'survey');
  if (surveyTask?.status === 'awaiting_gate') {
    return <SurveyGateForm run={run} />;
  }

  // Direction gate
  const dirGateTask = pipeline.find((t) => t.name === 'direction_selection_gate');
  if (dirGateTask?.status === 'awaiting_gate') {
    return <DirectionGateForm run={run} />;
  }

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
