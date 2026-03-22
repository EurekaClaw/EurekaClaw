import { SessionTopBar } from './SessionTopBar';
import { ProofCtrl } from '@/components/controls/ProofCtrl';
import { FailedSessionNote } from '@/components/controls/FailedSessionNote';
import { WorkspaceSplit } from '@/components/workspace/WorkspaceSplit';
import { GateOverlay } from '@/components/workspace/GateOverlay';
import type { SessionRun } from '@/types';

interface SessionDetailPaneProps {
  run: SessionRun;
  onRestartFast: () => void;
}

export function SessionDetailPane({ run, onRestartFast }: SessionDetailPaneProps) {
  const status = run.status;
  const showCtrl = status === 'running' || status === 'pausing' || status === 'paused' || status === 'resuming';
  const isFailed = status === 'failed';

  return (
    <div className="session-detail-pane" id="session-detail-pane">
      <SessionTopBar run={run} />
      {showCtrl && <ProofCtrl run={run} onRestartFast={onRestartFast} />}
      {isFailed && <FailedSessionNote run={run} />}
      <WorkspaceSplit run={run} />
      <GateOverlay run={run} />
    </div>
  );
}
