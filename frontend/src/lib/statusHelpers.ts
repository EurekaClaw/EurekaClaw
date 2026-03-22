import type { SessionRun, PipelineTask } from '@/types';
import { titleCase, humanize } from './formatters';
import { STAGE_TASK_MAP, INNER_STAGE_LABELS } from './agentManifest';

export function statusClass(status: string): string {
  if (status === 'completed' || status === 'available') return 'status-complete';
  if (status === 'running' || status === 'in_progress' || status === 'configured') return 'status-active';
  if (status === 'failed' || status === 'missing') return 'status-error';
  if (status === 'paused') return 'status-paused';
  if (status === 'pausing') return 'status-pausing';
  if (status === 'resuming') return 'status-resuming';
  if (status === 'optional') return 'status-warning';
  return 'status-idle';
}

export function liveStatusDetail(run: SessionRun | null): string {
  if (!run) return 'Launch a session from the form above.';
  if (run.status === 'queued') return 'Session queued — waiting to start…';
  if (run.status === 'running') {
    const activeTasks = (run.pipeline || []).filter((t) => t.status === 'in_progress');
    if (activeTasks.length) {
      return `Running: ${activeTasks.map((t) => titleCase(t.name)).join(', ')}`;
    }
    const elapsed = run.started_at
      ? Math.floor((Date.now() - new Date(run.started_at).getTime()) / 1000)
      : 0;
    return `Running${elapsed ? ` · ${elapsed}s elapsed` : ''}`;
  }
  if (run.status === 'completed') {
    const dir = run.output_dir ? ` → ${run.output_dir}` : '';
    return `Completed${dir}`;
  }
  if (run.status === 'paused') {
    return 'Proof paused at checkpoint — click Resume to continue, or use the Copy command button.';
  }
  if (run.status === 'failed') return `Failed: ${run.error || 'unknown error'}`;
  return `Run ${run.run_id.slice(0, 8)}`;
}

export function getActiveOuterStage(pipeline: PipelineTask[]): string | null {
  if (!pipeline || !pipeline.length) return null;
  const running = pipeline.find((t) => t.status === 'in_progress' || t.status === 'running');
  if (running) return STAGE_TASK_MAP[running.name] ?? null;
  const done = pipeline.filter((t) => t.status === 'completed');
  if (done.length) return STAGE_TASK_MAP[done[done.length - 1].name] ?? null;
  return null;
}

export function friendlyInnerStage(rawStage: string): string | null {
  if (!rawStage) return null;
  return (
    INNER_STAGE_LABELS[rawStage] ||
    humanize(rawStage)
      .replace(/Agent$/, '')
      .replace(/([A-Z])/g, ' $1')
      .trim()
      .toLowerCase()
  );
}
