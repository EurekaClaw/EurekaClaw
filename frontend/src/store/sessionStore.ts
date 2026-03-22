import { create } from 'zustand';
import type { SessionRun } from '@/types';

const RUN_ID_KEY = 'eurekaclaw_current_run';
const SESSIONS_KEY = 'eurekaclaw_sessions';

function loadRunId(): string | null {
  try { return localStorage.getItem(RUN_ID_KEY) || null; } catch { return null; }
}

function persistRunId(id: string | null) {
  try {
    if (id) localStorage.setItem(RUN_ID_KEY, id);
    else localStorage.removeItem(RUN_ID_KEY);
  } catch { /* ignore */ }
}

function loadSessions(): SessionRun[] {
  try {
    const raw = localStorage.getItem(SESSIONS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function persistSessions(sessions: SessionRun[]) {
  try { localStorage.setItem(SESSIONS_KEY, JSON.stringify(sessions)); } catch { /* ignore */ }
}

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
  sessions: loadSessions(),
  currentRunId: loadRunId(),
  currentLogPage: 1,
  isPausingRequested: false,
  pauseRequestedAt: null,

  setSessions: (sessions) => {
    // Merge: server sessions take priority; keep local-only sessions that server doesn't know about
    const serverIds = new Set(sessions.map((s) => s.run_id));
    const localOnly = get().sessions.filter((s) => !serverIds.has(s.run_id));
    const merged = [...sessions, ...localOnly];
    set({ sessions: merged });
    persistSessions(merged);
  },
  setCurrentRunId: (id) => { set({ currentRunId: id }); persistRunId(id); },
  setCurrentLogPage: (page) => set({ currentLogPage: page }),
  setIsPausingRequested: (val) => set({ isPausingRequested: val }),
  setPauseRequestedAt: (date) => set({ pauseRequestedAt: date }),

  currentRun: () => {
    const { sessions, currentRunId } = get();
    if (!currentRunId) return null;
    return sessions.find((s) => s.run_id === currentRunId) ?? null;
  },
}));
