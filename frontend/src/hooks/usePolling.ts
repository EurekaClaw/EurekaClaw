import { useEffect, useRef, useCallback } from 'react';
import { apiGet } from '@/api/client';
import { useSessionStore } from '@/store/sessionStore';
import { useUiStore } from '@/store/uiStore';
import type { SessionRun } from '@/types';

const POLL_INTERVAL_FAST_MS = 500;
const POLL_INTERVAL_ACTIVE_MS = 1200;
const POLL_INTERVAL_IDLE_MS = 3000;

interface RunsResponse {
  runs: SessionRun[];
}

function computeInterval(sessions: SessionRun[], isPausingRequested: boolean): number {
  const hasTransient = sessions.some((s) => s.status === 'pausing' || s.status === 'resuming');
  if (hasTransient || isPausingRequested) return POLL_INTERVAL_FAST_MS;
  const hasLive = sessions.some((s) => s.status === 'running' || s.status === 'queued');
  return hasLive ? POLL_INTERVAL_ACTIVE_MS : POLL_INTERVAL_IDLE_MS;
}

export function usePolling() {
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const intervalRef = useRef(POLL_INTERVAL_ACTIVE_MS);
  const errorsRef = useRef(0);
  const { setSessions, currentRunId, isPausingRequested } = useSessionStore();
  const { activeWsTab, setActiveWsTab } = useUiStore();
  const prevRunRef = useRef<SessionRun | null>(null);

  const tick = useCallback(async () => {
    try {
      const data = await apiGet<RunsResponse>('/api/runs');
      errorsRef.current = 0;
      const sessions = data.runs || [];
      setSessions(sessions);

      // Auto-tab switching
      const current = currentRunId ? sessions.find((s) => s.run_id === currentRunId) : null;
      if (current) {
        const prev = prevRunRef.current;
        const theoryTask = current.pipeline?.find((t) => t.name === 'theory' || t.agent_role === 'theory');
        const prevTheoryTask = prev?.pipeline?.find((t) => t.name === 'theory' || t.agent_role === 'theory');
        const wasRunning = prevTheoryTask?.status === 'in_progress';
        const nowDone = theoryTask?.status === 'completed';
        if (wasRunning && nowDone && activeWsTab === 'live') setActiveWsTab('proof');
        if (prev?.status !== 'completed' && current.status === 'completed' && activeWsTab === 'live') {
          setActiveWsTab('paper');
        }
        prevRunRef.current = current;
      }

      const newInterval = computeInterval(sessions, isPausingRequested);
      if (newInterval !== intervalRef.current) {
        intervalRef.current = newInterval;
        if (timerRef.current) {
          clearInterval(timerRef.current);
          timerRef.current = setInterval(tick, newInterval);
        }
      }
    } catch {
      errorsRef.current += 1;
    }
  }, [setSessions, currentRunId, isPausingRequested, activeWsTab, setActiveWsTab]);

  const startFast = useCallback(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    intervalRef.current = POLL_INTERVAL_FAST_MS;
    errorsRef.current = 0;
    void tick();
    timerRef.current = setInterval(tick, POLL_INTERVAL_FAST_MS);
  }, [tick]);

  useEffect(() => {
    errorsRef.current = 0;
    void tick();
    timerRef.current = setInterval(tick, intervalRef.current);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [tick]);

  return { restartFast: startFast, pollErrors: errorsRef };
}
