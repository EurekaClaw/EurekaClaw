import type { SessionRun } from '@/types';

interface WriterDrawerBodyProps {
  run: SessionRun | null;
}

export function WriterDrawerBody({ run }: WriterDrawerBodyProps) {
  const paper = run?.result?.latex_paper || '';
  const outputDir = run?.output_dir || '';

  if (!paper && !outputDir) {
    return (
      <div className="drawer-empty-state">
        <span>✍️</span>
        <p>The paper will appear here once the writer agent completes its draft.</p>
      </div>
    );
  }

  const words = paper ? paper.split(/\s+/).filter(Boolean).length : 0;
  const preview = paper ? paper.slice(0, 800) : '';

  return (
    <>
      {words > 0 && (
        <div className="drawer-section">
          <h4>Draft overview</h4>
          <p className="drawer-word-count">{words.toLocaleString()} words</p>
          {outputDir && (
            <p className="drawer-muted">Saved to: <code>{outputDir}</code></p>
          )}
        </div>
      )}
      {preview && (
        <div className="drawer-section">
          <h4>Paper excerpt</h4>
          <pre className="drawer-paper-excerpt">
            {preview}{paper.length > 800 ? '\n…' : ''}
          </pre>
        </div>
      )}
    </>
  );
}
