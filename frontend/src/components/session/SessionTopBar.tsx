import { useState } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { truncateSessionName } from '@/lib/formatters';
import { statusClass, liveStatusDetail } from '@/lib/statusHelpers';
import { titleCase } from '@/lib/formatters';
import { apiPost } from '@/api/client';
import type { SessionRun, PipelineTask } from '@/types';

interface SessionTopBarProps {
  run: SessionRun;
}

function computeTokenUsage(tasks: PipelineTask[]) {
  return tasks.reduce(
    (acc, task) => {
      const usage = task?.outputs?.token_usage ?? {};
      acc.input += Number(usage.input || 0);
      acc.output += Number(usage.output || 0);
      return acc;
    },
    { input: 0, output: 0 }
  );
}

export function SessionTopBar({ run }: SessionTopBarProps) {
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const [isRenaming, setIsRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState('');

  const name = run.name || truncateSessionName(run);
  const tasks = run.pipeline ?? [];
  const totals = computeTokenUsage(tasks);
  const total = totals.input + totals.output;
  const status = run.status;
  const detail = liveStatusDetail(run);

  const startRename = () => {
    setRenameValue(run.name || truncateSessionName(run));
    setIsRenaming(true);
  };

  const commitRename = async () => {
    const val = renameValue.trim();
    setIsRenaming(false);
    if (!val || !run.run_id) return;
    try {
      await apiPost(`/api/runs/${run.run_id}/rename`, { name: val });
      setSessions(sessions.map((s) => (s.run_id === run.run_id ? { ...s, name: val } : s)));
    } catch {
      // silently ignore
    }
  };

  return (
    <>
      <div className="session-topbar">
        <div className="session-topbar-identity">
          {isRenaming ? (
            <input
              className="session-topbar-name-input"
              id="session-topbar-name-input"
              value={renameValue}
              maxLength={80}
              placeholder="Session name…"
              autoFocus
              onChange={(e) => setRenameValue(e.target.value)}
              onBlur={() => void commitRename()}
              onKeyDown={(e) => {
                if (e.key === 'Enter') e.currentTarget.blur();
                if (e.key === 'Escape') setIsRenaming(false);
              }}
            />
          ) : (
            <>
              <span className="session-topbar-name" id="session-topbar-name">{name}</span>
              <button className="session-topbar-rename-btn" id="session-topbar-rename-btn" title="Rename session" aria-label="Rename session" onClick={startRename}>
                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
              </button>
            </>
          )}
        </div>
        <div className="session-topbar-right">
          <span className={`status-pill ${statusClass(status)}`} id="run-status-pill">
            {titleCase(status)}
          </span>
        </div>
      </div>

      <div className="session-status-row">
        <p className="session-meta-text" id="run-meta">{detail}</p>
        <div className="token-strip" id="token-strip">
          <span className="token-label">Tokens</span>
          <span className="token-value" id="token-usage-value">{total.toLocaleString()} total</span>
          <span className="token-breakdown" id="token-usage-breakdown">
            Input {totals.input.toLocaleString()} · Output {totals.output.toLocaleString()}
          </span>
        </div>
      </div>
    </>
  );
}
