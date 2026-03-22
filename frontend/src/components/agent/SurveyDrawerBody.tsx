import type { Artifacts } from '@/types';
import { humanize } from '@/lib/formatters';

interface SurveyDrawerBodyProps {
  arts: Artifacts;
}

export function SurveyDrawerBody({ arts }: SurveyDrawerBodyProps) {
  const brief = arts.research_brief ?? {};
  // Papers live in bibliography.papers; ResearchBrief doesn't have a papers field
  const papers = arts.bibliography?.papers ?? [];
  const problems = brief.open_problems ?? [];
  // Backend field is key_mathematical_objects (list of strings)
  const keyObjects = brief.key_mathematical_objects ?? [];

  if (!papers.length && !problems.length) {
    return (
      <div className="drawer-empty-state">
        <span>📚</span>
        <p>Survey hasn't run yet — results will appear here once the literature scan completes.</p>
      </div>
    );
  }

  return (
    <>
      {papers.length > 0 && (
        <div className="drawer-section">
          <h4>Papers surveyed</h4>
          <div className="drawer-paper-list">
            {papers.slice(0, 15).map((p, i) => (
              <div key={i} className="drawer-paper-row">
                <span className="drawer-paper-year">{String(p.year || '—')}</span>
                <span>{humanize(p.title || 'Untitled')}</span>
              </div>
            ))}
            {papers.length > 15 && <p className="drawer-more">and {papers.length - 15} more papers…</p>}
          </div>
        </div>
      )}
      {problems.length > 0 && (
        <div className="drawer-section">
          <h4>Open problems identified</h4>
          <ul className="drawer-problems-list">
            {problems.map((p, i) => (
              <li key={i}>{humanize(String(p))}</li>
            ))}
          </ul>
        </div>
      )}
      {keyObjects.length > 0 && (
        <div className="drawer-section">
          <h4>Key mathematical objects</h4>
          <div className="drawer-tags-row">
            {keyObjects.slice(0, 12).map((obj, i) => (
              <span key={i} className="drawer-object-tag">{humanize(String(obj))}</span>
            ))}
          </div>
        </div>
      )}
    </>
  );
}
