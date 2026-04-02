import { useState } from 'react';
import type { Artifacts, KnownResult, ProofPlanEntry, ProofRecord, FailedAttempt, Counterexample } from '@/types';
import { humanize } from '@/lib/formatters';
import { CollapsibleSection } from '@/components/shared/CollapsibleSection';

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

/* ── Expandable card list (shared pattern for results, lemmas, failures) ── */

interface ExpandableCardProps {
  tag: string;
  title: string;
  children: React.ReactNode;
}

function ExpandableCard({ tag, title, children }: ExpandableCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  return (
    <button
      type="button"
      className={`drawer-result-card${isExpanded ? ' is-expanded' : ''}`}
      onClick={() => setIsExpanded((v) => !v)}
    >
      <div className="drawer-result-head">
        <div className="drawer-paper-row">
          <span className="drawer-paper-year">{tag}</span>
          <span className="drawer-result-title">{title}</span>
        </div>
        <span className="drawer-result-toggle">{isExpanded ? 'Hide' : 'View'}</span>
      </div>
      {isExpanded && <div className="drawer-result-detail">{children}</div>}
    </button>
  );
}

/* ── Section: Research Gap ──────────────────────────────────────────────── */

function ResearchGapSection({ ts }: { ts: NonNullable<Artifacts['theory_state']> }) {
  if (!ts.research_gap && !ts.problem_type && !ts.proof_template) return null;
  return (
    <CollapsibleSection title="Research Gap">
      {ts.research_gap && <blockquote className="drawer-direction-quote">{humanize(ts.research_gap)}</blockquote>}
      {(ts.problem_type || ts.proof_template) && (
        <p className="drawer-muted">
          {ts.problem_type && `Problem type: ${humanize(ts.problem_type)}`}
          {ts.problem_type && ts.proof_template && ' · '}
          {ts.proof_template && `Template: ${humanize(ts.proof_template)}`}
        </p>
      )}
    </CollapsibleSection>
  );
}

/* ── Section: Extracted Results ─────────────────────────────────────────── */

function ExtractedResultsSection({ results }: { results: KnownResult[] }) {
  if (results.length === 0) return null;
  return (
    <CollapsibleSection title="Extracted Results" count={results.length}>
      <div className="drawer-paper-list drawer-paper-list--scroll">
        {results.map((result, index) => {
          const detailText = result.theorem_content || result.statement || result.informal || '';
          return (
            <ExpandableCard
              key={`${result.source_paper_id}-${index}`}
              tag={humanize(result.result_type)}
              title={humanize(lemmaTitle(result.statement, result.source_paper_title || 'Extracted result'))}
            >
              <p className="drawer-result-source">
                {humanize(result.source_paper_title || result.source_paper_id || 'Unknown source')}
              </p>
              {detailText && <pre className="drawer-paper-excerpt">{humanize(detailText)}</pre>}
              {result.assumptions && (
                <p className="drawer-result-meta"><strong>Assumptions:</strong> {humanize(result.assumptions)}</p>
              )}
              {result.proof_idea && (
                <p className="drawer-result-meta"><strong>Proof idea:</strong> {humanize(result.proof_idea)}</p>
              )}
            </ExpandableCard>
          );
        })}
      </div>
    </CollapsibleSection>
  );
}

/* ── Section: Proof Plan ───────────────────────────────────────────────── */

function ProofPlanSection({ plan }: { plan: ProofPlanEntry[] }) {
  if (plan.length === 0) return null;
  const shown = plan.slice(0, 10);
  return (
    <CollapsibleSection title="Proof Plan" count={plan.length}>
      <div className="drawer-paper-list">
        {shown.map((item) => (
          <div key={item.lemma_id} className="drawer-paper-row">
            <span className="drawer-paper-year">{humanize(item.provenance)}</span>
            <span>{humanize(lemmaTitle(item.statement, item.lemma_id))}</span>
          </div>
        ))}
        {plan.length > shown.length && (
          <p className="drawer-more">and {plan.length - shown.length} more planned steps…</p>
        )}
      </div>
    </CollapsibleSection>
  );
}

/* ── Section: Open Goals ───────────────────────────────────────────────── */

interface OpenGoalEntry {
  lemmaId: string;
  statement: string;
  verificationMethod: string;
}

function OpenGoalsSection({ goals }: { goals: OpenGoalEntry[] }) {
  if (goals.length === 0) return null;
  return (
    <CollapsibleSection title="Open Goals" count={goals.length}>
      <ul className="drawer-problems-list">
        {goals.map((goal) => (
          <li key={goal.lemmaId}>
            {humanize(lemmaTitle(goal.statement, goal.lemmaId))}
            {goal.verificationMethod ? ` (${humanize(goal.verificationMethod)})` : ''}
          </li>
        ))}
      </ul>
    </CollapsibleSection>
  );
}

/* ── Section: Proven Lemmas ────────────────────────────────────────────── */

function ProvenLemmasSection({ entries, lemmaDag }: {
  entries: [string, ProofRecord][];
  lemmaDag: Record<string, { statement?: string }>;
}) {
  if (entries.length === 0) return null;
  return (
    <CollapsibleSection title="Proven Lemmas" count={entries.length}>
      <div className="drawer-paper-list">
        {entries.slice(0, 10).map(([lemmaId, record]) => {
          const detailText = lemmaDag[lemmaId]?.statement || record.proof_text || lemmaId;
          return (
            <ExpandableCard
              key={lemmaId}
              tag={record.verified ? 'verified' : 'partial'}
              title={`${humanize(lemmaTitle(detailText, lemmaId))}${record.verification_method ? ` · ${humanize(record.verification_method)}` : ''}`}
            >
              <pre className="drawer-paper-excerpt">{humanize(detailText)}</pre>
              {record.proof_text && record.proof_text !== detailText && (
                <pre className="drawer-paper-excerpt">{humanize(record.proof_text)}</pre>
              )}
            </ExpandableCard>
          );
        })}
        {entries.length > 10 && (
          <p className="drawer-more">and {entries.length - 10} more proven lemmas…</p>
        )}
      </div>
    </CollapsibleSection>
  );
}

/* ── Section: Failed Attempts ──────────────────────────────────────────── */

function FailedAttemptsSection({ failures }: { failures: FailedAttempt[] }) {
  const recent = failures.slice(-6).reverse();
  if (recent.length === 0) return null;
  return (
    <CollapsibleSection title="Recent Failed Attempts" count={recent.length}>
      <div className="drawer-paper-list">
        {recent.map((failure, index) => (
          <ExpandableCard
            key={`${failure.lemma_id}-${index}`}
            tag="failed"
            title={`${humanize(failure.lemma_id)}: ${humanize(truncate(failure.failure_reason, 90))}`}
          >
            <p className="drawer-result-meta"><strong>Lemma:</strong> {humanize(failure.lemma_id)}</p>
            <pre className="drawer-paper-excerpt">{humanize(failure.attempt_text || failure.failure_reason)}</pre>
            <p className="drawer-result-meta"><strong>Failure reason:</strong> {humanize(failure.failure_reason)}</p>
          </ExpandableCard>
        ))}
      </div>
    </CollapsibleSection>
  );
}

/* ── Section: Counterexamples ──────────────────────────────────────────── */

function CounterexamplesSection({ counterexamples }: { counterexamples: Counterexample[] }) {
  if (counterexamples.length === 0) return null;
  return (
    <CollapsibleSection title="Counterexamples" count={counterexamples.length}>
      <div className="drawer-paper-list">
        {counterexamples.slice(0, 6).map((cx, index) => (
          <ExpandableCard
            key={`${cx.lemma_id}-${index}`}
            tag="counter"
            title={`${humanize(cx.lemma_id)}: ${humanize(truncate(cx.counterexample_description, 90))}`}
          >
            <p className="drawer-result-meta"><strong>Lemma:</strong> {humanize(cx.lemma_id)}</p>
            <pre className="drawer-paper-excerpt">{humanize(cx.counterexample_description)}</pre>
            {cx.suggested_refinement && (
              <p className="drawer-result-meta"><strong>Suggested refinement:</strong> {humanize(cx.suggested_refinement)}</p>
            )}
          </ExpandableCard>
        ))}
      </div>
    </CollapsibleSection>
  );
}

/* ── Section: Proof Snapshot ───────────────────────────────────────────── */

function ProofSnapshotSection({ ts }: { ts: NonNullable<Artifacts['theory_state']> }) {
  if (!ts.formal_statement && !ts.assembled_proof && !ts.proof_skeleton) return null;
  return (
    <CollapsibleSection title="Current Proof Snapshot">
      <pre className="drawer-paper-excerpt">
        {truncate(ts.formal_statement || ts.assembled_proof || ts.proof_skeleton || '', 1400)}
      </pre>
    </CollapsibleSection>
  );
}

/* ── Main Component ────────────────────────────────────────────────────── */

export function TheoryDrawerBody({ arts }: TheoryDrawerBodyProps) {
  const ts = arts.theory_state;
  if (!ts) {
    return (
      <div className="drawer-empty-state">
        <span>📐</span>
        <p>The proof hasn't started yet — theory-stage extracts and proof attempts will appear here once the theory agent begins its work.</p>
      </div>
    );
  }

  const openGoalEntries: OpenGoalEntry[] = (ts.open_goals ?? []).map((lemmaId) => ({
    lemmaId,
    statement: ts.lemma_dag?.[lemmaId]?.statement || '',
    verificationMethod: ts.lemma_dag?.[lemmaId]?.verification_method || '',
  }));

  const provenEntries = Object.entries(ts.proven_lemmas ?? {}) as [string, ProofRecord][];

  return (
    <>
      <ResearchGapSection ts={ts} />
      <ExtractedResultsSection results={ts.known_results ?? []} />
      <ProofPlanSection plan={ts.proof_plan ?? []} />
      <OpenGoalsSection goals={openGoalEntries} />
      <ProvenLemmasSection entries={provenEntries} lemmaDag={ts.lemma_dag ?? {}} />
      <FailedAttemptsSection failures={ts.failed_attempts ?? []} />
      <CounterexamplesSection counterexamples={ts.counterexamples ?? []} />
      <ProofSnapshotSection ts={ts} />
    </>
  );
}
