import type { SessionRun } from '@/types';
import { titleCase } from '@/lib/formatters';

interface PaperPanelProps {
  run: SessionRun | null;
}

export function PaperPanel({ run }: PaperPanelProps) {
  const theoryState = run?.artifacts?.theory_state;
  const result = run?.result;
  const title =
    run?.artifacts?.research_brief?.selected_direction
      ? (typeof run.artifacts.research_brief.selected_direction === 'string'
          ? run.artifacts.research_brief.selected_direction
          : (run.artifacts.research_brief.selected_direction as { title?: string }).title ?? 'EurekaClaw Autonomous Research System')
      : 'EurekaClaw Autonomous Research System';
  const paperText = result?.latex_paper || '';

  let summary = 'Launch a session to produce a real paper draft and final run summary.';
  if (run?.status === 'completed') {
    summary = paperText
      ? `${paperText.slice(0, 280)}...`
      : 'The run completed and output artifacts are available, but no paper text was returned.';
  } else if (run?.status === 'running') {
    summary = 'The writer surface will populate as the pipeline produces theory and experiment artifacts.';
  } else if (run?.status === 'failed') {
    summary = run.error || 'The run failed before a paper could be generated.';
  }

  return (
    <div className="paper-preview" id="paper-preview">
      <div className="paper-sheet">
        <p className="paper-title">{title}</p>
        <p className="paper-meta">Status: {titleCase(run?.status || 'not started')}</p>
        <p>{summary}</p>
        {theoryState && (
          <p className="paper-meta">
            Proven lemmas: {Object.keys(theoryState.proven_lemmas || {}).length} |
            Open goals: {(theoryState.open_goals || []).length}
          </p>
        )}
      </div>
    </div>
  );
}
