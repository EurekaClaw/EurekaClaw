import type { Artifacts, SessionRun } from '@/types';

interface IdeationDrawerBodyProps {
  arts: Artifacts;
  run: SessionRun | null;
}

export function IdeationDrawerBody({ arts, run }: IdeationDrawerBodyProps) {
  const brief = arts.research_brief ?? {};
  const direction = brief.selected_direction;
  const dirStr = typeof direction === 'string' ? direction : direction?.title || direction?.direction || '';
  const mode = run?.input_spec?.mode;
  const conj = run?.input_spec?.conjecture || run?.input_spec?.query || '';

  return (
    <>
      <div className="drawer-section">
        <h4>Research direction</h4>
        {dirStr ? (
          <blockquote className="drawer-direction-quote">{dirStr}</blockquote>
        ) : mode === 'detailed' && conj ? (
          <>
            <p className="drawer-muted">Using your conjecture as the research direction.</p>
            <blockquote className="drawer-direction-quote">{conj}</blockquote>
          </>
        ) : (
          <p className="drawer-muted">No direction generated yet — ideation will run after the literature survey completes.</p>
        )}
      </div>
      {brief.domain && (
        <div className="drawer-section">
          <h4>Research domain</h4>
          <p>{brief.domain}</p>
        </div>
      )}
    </>
  );
}
