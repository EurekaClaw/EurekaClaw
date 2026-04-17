import { useCallback, useEffect, useRef, useState } from 'react';
import type { SessionRun } from '@/types';
import { PaperViewer } from './paper-review/PaperViewer';
import { QAChat } from './paper-review/QAChat';
import { usePaperSession } from './paper-review/usePaperSession';

interface PaperPanelProps {
  run: SessionRun | null;
}

const SPLIT_KEY = 'eurekaclaw-review-split';
const MIN_SPLIT = 30;
const MAX_SPLIT = 70;
const DEFAULT_SPLIT = 55;

function loadInitialSplit(): number {
  try {
    const saved = localStorage.getItem(SPLIT_KEY);
    if (!saved) return DEFAULT_SPLIT;
    const parsed = parseFloat(saved);
    if (!Number.isFinite(parsed)) return DEFAULT_SPLIT;
    return Math.min(MAX_SPLIT, Math.max(MIN_SPLIT, parsed));
  } catch {
    return DEFAULT_SPLIT;
  }
}

export function PaperPanel({ run }: PaperPanelProps) {
  // Force the hook (and all downstream state) to reset on session switch.
  return <PaperPanelInner key={run?.run_id ?? '__none__'} run={run} />;
}

function PaperPanelInner({ run }: PaperPanelProps) {
  const session = usePaperSession(run);

  const [splitPct, setSplitPct] = useState(loadInitialSplit);
  const [isDragging, setIsDragging] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Persist split on every change. Covers the mid-drag-unmount edge case
  // that a mouseup-only save would miss; drag-time writes are cheap.
  useEffect(() => {
    try {
      localStorage.setItem(SPLIT_KEY, String(splitPct));
    } catch {
      /* quota / private-mode — preference is ephemeral, no-op */
    }
  }, [splitPct]);

  const handleMouseDown = useCallback(() => setIsDragging(true), []);

  useEffect(() => {
    if (!isDragging) return;
    function onMouseMove(e: MouseEvent) {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const pct = ((e.clientX - rect.left) / rect.width) * 100;
      const clamped = Math.min(MAX_SPLIT, Math.max(MIN_SPLIT, pct));
      setSplitPct(clamped);
    }
    function onMouseUp() {
      setIsDragging(false);
    }
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
    return () => {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
    };
  }, [isDragging]);

  if (!run) {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <p>Launch a session to produce a research paper.</p>
        </div>
      </div>
    );
  }

  // session is non-null whenever run is non-null, but narrow for TS.
  if (!session) {
    return null;
  }

  if (session.mode === 'failed') {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <p>{run.error || 'The session failed before a paper could be generated.'}</p>
        </div>
      </div>
    );
  }

  if (session.mode === 'no-paper') {
    if (run.status === 'running') {
      return (
        <div className="paper-preview">
          <div className="paper-empty-state">
            <div className="paper-progress-dots">
              <span /><span /><span />
            </div>
            <p>Paper will appear once the writer agent completes.</p>
          </div>
        </div>
      );
    }
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <p>No paper generated yet.</p>
        </div>
      </div>
    );
  }

  if (session.mode === 'loading-review') {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <div className="paper-progress-dots">
            <span /><span /><span />
          </div>
          <p>Loading paper review...</p>
        </div>
      </div>
    );
  }

  return (
    <div
      className="paper-review-panel"
      ref={containerRef}
      style={{ userSelect: isDragging ? 'none' : undefined }}
    >
      {session.reviewError ? (
        <div className="paper-review-error-banner">
          Review activation failed: {session.reviewError}
        </div>
      ) : null}

      <div style={{ flex: `0 0 ${splitPct}%`, minWidth: 0, display: 'flex' }}>
        <PaperViewer
          run={session.run}
          paperVersion={session.paperVersion}
          isRewriting={session.isRewriting}
          theoryStatus={session.theoryStatus}
          writerStatus={session.writerStatus}
        />
      </div>

      <div
        className={`review-divider${isDragging ? ' is-dragging' : ''}`}
        onMouseDown={handleMouseDown}
      >
        <div className="review-divider-handle" />
      </div>

      <div style={{ flex: 1, minWidth: 0, display: 'flex' }}>
        <QAChat
          run={session.run}
          messages={session.messages}
          setMessages={session.setMessages}
          isRewriting={session.isRewriting}
          isHistorical={session.isHistorical}
          onAccept={session.onAccept}
          onRewrite={session.onRewrite}
        />
      </div>
    </div>
  );
}
