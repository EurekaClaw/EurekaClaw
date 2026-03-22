import { useUiStore } from '@/store/uiStore';
import { AGENT_MANIFEST } from '@/lib/agentManifest';
import { AgentStepCard } from './AgentStepCard';
import type { SessionRun } from '@/types';

interface AgentTrackProps {
  run: SessionRun | null;
}

export function AgentTrack({ run }: AgentTrackProps) {
  const setOpenAgentDrawerRole = useUiStore((s) => s.setOpenAgentDrawerRole);
  const pipeline = run?.pipeline ?? [];
  const taskMap = new Map(pipeline.map((t) => [t.agent_role, t]));

  return (
    <nav className="agent-track-col" id="agent-track" aria-label="Research agents">
      {AGENT_MANIFEST.map((manifest) => (
        <AgentStepCard
          key={manifest.role}
          manifest={manifest}
          task={taskMap.get(manifest.role)}
          run={run}
          taskMap={taskMap}
          onClick={(role) => setOpenAgentDrawerRole(role)}
        />
      ))}
    </nav>
  );
}
