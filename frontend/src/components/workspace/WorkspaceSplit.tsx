import { AgentTrack } from './AgentTrack';
import { WorkspaceTabs } from './WorkspaceTabs';
import type { SessionRun } from '@/types';

interface WorkspaceSplitProps {
  run: SessionRun | null;
}

export function WorkspaceSplit({ run }: WorkspaceSplitProps) {
  return (
    <div className="workspace-split" id="workspace-split">
      <AgentTrack run={run} />
      <WorkspaceTabs run={run} />
    </div>
  );
}
