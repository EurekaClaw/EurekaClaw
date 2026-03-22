import type { TheoryState } from '@/types';

interface ProofPanelProps {
  theoryState: TheoryState | null | undefined;
}

interface LemmaEntry {
  name: string;
  proof: string;
  proven: boolean;
  conf: string;
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

  const theorem = ts.formal_statement || ts.proof_skeleton || '';
  const lemmas = ts.open_goals ?? [];
  const provenLemmas = ts.proven_lemmas ?? {};
  const counterexamples = ts.counterexamples ?? [];
  const iteration = ts.iteration ?? 0;

  const provenEntries: LemmaEntry[] = Object.entries(provenLemmas).map(([name, proof]) => ({
    name,
    proof: typeof proof === 'string' ? proof : JSON.stringify(proof),
    proven: true,
    conf: 'verified',
  }));

  const openEntries: LemmaEntry[] = lemmas.map((g, i) => {
    const name = typeof g === 'string' ? g : (g.name ?? `Goal ${i + 1}`);
    const conf = typeof g === 'string' ? 'low' : (g.confidence || (g.status === 'proven' ? 'verified' : 'low'));
    return {
      name,
      proof: typeof g === 'string' ? '' : (g.description ?? ''),
      proven: false,
      conf,
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
        {iteration > 0 && (
          <p className="drawer-muted">
            Iteration {iteration} · {provenEntries.length} proven · {openEntries.length} open
          </p>
        )}
        {counterexamples.length > 0 && (
          <div className="proof-counterexample-warning">
            ⚠ {counterexamples.length} counterexample{counterexamples.length > 1 ? 's' : ''} found — the theorem may need refinement.
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
