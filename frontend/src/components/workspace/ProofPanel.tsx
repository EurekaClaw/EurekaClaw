import type { TheoryState, LemmaNode } from '@/types';

interface ProofPanelProps {
  theoryState: TheoryState | null | undefined;
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

export function ProofPanel({ theoryState: ts }: ProofPanelProps) {
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

  return (
    <div className="proof-sketch-panel">
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
              <div key={i} className="proof-lemma-row">
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
    </div>
  );
}
