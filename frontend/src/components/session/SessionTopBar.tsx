import { useState, useMemo } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { parseServerTimestamp } from '@/lib/formatters';
import { compactRunMeta } from '@/lib/statusHelpers';
import { useElapsedTimer } from '@/hooks/useElapsedTimer';
import { apiPost } from '@/api/client';
import type { SessionRun, PipelineTask } from '@/types';

function fullSessionName(run: SessionRun): string {
  return run.name || run.input_spec?.query || run.input_spec?.domain || 'Untitled session';
}

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

function formatCompact(n: number): string {
  if (n < 1000) return String(n);
  if (n < 1_000_000) return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0)}K`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

export function SessionTopBar({ run }: SessionTopBarProps) {
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const [isRenaming, setIsRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState('');

  const name = fullSessionName(run);
  const tasks = run.pipeline ?? [];
  const totals = computeTokenUsage(tasks);
  const total = totals.input + totals.output;

  // Live elapsed ticker — only active while the run is running.
  // Uses parseServerTimestamp so naive ISO timestamps from the
  // server (which are UTC) aren't misread as local time.
  const startedAt = useMemo(
    () => parseServerTimestamp(run.started_at),
    [run.started_at]
  );
  const elapsed = useElapsedTimer(run.status === 'running' ? startedAt : null);
  const metaText = compactRunMeta(run, elapsed);
  const statusDotClass = statusDot(run.status);

  const startRename = () => {
    setRenameValue(fullSessionName(run));
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
    <header className="session-topbar" id="session-topbar">
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
            <h2 className="session-topbar-name" id="session-topbar-name" title={name}>
              {name}
            </h2>
            <button
              className="session-topbar-rename-btn"
              id="session-topbar-rename-btn"
              title="Rename session"
              aria-label="Rename session"
              onClick={startRename}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            </button>
          </>
        )}
      </div>

      <div className="session-topbar-footer" id="session-topbar-footer">
        <span className="session-topbar-status" id="run-status-line">
          <span className={`session-topbar-dot ${statusDotClass}`} aria-hidden="true" />
          <span className="session-topbar-status-text">{metaText}</span>
        </span>
        {total > 0 && (
          <span className="session-topbar-tokens" id="token-strip" title={`Input ${totals.input.toLocaleString()} · Output ${totals.output.toLocaleString()}`}>
            <span className="session-topbar-tokens-breakdown">
              {formatCompact(totals.input)} in · {formatCompact(totals.output)} out
            </span>
            <span className="session-topbar-tokens-total">{formatCompact(total)}</span>
          </span>
        )}
      </div>
    </header>
  );
}

function statusDot(status: string): string {
  if (status === 'running') return 'is-running';
  if (status === 'queued') return 'is-queued';
  if (status === 'paused') return 'is-paused';
  if (status === 'pausing') return 'is-pausing';
  if (status === 'resuming') return 'is-resuming';
  if (status === 'completed') return 'is-completed';
  if (status === 'failed') return 'is-failed';
  return 'is-idle';
}
