import { useState } from 'react';
import type { SessionRun, LemmaNode } from '@/types';
import { apiPost } from '@/api/client';
import { humanize } from '@/lib/formatters';

interface Props {
  run: SessionRun;
}

function SurveyGate({ run }: Props) {
  const [paperText, setPaperText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(skip: boolean) {
    if (submitting) return;
    setError(null);
    setSubmitting(true);
    try {
      const paper_ids = skip
        ? []
        : paperText.split(/[\n,]+/).map((s) => s.trim()).filter(Boolean);
      await apiPost(`/api/runs/${run.run_id}/gate/survey`, { paper_ids });
      // Keep submitting=true; overlay unmounts when pipeline status moves off awaiting_gate
    } catch (err) {
      setError((err as Error).message || 'Could not submit');
      setSubmitting(false);
    }
  }

  return (
    <div className="gate-overlay-body">
      <p className="gate-overlay-heading">📄 Survey found no papers</p>
      <p className="gate-overlay-sub">
        Provide paper IDs or arXiv IDs to retry, or continue without papers.
      </p>
      <textarea
        className="gate-textarea"
        placeholder="Enter paper IDs, one per line or comma-separated…"
        value={paperText}
        onChange={(e) => setPaperText(e.target.value)}
        rows={4}
        disabled={submitting}
      />
      {error && <p className="gate-overlay-error" role="alert">{error}</p>}
      <div className="gate-btn-row">
        <button className="btn btn-primary" disabled={submitting || !paperText.trim()} onClick={() => void submit(false)}>
          {submitting ? 'Submitting…' : 'Retry with these papers'}
        </button>
        <button className="btn btn-secondary" disabled={submitting} onClick={() => void submit(true)}>
          {submitting ? 'Submitting…' : 'Continue without papers'}
        </button>
      </div>
    </div>
  );
}

function DirectionGate({ run }: Props) {
  const brief = run.artifacts?.research_brief ?? {};
  const openProblems = (brief.open_problems ?? []) as string[];
  const keyObjects = (brief.key_mathematical_objects ?? []) as string[];
  const conjecture = run.input_spec?.conjecture || run.input_spec?.query || '';
  const [dirText, setDirText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(direction: string) {
    const val = direction.trim();
    if (!val || submitting) return;
    setError(null);
    setSubmitting(true);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/direction`, { direction: val });
      // Keep submitting=true; overlay unmounts on status change
    } catch (err) {
      setError((err as Error).message || 'Could not submit');
      setSubmitting(false);
    }
  }

  return (
    <div className="gate-overlay-body">
      <p className="gate-overlay-heading">
        🧭 No research directions generated
      </p>
      <p className="gate-overlay-sub">
        Enter a research direction or hypothesis to continue.
      </p>

      {openProblems.length > 0 && (
        <div className="direction-gate-section">
          <p className="direction-gate-sublabel">Open problems</p>
          <ul className="direction-gate-problems">
            {openProblems.slice(0, 5).map((p, i) => (
              <li key={i}>
                <span className="direction-gate-problem-text">
                  {humanize(typeof p === 'string' ? p : String(p))}
                </span>
                <button
                  className="direction-gate-use-btn"
                  disabled={submitting}
                  onClick={() => setDirText(typeof p === 'string' ? p : String(p))}
                >
                  Use
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {keyObjects.length > 0 && (
        <div className="direction-gate-section">
          <p className="direction-gate-sublabel">Key objects</p>
          <div className="direction-gate-tags">
            {keyObjects.slice(0, 8).map((obj, i) => (
              <span key={i} className="direction-gate-tag">{humanize(String(obj))}</span>
            ))}
          </div>
        </div>
      )}

      <textarea
        className="gate-textarea"
        placeholder='e.g. "Prove a generalization bound for sparse transformer attention under low-rank kernel assumptions"'
        value={dirText}
        onChange={(e) => setDirText(e.target.value)}
        rows={2}
        disabled={submitting}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            const val = dirText.trim() || conjecture;
            if (val) void submit(val);
          }
        }}
      />

      {error && <p className="gate-overlay-error" role="alert">{error}</p>}

      <div className="gate-btn-row">
        {conjecture && (
          <button className="btn btn-primary" disabled={submitting} onClick={() => void submit(conjecture)}>
            {submitting ? 'Submitting…' : 'Use conjecture'}
          </button>
        )}
        <button
          className={conjecture ? 'btn btn-secondary' : 'btn btn-primary'}
          disabled={submitting || !dirText.trim()}
          onClick={() => void submit(dirText)}
        >
          {submitting ? 'Submitting…' : 'Use this direction'}
        </button>
      </div>
    </div>
  );
}

function TheoryReviewGate({ run }: Props) {
  const ts = run.artifacts?.theory_state;
  const lemmaDAG = ts?.lemma_dag ?? {};
  const lemmaEntries = Object.entries(lemmaDAG);
  const [rejecting, setRejecting] = useState(false);
  const [selectedLemma, setSelectedLemma] = useState('');
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function approve() {
    if (submitting) return;
    setError(null);
    setSubmitting(true);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/theory`, { approved: true });
    } catch (err) {
      setError((err as Error).message || 'Could not submit');
      setSubmitting(false);
    }
  }

  async function reject() {
    if (!reason.trim() || submitting) return;
    setError(null);
    setSubmitting(true);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/theory`, {
        approved: false,
        lemma_id: selectedLemma,
        reason: reason.trim(),
      });
    } catch (err) {
      setError((err as Error).message || 'Could not submit');
      setSubmitting(false);
    }
  }

  return (
    <div className="gate-overlay-body">
      <p className="gate-overlay-heading">🔍 Proof ready for review</p>
      <p className="gate-overlay-sub">
        The theory agent has completed a proof attempt. Approve to continue, or flag a concern to request a revision.
      </p>
      {ts?.formal_statement && (
        <pre className="gate-overlay-theorem">{ts.formal_statement.slice(0, 400)}{ts.formal_statement.length > 400 ? '\n…' : ''}</pre>
      )}
      {error && <p className="gate-overlay-error" role="alert">{error}</p>}
      {!rejecting ? (
        <div className="gate-btn-row">
          <button className="btn btn-primary" disabled={submitting} onClick={() => void approve()}>
            {submitting ? 'Submitting…' : 'Approve & continue'}
          </button>
          <button className="btn btn-secondary" disabled={submitting} onClick={() => setRejecting(true)}>
            Flag a concern
          </button>
        </div>
      ) : (
        <div className="theory-feedback-section">
          <p className="theory-feedback-heading">Flag a concern</p>
          {lemmaEntries.length > 0 && (
            <div className="theory-lemma-picker">
              <p className="theory-lemma-picker-label">Select a lemma (optional)</p>
              <div className="theory-lemma-list">
                {lemmaEntries.map(([id, node], idx) => {
                  const lemma = node as LemmaNode;
                  const label = lemma.informal || lemma.statement || id;
                  const isSelected = selectedLemma === id;
                  return (
                    <button
                      key={id}
                      className={`theory-lemma-item${isSelected ? ' is-selected' : ''}`}
                      disabled={submitting}
                      onClick={() => setSelectedLemma(isSelected ? '' : id)}
                    >
                      <span className="theory-lemma-num">{idx + 1}</span>
                      <span className="theory-lemma-text">{humanize(typeof label === 'string' ? label : String(label))}</span>
                      {isSelected && (
                        <svg className="theory-lemma-check" xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                      )}
                    </button>
                  );
                })}
              </div>
            </div>
          )}
          <textarea
            className="gate-textarea"
            placeholder="Describe the logical gap or issue…"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            disabled={submitting}
          />
          <div className="gate-btn-row">
            <button className="btn btn-primary" disabled={submitting || !reason.trim()} onClick={() => void reject()}>
              {submitting ? 'Submitting…' : 'Submit feedback & revise'}
            </button>
            <button className="btn btn-ghost" disabled={submitting} onClick={() => setRejecting(false)}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export function GateOverlay({ run }: Props) {
  // If the orchestrator is gone, the gate has no-one to submit to — don't
  // trap the user behind a modal they can't clear. Pipeline state may still
  // show `awaiting_gate` on disk; run.status is the source of truth about
  // whether a live submitter exists.
  if (run.status === 'failed' || run.status === 'completed') return null;

  const pipeline = run.pipeline ?? [];

  const surveyTask = pipeline.find((t) => t.name === 'survey');
  const dirTask = pipeline.find((t) => t.name === 'direction_selection_gate');
  const theoryTask = pipeline.find((t) => t.name === 'theory_review_gate');

  const activeGate =
    surveyTask?.status === 'awaiting_gate' ? 'survey' :
    dirTask?.status === 'awaiting_gate' ? 'direction' :
    theoryTask?.status === 'awaiting_gate' ? 'theory' :
    null;

  if (!activeGate) return null;

  return (
    <div className="gate-overlay-backdrop">
      <div className={`gate-overlay-card${activeGate === 'theory' ? ' gate-overlay-card--wide' : ''}`}>
        {activeGate === 'survey' && <SurveyGate run={run} />}
        {activeGate === 'direction' && <DirectionGate run={run} />}
        {activeGate === 'theory' && <TheoryReviewGate run={run} />}
      </div>
    </div>
  );
}
