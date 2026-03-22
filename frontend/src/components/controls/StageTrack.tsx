import type { SessionRun } from '@/types';
import { getActiveOuterStage } from '@/lib/statusHelpers';
import { STAGE_TASK_MAP } from '@/lib/agentManifest';

interface StageTrackProps {
  run: SessionRun | null;
}

const STAGE_ORDER = ['survey', 'ideation', 'theory', 'experiment', 'writer'] as const;
const STAGE_LABELS: Record<string, { emoji: string; label: string }> = {
  survey:     { emoji: '📚', label: 'Reading' },
  ideation:   { emoji: '💡', label: 'Ideas' },
  theory:     { emoji: '📐', label: 'Proof' },
  experiment: { emoji: '🧪', label: 'Testing' },
  writer:     { emoji: '✍️', label: 'Writing' },
};

export function StageTrack({ run }: StageTrackProps) {
  const pipeline = run?.pipeline ?? [];
  const activeOuter = getActiveOuterStage(pipeline);
  const isPaused = run?.status === 'paused' || run?.status === 'pausing';
  const activeIdx = STAGE_ORDER.indexOf(activeOuter as (typeof STAGE_ORDER)[number]);

  return (
    <div className="proof-ctrl-track" id="proof-ctrl-track" aria-label="Research pipeline progress">
      {STAGE_ORDER.map((stageKey, i) => {
        const tasksForStage = pipeline.filter((t) => STAGE_TASK_MAP[t.name] === stageKey);
        const isCompleted = tasksForStage.length > 0 && tasksForStage.every((t) => t.status === 'completed');
        const isActive = activeOuter === stageKey;
        const isPausedHere = isPaused && stageKey === 'theory';
        const stageClass = isCompleted ? ' is-done' : isPausedHere ? ' is-paused' : isActive ? ' is-active' : '';
        const connectorFilled = i < STAGE_ORDER.length - 1 &&
          (i < activeIdx || (activeIdx < 0 && pipeline.some((t) => t.status === 'completed')));

        return (
          <span key={stageKey} style={{ display: 'contents' }}>
            <div className={`proof-ctrl-track-stage${stageClass}`} data-stage={stageKey}>
              <span className="pct-node" aria-hidden="true">{STAGE_LABELS[stageKey]?.emoji}</span>
              <span className="pct-label">{STAGE_LABELS[stageKey]?.label}</span>
            </div>
            {i < STAGE_ORDER.length - 1 && (
              <span className={`pct-connector${connectorFilled ? ' is-filled' : ''}`} aria-hidden="true" />
            )}
          </span>
        );
      })}
    </div>
  );
}
