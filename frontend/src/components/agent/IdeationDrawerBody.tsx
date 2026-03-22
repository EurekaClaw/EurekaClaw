import type { Artifacts, SessionRun } from '@/types';
import { humanize } from '@/lib/formatters';

interface IdeationDrawerBodyProps {
  arts: Artifacts;
  run: SessionRun | null;
}

export function IdeationDrawerBody({ arts, run }: IdeationDrawerBodyProps) {
  const brief = arts.research_brief ?? {};
  // selected_direction is a ResearchDirection object (title + hypothesis) from the backend
  const direction = brief.selected_direction;
  const dirStr = direction?.title || direction?.hypothesis || '';
  const mode = run?.input_spec?.mode;
  const conj = run?.input_spec?.conjecture || run?.input_spec?.query || '';

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
      {brief.domain && (
        <div className="drawer-section">
          <h4>Research domain</h4>
          <p>{humanize(brief.domain)}</p>
        </div>
      )}
    </>
  );
}
