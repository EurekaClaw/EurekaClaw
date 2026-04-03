import { useState } from 'react';
import type { Artifacts, ResearchDirection, SessionRun } from '@/types';
import { humanize } from '@/lib/formatters';
import { CollapsibleSection } from '@/components/shared/CollapsibleSection';

interface IdeationDrawerBodyProps {
  arts: Artifacts;
  run: SessionRun | null;
}

function truncate(text: string, limit = 140): string {
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text;
}

function directionTitle(direction: ResearchDirection): string {
  const title = direction.title?.trim();
  if (title) return humanize(title);
  const hypothesis = direction.hypothesis?.trim() || '';
  return humanize(truncate(hypothesis || 'Untitled direction', 90));
}

function scoreLabel(value?: number): string | null {
  if (typeof value !== 'number' || Number.isNaN(value)) return null;
  return value.toFixed(2);
}

function DirectionCard({ direction, selected }: { direction: ResearchDirection; selected: boolean }) {
  const [isExpanded, setIsExpanded] = useState(false);
  const hypothesis = direction.hypothesis?.trim() || '';
  const approach = direction.approach_sketch?.trim() || '';
  const novelty = scoreLabel(direction.novelty_score);
  const soundness = scoreLabel(direction.soundness_score);
  const transformative = scoreLabel(direction.transformative_score);
  const composite = scoreLabel(direction.composite_score);

  return (
    <button
      type="button"
      className={`drawer-result-card${isExpanded ? ' is-expanded' : ''}`}
      onClick={() => setIsExpanded((v) => !v)}
    >
      <div className="drawer-result-head">
        <div className="drawer-paper-row">
          <span className="drawer-paper-year">{selected ? 'chosen' : 'idea'}</span>
          <span className="drawer-result-title">{directionTitle(direction)}</span>
        </div>
        <span className="drawer-result-toggle">{isExpanded ? 'Hide' : 'View'}</span>
      </div>
      {isExpanded && (
        <div className="drawer-result-detail">
          {hypothesis && <blockquote className="drawer-direction-quote">{humanize(hypothesis)}</blockquote>}
          {approach && (
            <p className="drawer-result-meta">
              <strong>Approach:</strong> {humanize(approach)}
            </p>
          )}
          {(novelty || soundness || transformative || composite) && (
            <p className="drawer-result-meta">
              <strong>Scores:</strong>{' '}
              {[
                novelty ? `novelty ${novelty}` : null,
                soundness ? `soundness ${soundness}` : null,
                transformative ? `impact ${transformative}` : null,
                composite ? `composite ${composite}` : null,
              ].filter(Boolean).join(' · ')}
            </p>
          )}
        </div>
      )}
    </button>
  );
}

export function IdeationDrawerBody({ arts, run }: IdeationDrawerBodyProps) {
  const brief = arts.research_brief ?? {};
  const direction = brief.selected_direction;
  const directions = brief.directions ?? [];
  const dirStr = direction?.title || direction?.hypothesis || '';
  const mode = run?.input_spec?.mode;
  const conj = run?.input_spec?.conjecture || run?.input_spec?.query || '';
  const selectedDirectionId = direction?.direction_id;

  return (
    <>
      <div className="drawer-section">
        <h4>Research direction</h4>
        {dirStr ? (
          <blockquote className="drawer-direction-quote">{humanize(dirStr)}</blockquote>
        ) : mode === 'detailed' && conj ? (
          <>
            <p className="drawer-muted">Using your conjecture as the research direction.</p>
            <blockquote className="drawer-direction-quote">{conj}</blockquote>
          </>
        ) : (
          <p className="drawer-muted">No direction generated yet — ideation will run after the literature survey completes.</p>
        )}
      </div>
      {directions.length > 0 && (
        <CollapsibleSection title="Generated Directions" count={directions.length}>
          <div className="drawer-paper-list">
            {directions.map((item) => (
              <DirectionCard
                key={item.direction_id}
                direction={item}
                selected={item.direction_id === selectedDirectionId}
              />
            ))}
          </div>
        </CollapsibleSection>
      )}
      {brief.domain && (
        <div className="drawer-section">
          <h4>Research domain</h4>
          <p>{humanize(brief.domain)}</p>
        </div>
      )}
    </>
  );
}
