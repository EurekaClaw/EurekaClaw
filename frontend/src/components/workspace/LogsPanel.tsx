import type { SessionRun, PipelineTask } from '@/types';
import { formatLocalTimestamp, parseServerTimestamp } from '@/lib/formatters';
import { AGENT_MANIFEST, STAGE_TASK_MAP } from '@/lib/agentManifest';
import { titleCase } from '@/lib/formatters';
import { useSessionStore } from '@/store/sessionStore';

interface LogItem {
  time: string | undefined;
  message: string;
  tone: string;
}

interface LogsPanelProps {
  run: SessionRun | null;
}

const LOGS_PER_PAGE = 6;

function humanizeLogMessage(taskName: string, eventType: string, detail: string): string {
  const name = taskName || '';
  const role = STAGE_TASK_MAP[name] || name;
  const manifest = AGENT_MANIFEST.find((a) => a.role === role);
  const agentName = manifest?.name || titleCase(name);

  if (eventType === 'started') {
    const starts: Record<string, string> = {
      survey: '📚 Literature survey started — scanning recent papers',
      ideation: '💡 Idea generation started — exploring research directions',
      theory: '📐 Theorem proving started — architecting the proof',
      experiment: '🧪 Validation started — running numerical experiments',
      writer: '✍️ Paper writing started — composing the manuscript',
      direction_selection_gate: '🧭 Selecting research direction…',
      theory_review_gate: '🔍 Theory review gate reached',
      final_review_gate: '✅ Final review gate reached',
    };
    return starts[name] || `${agentName} started`;
  }
  if (eventType === 'completed') {
    const done: Record<string, string> = {
      survey: '📚 Literature survey complete — research brief ready',
      ideation: '💡 Directions generated — research direction selected',
      theory: '📐 Proof complete — theorem sketch ready for review',
      experiment: '🧪 Experiments finished — bounds verified',
      writer: '✍️ Paper draft complete',
      direction_selection_gate: '🧭 Direction confirmed',
      theory_review_gate: '🔍 Theory reviewed — proceeding to validation',
      final_review_gate: '✅ Final review complete',
    };
    return done[name] || `${agentName} complete`;
  }
  if (eventType === 'error') {
    return `⚠ ${agentName} encountered an issue${detail ? ': ' + detail : ''}`;
  }
  return `${agentName} ${eventType}`;
}

function buildLogItems(run: SessionRun | null, tasks: PipelineTask[]): LogItem[] {
  const items: LogItem[] = [];
  if (run?.created_at) {
    items.push({ time: run.created_at, message: '🔬 Research session created', tone: '' });
  }
  tasks.forEach((task) => {
    if (task.started_at) {
      items.push({ time: task.started_at, message: humanizeLogMessage(task.name, 'started', ''), tone: '' });
    }
    if (task.completed_at && task.status !== 'failed') {
      items.push({ time: task.completed_at, message: humanizeLogMessage(task.name, 'completed', ''), tone: '' });
    }
    if (task.error_message) {
      items.push({
        time: task.completed_at || task.started_at || run?.created_at,
        message: humanizeLogMessage(task.name, 'error', task.error_message),
        tone: 'warning',
      });
    }
  });
  return items.sort((a, b) => {
    const tA = parseServerTimestamp(a.time)?.getTime() ?? 0;
    const tB = parseServerTimestamp(b.time)?.getTime() ?? 0;
    return tA - tB;
  });
}

export function LogsPanel({ run }: LogsPanelProps) {
  const currentLogPage = useSessionStore((s) => s.currentLogPage);
  const setCurrentLogPage = useSessionStore((s) => s.setCurrentLogPage);

  const tasks = run?.pipeline ?? [];
  const items = buildLogItems(run, tasks);

  if (!items.length) {
    return (
      <div className="log-stream" id="log-stream">
        <div className="log-line">
          <span className="mono-label">--:--:--</span>
          <p>Run events will appear here once a session starts.</p>
        </div>
      </div>
    );
  }

  const totalPages = Math.max(1, Math.ceil(items.length / LOGS_PER_PAGE));
  const safePage = Math.min(currentLogPage, totalPages);
  const startIndex = (safePage - 1) * LOGS_PER_PAGE;
  const visible = items.slice(startIndex, startIndex + LOGS_PER_PAGE);

  return (
    <>
      <div className="log-stream" id="log-stream">
        {visible.map((item, i) => (
          <div key={i} className={`log-line ${item.tone}`}>
            <span className="mono-label">{formatLocalTimestamp(item.time)}</span>
            <p>{item.message}</p>
          </div>
        ))}
      </div>
      {totalPages > 1 && (
        <div className="log-pagination" id="log-pagination">
          <button
            type="button"
            className="ghost-btn"
            disabled={safePage === 1}
            onClick={() => setCurrentLogPage(safePage - 1)}
          >
            Previous
          </button>
          <span className="log-pagination-meta">Page {safePage} / {totalPages}</span>
          <button
            type="button"
            className="ghost-btn"
            disabled={safePage === totalPages}
            onClick={() => setCurrentLogPage(safePage + 1)}
          >
            Next
          </button>
        </div>
      )}
    </>
  );
}
