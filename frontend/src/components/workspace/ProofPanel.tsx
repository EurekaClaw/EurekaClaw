import { useState } from 'react';
import type { SessionRun, TheoryState, LemmaNode } from '@/types';
import { useSessionStore } from '@/store/sessionStore';
import { apiPost } from '@/api/client';
import { LemmaFeedbackDialog } from './LemmaFeedbackDialog';

interface ProofPanelProps {
  run: SessionRun | null;
  theoryState: TheoryState | null | undefined;
}

interface LemmaEntry {
  id: string;
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

export function ProofPanel({ run, theoryState: ts }: ProofPanelProps) {
  const [reviewDismissedForRun, setReviewDismissedForRun] = useState('');
  const [selectingLemma, setSelectingLemma] = useState(false);
  const [selectedLemmaId, setSelectedLemmaId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);

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

  // Build proven entries
  const provenEntries: LemmaEntry[] = Object.entries(provenLemmas).map(([lemmaId, record]) => {
    const node = lemmaDAG[lemmaId];
    return {
      id: lemmaId,
      name: lemmaLabel(node, lemmaId),
      proof: record.proof_text || '',
      proven: true,
      conf: record.verified ? 'verified' : 'unverified',
    };
  });

  // Build open goal entries
  const openEntries: LemmaEntry[] = openGoalIds.map((lemmaId) => {
    const node = lemmaDAG[lemmaId];
    return {
      id: lemmaId,
      name: lemmaLabel(node, lemmaId),
      proof: node?.statement || '',
      proven: false,
      conf: lemmaConf(node),
    };
  });

  const allLemmas = [...provenEntries, ...openEntries];

  // Detect proof review gate: theory completed + writer not yet started + not dismissed
  const pipeline = run?.pipeline ?? [];
  const theoryTask = pipeline.find((t) => t.name === 'theory' || t.agent_role === 'theory');
  const theoryReviewTask = pipeline.find((t) => t.name === 'theory_review_gate');
  const writerTask = pipeline.find((t) => t.name === 'writer' || t.agent_role === 'writer');
  const theoryDone = theoryTask?.status === 'completed';
  const writerNotStarted = !writerTask || writerTask.status === 'pending' || writerTask.status === 'queued';
  const gateDone = theoryReviewTask?.status === 'completed';
  const showReviewGate =
    theoryDone &&
    allLemmas.length > 0 &&
    (gateDone || (theoryReviewTask?.status === 'in_progress')) &&
    writerNotStarted &&
    reviewDismissedForRun !== run?.run_id;

  const handleApprove = () => {
    setReviewDismissedForRun(run?.run_id ?? '');
    setSelectingLemma(false);
    setSelectedLemmaId(null);
  };

  const handleReject = () => {
    setSelectingLemma(true);
  };

  const handleLemmaSelect = (lemmaId: string) => {
    if (!selectingLemma) return;
    setSelectedLemmaId(lemmaId);
  };

  const handleFeedbackSubmit = async (reason: string) => {
    if (!selectedLemmaId || !run) return;
    setSubmitting(true);
    try {
      const spec = run.input_spec ?? {};
      const lemmaName = lemmaLabel(lemmaDAG[selectedLemmaId], selectedLemmaId);
      const feedback =
        `The user flagged lemma '${selectedLemmaId}' (${lemmaName}) as having a critical logical gap.\n` +
        `Issue: ${reason}\n` +
        `Please re-examine this lemma and fix the logical chain before assembling the proof.`;

      const newRun = await apiPost<SessionRun>('/api/runs', {
        mode: 'detailed',
        domain: spec.domain || '',
        conjecture: spec.conjecture || spec.query || '',
        query: spec.query || '',
        additional_context: (spec.additional_context || '') + `\n\n[User feedback on proof]: ${feedback}`,
        selected_skills: spec.selected_skills || [],
      });
      setSessions([newRun, ...sessions.filter((s) => s.run_id !== newRun.run_id)]);
      setCurrentRunId(newRun.run_id);
      setSelectedLemmaId(null);
      setSelectingLemma(false);
    } catch (err) {
      alert(`Could not start revision: ${(err as Error).message}`);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="proof-sketch-panel">
      {/* Proof Review Gate */}
      {showReviewGate && (
        <div className="proof-review-gate">
          {!selectingLemma ? (
            <div className="proof-review-card">
              <div className="proof-review-header">
                <span className="proof-review-icon">📋</span>
                <div>
                  <h3 className="proof-review-title">Proof Sketch Review</h3>
                  <p className="proof-review-subtitle">
                    The theory agent has finished. Review the proof structure below before the paper is written.
                  </p>
                </div>
              </div>
              <div className="proof-review-question">
                <p className="proof-review-question-text">Does this proof sketch look correct?</p>
                <div className="proof-review-actions">
                  <button className="proof-review-approve-btn" onClick={handleApprove}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    <span>Yes — Proceed to writing</span>
                  </button>
                  <button className="proof-review-reject-btn" onClick={handleReject}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                    <span>No — Flag a problematic step</span>
                  </button>
                </div>
              </div>
            </div>
          ) : (
            <div className="proof-review-card proof-review-card--selecting">
              <div className="proof-review-header">
                <span className="proof-review-icon">🔍</span>
                <div>
                  <h3 className="proof-review-title">Which lemma has the most critical logical gap?</h3>
                  <p className="proof-review-subtitle">
                    Click on the lemma you believe is incorrect. Only one can be selected.
                  </p>
                </div>
              </div>
              <button
                className="ghost-btn"
                style={{ alignSelf: 'flex-start', marginTop: '4px' }}
                onClick={() => { setSelectingLemma(false); setSelectedLemmaId(null); }}
              >
                Back to review
              </button>
            </div>
          )}
        </div>
      )}

      <div className="drawer-section">
        {theorem && (
          <div className="proof-theorem-block">
            <p className="proof-theorem-label">Theorem statement</p>
            <pre className="proof-theorem-text">
              {theorem.slice(0, 600)}{theorem.length > 600 ? '\n…' : ''}
            </pre>
          </div>
        )}
        {theoryStatus && theoryStatus !== 'pending' && (
          <p className="drawer-muted" style={{ marginBottom: '4px' }}>
            Status: <strong>{theoryStatus}</strong>
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
              <div
                key={l.id}
                className={
                  'proof-lemma-row' +
                  (selectingLemma ? ' proof-lemma-row--selectable' : '') +
                  (selectedLemmaId === l.id ? ' proof-lemma-row--selected' : '')
                }
                onClick={() => handleLemmaSelect(l.id)}
                role={selectingLemma ? 'button' : undefined}
                tabIndex={selectingLemma ? 0 : undefined}
                onKeyDown={selectingLemma ? (e) => { if (e.key === 'Enter' || e.key === ' ') handleLemmaSelect(l.id); } : undefined}
              >
                <span className="proof-lemma-number">{i + 1}</span>
                <div className="proof-lemma-content">
                  <span className="proof-lemma-name">{l.name}</span>
                  {l.proof && (
                    <span className="proof-lemma-formal">
                      {l.proof.slice(0, 160)}{l.proof.length > 160 ? '…' : ''}
                    </span>
                  )}
                </div>
                <span className={`proof-lemma-badge badge-${l.conf}`}>{l.conf}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="drawer-muted">No lemmas yet — the proof structure will appear as the theory agent works.</p>
        )}
      </div>

      {/* Lemma feedback dialog */}
      {selectedLemmaId && (
        <LemmaFeedbackDialog
          lemmaId={selectedLemmaId}
          lemmaName={lemmaLabel(lemmaDAG[selectedLemmaId], selectedLemmaId)}
          onSubmit={(reason) => void handleFeedbackSubmit(reason)}
          onClose={() => setSelectedLemmaId(null)}
        />
      )}

      {/* Submitting overlay */}
      {submitting && (
        <div className="proof-review-submitting">
          <span className="pct-spinner pct-spinner--amber" />
          <span>Re-running theory agent with your feedback...</span>
        </div>
      )}
    </div>
  );
}
