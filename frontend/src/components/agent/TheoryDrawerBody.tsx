import { useState } from 'react';
import type { Artifacts, KnownResult, ProofPlanEntry, ProofRecord } from '@/types';
import { humanize } from '@/lib/formatters';

interface TheoryDrawerBodyProps {
  arts: Artifacts;
}

function truncate(text: string, limit = 220): string {
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text;
}

function lemmaTitle(statement: string, fallback: string): string {
  const clean = statement.trim();
  return clean ? truncate(clean, 90) : fallback;
}

export function TheoryDrawerBody({ arts }: TheoryDrawerBodyProps) {
  const [expandedResultKey, setExpandedResultKey] = useState<string | null>(null);
  const [isExtractedResultsOpen, setIsExtractedResultsOpen] = useState(false);
  const [isResearchGapOpen, setIsResearchGapOpen] = useState(false);
  const [isProofPlanOpen, setIsProofPlanOpen] = useState(false);
  const [isOpenGoalsOpen, setIsOpenGoalsOpen] = useState(false);
  const [isProvenLemmasOpen, setIsProvenLemmasOpen] = useState(false);
  const [isFailedAttemptsOpen, setIsFailedAttemptsOpen] = useState(false);
  const [isCounterexamplesOpen, setIsCounterexamplesOpen] = useState(false);
  const [isProofSnapshotOpen, setIsProofSnapshotOpen] = useState(false);
  const [expandedFailureKey, setExpandedFailureKey] = useState<string | null>(null);
  const [expandedProvenLemmaKey, setExpandedProvenLemmaKey] = useState<string | null>(null);
  const [expandedCounterexampleKey, setExpandedCounterexampleKey] = useState<string | null>(null);
  const ts = arts.theory_state;
  if (!ts) {
    return (
      <div className="drawer-empty-state">
        <span>📐</span>
        <p>The proof hasn't started yet — theory-stage extracts and proof attempts will appear here once the theory agent begins its work.</p>
      </div>
    );
  }

  const knownResults = ts.known_results ?? [];
  const proofPlan = ts.proof_plan ?? [];
  const openGoals = ts.open_goals ?? [];
  const provenLemmas = ts.proven_lemmas ?? {};
  const failedAttempts = ts.failed_attempts ?? [];
  const counterexamples = ts.counterexamples ?? [];
  const lemmaDag = ts.lemma_dag ?? {};

  const openGoalEntries = openGoals.map((lemmaId) => ({
    lemmaId,
    statement: lemmaDag[lemmaId]?.statement || '',
    verificationMethod: lemmaDag[lemmaId]?.verification_method || '',
  }));

  const provenEntries = Object.entries(provenLemmas) as [string, ProofRecord][];
  const recentFailures = failedAttempts.slice(-6).reverse();
  const recentPlan = proofPlan.slice(0, 10);

  return (
    <>
      {(ts.research_gap || ts.problem_type || ts.proof_template) && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsResearchGapOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isResearchGapOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Research Gap</h4>
            </span>
          </button>
          {isResearchGapOpen && (
            <>
              {ts.research_gap && <blockquote className="drawer-direction-quote">{humanize(ts.research_gap)}</blockquote>}
              {(ts.problem_type || ts.proof_template) && (
                <p className="drawer-muted">
                  {ts.problem_type && `Problem type: ${humanize(ts.problem_type)}`}
                  {ts.problem_type && ts.proof_template && ' · '}
                  {ts.proof_template && `Template: ${humanize(ts.proof_template)}`}
                </p>
              )}
            </>
          )}
        </div>
      )}

      {knownResults.length > 0 && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsExtractedResultsOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isExtractedResultsOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Extracted Results</h4>
              <span className="drawer-section-toggle-count">{knownResults.length}</span>
            </span>
          </button>
          {isExtractedResultsOpen && (
            <div className="drawer-paper-list drawer-paper-list--scroll">
              {knownResults.map((result: KnownResult, index) => {
                const resultKey = `${result.source_paper_id}-${index}`;
                const isExpanded = expandedResultKey === resultKey;
                const detailText = result.theorem_content || result.statement || result.informal || '';

                return (
                  <button
                    key={resultKey}
                    type="button"
                    className={`drawer-result-card${isExpanded ? ' is-expanded' : ''}`}
                    onClick={() => setExpandedResultKey(isExpanded ? null : resultKey)}
                  >
                    <div className="drawer-result-head">
                      <div className="drawer-paper-row">
                        <span className="drawer-paper-year">{humanize(result.result_type)}</span>
                        <span className="drawer-result-title">
                          {humanize(lemmaTitle(result.statement, result.source_paper_title || 'Extracted result'))}
                        </span>
                      </div>
                      <span className="drawer-result-toggle">{isExpanded ? 'Hide' : 'View'}</span>
                    </div>
                    {isExpanded && (
                      <div className="drawer-result-detail">
                        <p className="drawer-result-source">
                          {humanize(result.source_paper_title || result.source_paper_id || 'Unknown source')}
                        </p>
                        {detailText && <pre className="drawer-paper-excerpt">{humanize(detailText)}</pre>}
                        {result.assumptions && (
                          <p className="drawer-result-meta">
                            <strong>Assumptions:</strong> {humanize(result.assumptions)}
                          </p>
                        )}
                        {result.proof_idea && (
                          <p className="drawer-result-meta">
                            <strong>Proof idea:</strong> {humanize(result.proof_idea)}
                          </p>
                        )}
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}

      {recentPlan.length > 0 && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsProofPlanOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isProofPlanOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Proof Plan</h4>
              <span className="drawer-section-toggle-count">{proofPlan.length}</span>
            </span>
          </button>
          {isProofPlanOpen && (
            <div className="drawer-paper-list">
              {recentPlan.map((item: ProofPlanEntry) => (
                <div key={item.lemma_id} className="drawer-paper-row">
                  <span className="drawer-paper-year">{humanize(item.provenance)}</span>
                  <span>{humanize(lemmaTitle(item.statement, item.lemma_id))}</span>
                </div>
              ))}
              {proofPlan.length > recentPlan.length && (
                <p className="drawer-more">and {proofPlan.length - recentPlan.length} more planned steps…</p>
              )}
            </div>
          )}
        </div>
      )}

      {openGoalEntries.length > 0 && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsOpenGoalsOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isOpenGoalsOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Open Goals</h4>
              <span className="drawer-section-toggle-count">{openGoalEntries.length}</span>
            </span>
          </button>
          {isOpenGoalsOpen && (
            <ul className="drawer-problems-list">
              {openGoalEntries.map((goal) => (
                <li key={goal.lemmaId}>
                  {humanize(lemmaTitle(goal.statement, goal.lemmaId))}
                  {goal.verificationMethod ? ` (${humanize(goal.verificationMethod)})` : ''}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {provenEntries.length > 0 && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsProvenLemmasOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isProvenLemmasOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Proven Lemmas</h4>
              <span className="drawer-section-toggle-count">{provenEntries.length}</span>
            </span>
          </button>
          {isProvenLemmasOpen && (
            <div className="drawer-paper-list">
              {provenEntries.slice(0, 10).map(([lemmaId, record]) => {
                const key = lemmaId;
                const isExpanded = expandedProvenLemmaKey === key;
                const detailText = lemmaDag[lemmaId]?.statement || record.proof_text || lemmaId;
                return (
                  <button
                    key={lemmaId}
                    type="button"
                    className={`drawer-result-card${isExpanded ? ' is-expanded' : ''}`}
                    onClick={() => setExpandedProvenLemmaKey(isExpanded ? null : key)}
                  >
                    <div className="drawer-result-head">
                      <div className="drawer-paper-row">
                        <span className="drawer-paper-year">{record.verified ? 'verified' : 'partial'}</span>
                        <span className="drawer-result-title">
                          {humanize(lemmaTitle(detailText, lemmaId))}
                          {record.verification_method ? ` · ${humanize(record.verification_method)}` : ''}
                        </span>
                      </div>
                      <span className="drawer-result-toggle">{isExpanded ? 'Hide' : 'View'}</span>
                    </div>
                    {isExpanded && (
                      <div className="drawer-result-detail">
                        <pre className="drawer-paper-excerpt">{humanize(detailText)}</pre>
                        {record.proof_text && record.proof_text !== detailText && (
                          <pre className="drawer-paper-excerpt">{humanize(record.proof_text)}</pre>
                        )}
                      </div>
                    )}
                  </button>
                );
              })}
              {provenEntries.length > 10 && (
                <p className="drawer-more">and {provenEntries.length - 10} more proven lemmas…</p>
              )}
            </div>
          )}
        </div>
      )}

      {recentFailures.length > 0 && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsFailedAttemptsOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isFailedAttemptsOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Recent Failed Attempts</h4>
              <span className="drawer-section-toggle-count">{recentFailures.length}</span>
            </span>
          </button>
          {isFailedAttemptsOpen && (
            <div className="drawer-paper-list">
              {recentFailures.map((failure, index) => {
                const failureKey = `${failure.lemma_id}-${index}`;
                const isExpanded = expandedFailureKey === failureKey;
                return (
                  <button
                    key={failureKey}
                    type="button"
                    className={`drawer-result-card${isExpanded ? ' is-expanded' : ''}`}
                    onClick={() => setExpandedFailureKey(isExpanded ? null : failureKey)}
                  >
                    <div className="drawer-result-head">
                      <div className="drawer-paper-row">
                        <span className="drawer-paper-year">failed</span>
                        <span className="drawer-result-title">
                          <strong>{humanize(failure.lemma_id)}</strong>: {humanize(truncate(failure.failure_reason, 90))}
                        </span>
                      </div>
                      <span className="drawer-result-toggle">{isExpanded ? 'Hide' : 'View'}</span>
                    </div>
                    {isExpanded && (
                      <div className="drawer-result-detail">
                        <p className="drawer-result-meta">
                          <strong>Lemma:</strong> {humanize(failure.lemma_id)}
                        </p>
                        <pre className="drawer-paper-excerpt">{humanize(failure.attempt_text || failure.failure_reason)}</pre>
                        <p className="drawer-result-meta">
                          <strong>Failure reason:</strong> {humanize(failure.failure_reason)}
                        </p>
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}

      {counterexamples.length > 0 && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsCounterexamplesOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isCounterexamplesOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Counterexamples</h4>
              <span className="drawer-section-toggle-count">{counterexamples.length}</span>
            </span>
          </button>
          {isCounterexamplesOpen && (
            <div className="drawer-paper-list">
              {counterexamples.slice(0, 6).map((cx, index) => {
                const key = `${cx.lemma_id}-${index}`;
                const isExpanded = expandedCounterexampleKey === key;
                return (
                  <button
                    key={key}
                    type="button"
                    className={`drawer-result-card${isExpanded ? ' is-expanded' : ''}`}
                    onClick={() => setExpandedCounterexampleKey(isExpanded ? null : key)}
                  >
                    <div className="drawer-result-head">
                      <div className="drawer-paper-row">
                        <span className="drawer-paper-year">counter</span>
                        <span className="drawer-result-title">
                          <strong>{humanize(cx.lemma_id)}</strong>: {humanize(truncate(cx.counterexample_description, 90))}
                        </span>
                      </div>
                      <span className="drawer-result-toggle">{isExpanded ? 'Hide' : 'View'}</span>
                    </div>
                    {isExpanded && (
                      <div className="drawer-result-detail">
                        <p className="drawer-result-meta">
                          <strong>Lemma:</strong> {humanize(cx.lemma_id)}
                        </p>
                        <pre className="drawer-paper-excerpt">{humanize(cx.counterexample_description)}</pre>
                        {cx.suggested_refinement && (
                          <p className="drawer-result-meta">
                            <strong>Suggested refinement:</strong> {humanize(cx.suggested_refinement)}
                          </p>
                        )}
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}

      {(ts.formal_statement || ts.assembled_proof || ts.proof_skeleton) && (
        <div className="drawer-section">
          <button
            type="button"
            className="drawer-section-toggle"
            onClick={() => setIsProofSnapshotOpen((open) => !open)}
          >
            <span className="drawer-section-toggle-title">
              <span className={`drawer-section-toggle-caret${isProofSnapshotOpen ? ' is-open' : ''}`} aria-hidden="true">
                ▾
              </span>
              <h4>Current Proof Snapshot</h4>
            </span>
          </button>
          {isProofSnapshotOpen && (
            <pre className="drawer-paper-excerpt">
              {truncate(ts.formal_statement || ts.assembled_proof || ts.proof_skeleton || '', 1400)}
            </pre>
          )}
        </div>
      )}
    </>
  );
}
