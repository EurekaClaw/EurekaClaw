import { useState } from 'react';
import type { TheoryState, LemmaNode, SessionRun } from '@/types';
import { apiPost } from '@/api/client';
import { humanize } from '@/lib/formatters';

interface ProofPanelProps {
  run: SessionRun | null;
  theoryState?: TheoryState | null;
}

interface LemmaEntry {
  name: string;
  proof: string;
  proven: boolean;
  conf: string;
}

function lemmaLabel(node: LemmaNode | undefined, fallbackId: string): string {
  if (!node) return fallbackId;
  return node.informal || node.statement || fallbackId;
}

function lemmaConf(node: LemmaNode | undefined): string {
  if (!node) return 'open';
  if (node.verified === true) return 'verified';
  if (node.verified === false) return 'failed';
  if (node.confidence_score != null) {
    if (node.confidence_score >= 0.8) return 'high';
    if (node.confidence_score >= 0.5) return 'medium';
    return 'low';
  }
  return 'open';
}

function TheoryReviewGate({ run, ts }: { run: SessionRun; ts: TheoryState }) {
  const lemmaDAG = ts.lemma_dag ?? {};
  const lemmaEntries = Object.entries(lemmaDAG);
  const [selectedLemma, setSelectedLemma] = useState('');
  const [reason, setReason] = useState('');
  const [rejecting, setRejecting] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  async function handleApprove() {
    setSubmitting(true);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/theory`, { approved: true });
    } catch (err) {
      console.error('Theory gate approve failed:', err);
    } finally {
      setSubmitting(false);
    }
  }

  async function handleReject() {
    setSubmitting(true);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/theory`, {
        approved: false,
        lemma_id: selectedLemma,
        reason,
      });
      setRejecting(false);
      setSelectedLemma('');
      setReason('');
    } catch (err) {
      console.error('Theory gate reject failed:', err);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="proof-gate-review">
      <p className="proof-gate-heading">🔍 Theory ready for review</p>
      <p className="drawer-muted">
        The theory agent has completed a proof attempt. Review the proof sketch above and approve
        to proceed, or flag a lemma with a concern to request a revision.
      </p>
      {!rejecting ? (
        <div className="gate-btn-row">
          <button className="btn btn-primary" disabled={submitting} onClick={handleApprove}>
            Approve &amp; continue
          </button>
          <button
            className="btn btn-secondary"
            disabled={submitting}
            onClick={() => setRejecting(true)}
          >
            Flag a concern
          </button>
        </div>
      ) : (
        <div className="proof-gate-reject-form">
          {lemmaEntries.length > 0 && (
            <select
              className="gate-select"
              value={selectedLemma}
              onChange={(e) => setSelectedLemma(e.target.value)}
              disabled={submitting}
            >
              <option value="">— Select a lemma (optional) —</option>
              {lemmaEntries.map(([id, node]) => (
                <option key={id} value={id}>
                  {humanize(lemmaLabel(node, id))}
                </option>
              ))}
            </select>
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
            <button
              className="btn btn-primary"
              disabled={submitting || !reason.trim()}
              onClick={handleReject}
            >
              Submit feedback &amp; revise
            </button>
            <button
              className="btn btn-ghost"
              disabled={submitting}
              onClick={() => setRejecting(false)}
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export function ProofPanel({ run, theoryState: theoryStateOverride }: ProofPanelProps) {
  const [expandedLemmaKey, setExpandedLemmaKey] = useState<string | null>(null);
  const [isTheoremOpen, setIsTheoremOpen] = useState(false);
  const ts = theoryStateOverride ?? run?.artifacts?.theory_state;
  const pipeline = run?.pipeline ?? [];

  if (!ts) {
    return (
      <div className="proof-sketch-panel">
        <div className="proof-sketch-empty">
          <span>📐</span>
          <p>The proof sketch will appear here once the theory agent starts building the argument.</p>
        </div>
      </div>
    );
  }

  const theorem = ts.formal_statement || ts.proof_skeleton || ts.assembled_proof || '';
  const lemmaDAG = ts.lemma_dag ?? {};
  const openGoalIds = ts.open_goals ?? [];
  const provenLemmas = ts.proven_lemmas ?? {};
  const counterexamples = ts.counterexamples ?? [];
  const iteration = ts.iteration ?? 0;
  const theoryStatus = ts.status;

  // Build proven entries using ProofRecord.proof_text (not JSON.stringify)
  const provenEntries: LemmaEntry[] = Object.entries(provenLemmas).map(([lemmaId, record]) => {
    const node = lemmaDAG[lemmaId];
    return {
      name: lemmaLabel(node, lemmaId),
      proof: record.proof_text || '',
      proven: true,
      conf: record.verified ? 'verified' : 'unverified',
    };
  });

  // Build open goal entries using lemma_dag for human-readable names + confidence
  const openEntries: LemmaEntry[] = openGoalIds.map((lemmaId) => {
    const node = lemmaDAG[lemmaId];
    return {
      name: lemmaLabel(node, lemmaId),
      proof: node?.statement || '',
      proven: false,
      conf: lemmaConf(node),
    };
  });

  const allLemmas = [...provenEntries, ...openEntries];

  // Theory review gate
  const theoryReviewTask = pipeline.find((t) => t.name === 'theory_review_gate');
  const showReviewGate = theoryReviewTask?.status === 'awaiting_gate' && run != null;

  return (
    <div className="proof-sketch-panel">
      <div className="drawer-section">
        {theorem && (
          <div className="proof-theorem-block">
            <button
              type="button"
              className="drawer-section-toggle proof-theorem-toggle"
              onClick={() => setIsTheoremOpen((open) => !open)}
            >
              <span className="drawer-section-toggle-title">
                <span className={`drawer-section-toggle-caret${isTheoremOpen ? ' is-open' : ''}`} aria-hidden="true">
                  ▾
                </span>
                <p className="proof-theorem-label">Theorem statement</p>
              </span>
            </button>
            {isTheoremOpen && (
              <pre className="proof-theorem-text">
                {theorem}
              </pre>
            )}
          </div>
        )}
        {theoryStatus && theoryStatus !== 'pending' && (
          <p className="drawer-muted" style={{ marginBottom: '4px' }}>
            Status: <strong>{humanize(theoryStatus)}</strong>
            {iteration > 0 && ` · iteration ${iteration}`}
            {provenEntries.length > 0 && ` · ${provenEntries.length} proven`}
            {openEntries.length > 0 && ` · ${openEntries.length} open`}
          </p>
        )}
        {!theoryStatus && iteration > 0 && (
          <p className="drawer-muted">
            Iteration {iteration} · {provenEntries.length} proven · {openEntries.length} open
          </p>
        )}
        {counterexamples.length > 0 && (
          <div className="proof-counterexample-warning">
            ⚠ {counterexamples.length} counterexample{counterexamples.length > 1 ? 's' : ''} found
            {counterexamples.some((c) => c.falsifies_conjecture) && ' — the theorem may need refinement'}.
            {counterexamples[0]?.suggested_refinement && (
              <p style={{ marginTop: '4px', fontSize: '0.8rem' }}>
                Suggested: {counterexamples[0].suggested_refinement}
              </p>
            )}
          </div>
        )}
        {allLemmas.length > 0 && <h4 style={{ margin: '12px 0 6px' }}>Proof steps</h4>}
        {allLemmas.length > 0 ? (
          <div className="proof-lemma-chain">
            {allLemmas.map((l, i) => (
              <button
                key={i}
                type="button"
                className={`proof-lemma-row${expandedLemmaKey === `${i}` ? ' is-expanded' : ''}`}
                onClick={() => setExpandedLemmaKey(expandedLemmaKey === `${i}` ? null : `${i}`)}
              >
                <span className="proof-lemma-number">{i + 1}</span>
                <div className="proof-lemma-content">
                  <div className="proof-lemma-head">
                    <span className="proof-lemma-name">{humanize(l.name)}</span>
                    <span className="proof-lemma-toggle">{expandedLemmaKey === `${i}` ? 'Hide' : 'View'}</span>
                  </div>
                  {l.proof && (
                    expandedLemmaKey === `${i}` ? (
                      <pre className="proof-lemma-formal proof-lemma-formal--expanded">{l.proof}</pre>
                    ) : (
                      <span className="proof-lemma-formal">
                        {l.proof.slice(0, 160)}{l.proof.length > 160 ? '…' : ''}
                      </span>
                    )
                  )}
                </div>
                <span className={`proof-lemma-badge badge-${l.conf}`}>{humanize(l.conf)}</span>
              </button>
            ))}
          </div>
        ) : (
          <p className="drawer-muted">No lemmas yet — the proof structure will appear as the theory agent works.</p>
        )}
        {showReviewGate && <TheoryReviewGate run={run!} ts={ts} />}
      </div>
    </div>
  );
}
