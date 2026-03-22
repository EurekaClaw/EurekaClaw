import type { PipelineTask, SessionRun } from '@/types';
import { agentNarrativeLine } from '@/lib/agentManifest';
import type { AgentManifestEntry } from '@/lib/agentManifest';

interface AgentStepCardProps {
  manifest: AgentManifestEntry;
  task: PipelineTask | undefined;
  run: SessionRun | null;
  taskMap: Map<string, PipelineTask>;
  onClick: (role: string) => void;
}

export function AgentStepCard({ manifest, task, run, taskMap, onClick }: AgentStepCardProps) {
  const st = task?.status || 'pending';
  const isDone = st === 'completed' || st === 'skipped';
  const isActive = st === 'in_progress' || st === 'awaiting_gate';
  const isFailed = st === 'failed';
  const narrative = agentNarrativeLine(manifest.role, taskMap, run);
  const stateClass = isDone ? ' is-done' : isActive ? ' is-active' : isFailed ? ' is-failed' : '';
  const statusLabel = isDone ? 'done' : isActive ? 'active' : isFailed ? 'failed' : 'pending';

  return (
    <button
      className={`agent-step-card${stateClass}`}
      data-agent-role={manifest.role}
      aria-label={`View ${manifest.name} details`}
      onClick={() => onClick(manifest.role)}
    >
      <span className="agent-step-icon" aria-hidden="true">{manifest.icon}</span>
      <div className="agent-step-body">
        <span className="agent-step-name">{manifest.name}</span>
        <span className="agent-step-summary">{narrative}</span>
      </div>
      <span className={`agent-step-badge badge-${statusLabel}`}>{statusLabel}</span>
    </button>
  );
}
