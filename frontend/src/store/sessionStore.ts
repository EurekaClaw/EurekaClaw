import { create } from 'zustand';
import type { SessionRun } from '@/types';

interface SessionState {
  sessions: SessionRun[];
  currentRunId: string | null;
  currentLogPage: number;
  isPausingRequested: boolean;
  pauseRequestedAt: Date | null;

  setSessions: (sessions: SessionRun[]) => void;
  setCurrentRunId: (id: string | null) => void;
  setCurrentLogPage: (page: number) => void;
  setIsPausingRequested: (val: boolean) => void;
  setPauseRequestedAt: (date: Date | null) => void;
  currentRun: () => SessionRun | null;
}

export const useSessionStore = create<SessionState>((set, get) => ({
  sessions: [],
  currentRunId: null,
  currentLogPage: 1,
  isPausingRequested: false,
  pauseRequestedAt: null,

  setSessions: (sessions) => set({ sessions }),
  setCurrentRunId: (id) => set({ currentRunId: id }),
  setCurrentLogPage: (page) => set({ currentLogPage: page }),
  setIsPausingRequested: (val) => set({ isPausingRequested: val }),
  setPauseRequestedAt: (date) => set({ pauseRequestedAt: date }),

  currentRun: () => {
    const { sessions, currentRunId } = get();
    if (!currentRunId) return null;
    return sessions.find((s) => s.run_id === currentRunId) ?? null;
  },
}));
