interface RewriteOverlayProps {
  theoryStatus: string;
  writerStatus: string;
}

export function RewriteOverlay({ theoryStatus, writerStatus }: RewriteOverlayProps) {
  const theoryDone = theoryStatus === 'completed' || theoryStatus === 'failed';
  const writerActive = theoryDone && (writerStatus === 'in_progress' || writerStatus === 'running');

  return (
    <div className="rewrite-overlay">
      <div className="rewrite-overlay-content">
        <div className="rewrite-spinner" />
        <div className="rewrite-title">Rewriting paper...</div>
        <div className="rewrite-desc">
          Incorporating your feedback into the proof and regenerating the paper.
        </div>
        <div className="rewrite-steps">
          <div className="rewrite-step">
            {theoryDone ? (
              <div className="rewrite-step-done">✓</div>
            ) : (
              <div className="rewrite-step-spinner" />
            )}
            <div>
              <div className={`rewrite-step-name${!theoryDone ? ' rewrite-step-name--active' : ''}`}>
                Theory Agent
              </div>
              <div className="rewrite-step-detail">
                {theoryDone ? 'Done' : 'Re-proving with feedback...'}
              </div>
            </div>
          </div>
          <div className={`rewrite-step${!theoryDone ? ' rewrite-step--pending' : ''}`}>
            {writerActive ? (
              <div className="rewrite-step-spinner" />
            ) : writerStatus === 'completed' ? (
              <div className="rewrite-step-done">✓</div>
            ) : (
              <div className="rewrite-step-dot">
                <div className="rewrite-step-dot-inner" />
              </div>
            )}
            <div>
              <div className={`rewrite-step-name${writerActive ? ' rewrite-step-name--active' : ''}`}>
                Writer Agent
              </div>
              <div className="rewrite-step-detail">
                {writerActive ? 'Generating paper...' : writerStatus === 'completed' ? 'Done' : 'Waiting for theory...'}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
