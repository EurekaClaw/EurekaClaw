import type { Artifacts } from '@/types';
import { humanize } from '@/lib/formatters';

interface ExperimentDrawerBodyProps {
  arts: Artifacts;
}

export function ExperimentDrawerBody({ arts }: ExperimentDrawerBodyProps) {
  const er = arts.experiment_result;

  if (!er) {
    return (
      <div className="drawer-empty-state">
        <span>🧪</span>
        <p>Experimental results will appear here after the validation stage runs.</p>
      </div>
    );
  }

  const bounds = er.bounds ?? [];
  const score = er.alignment_score;

  return (
    <>
      <div className="drawer-section">
        <h4>Alignment score</h4>
        <div className="drawer-alignment-row">
          <span className="drawer-alignment-score">
            {score != null ? `${(score * 100).toFixed(0)}%` : '—'}
          </span>
          <span className="drawer-muted">1.0 = theory matches simulation perfectly</span>
        </div>
      </div>
      {bounds.length > 0 && (
        <div className="drawer-section">
          <h4>Bounds verification</h4>
          <table className="drawer-bounds-table">
            <thead>
              <tr><th>Bound</th><th>Theoretical</th><th>Empirical</th><th /></tr>
            </thead>
            <tbody>
              {bounds.map((b, i) => (
                <tr key={i}>
                  <td>{humanize(b.name || '—')}</td>
                  <td>{String(b.theoretical ?? '—')}</td>
                  <td>{String(b.empirical ?? '—')}</td>
                  <td className={b.aligned ? 'drawer-bounds-pass' : 'drawer-bounds-fail'}>
                    {b.aligned == null ? '?' : b.aligned ? '✓' : '✗'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {er.description && (
        <div className="drawer-section">
          <h4>Description</h4>
          <p>{humanize(er.description)}</p>
        </div>
      )}
    </>
  );
}
