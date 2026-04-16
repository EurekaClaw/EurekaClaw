import { useState, useEffect, useCallback, useRef } from 'react';
import { apiGet, apiPost } from '@/api/client';
import { PaperViewer } from './PaperViewer';
import { QAChat } from './QAChat';
import type { SessionRun, QAMessage } from '@/types';

interface PaperReviewPanelProps {
  run: SessionRun;
}

interface HistoryResponse {
  messages: QAMessage[];
}

const SPLIT_KEY = 'eurekaclaw-review-split';
const MIN_SPLIT = 30;
const MAX_SPLIT = 70;

export function PaperReviewPanel({ run }: PaperReviewPanelProps) {
  const [messages, setMessages] = useState<QAMessage[]>([]);
  const [splitPct, setSplitPct] = useState(() => {
    const saved = localStorage.getItem(SPLIT_KEY);
    return saved ? Number(saved) : 55;
  });
  const [isDragging, setIsDragging] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Determine rewrite state from pipeline
  const theoryTask = run.pipeline?.find((t) => t.name === 'theory');
  const writerTask = run.pipeline?.find((t) => t.name === 'writer');
  const isRewriting =
    theoryTask?.status === 'in_progress' ||
    theoryTask?.status === 'running' ||
    theoryTask?.status === 'pending' ||
    writerTask?.status === 'in_progress' ||
    writerTask?.status === 'running' ||
    writerTask?.status === 'pending' ||
    false;

  // Derive paper version from rewrite system messages in history
  const rewriteCount = messages.filter(
    (m) => m.role === 'system' && m.content.startsWith('↻')
  ).length;
  const paperVersion = 1 + rewriteCount;

  // Load history on mount or run change — always reset to avoid stale state
  useEffect(() => {
    void (async () => {
      try {
        const data = await apiGet<HistoryResponse>(`/api/runs/${run.run_id}/paper-qa/history`);
        setMessages(data.messages ?? []);
      } catch {
        setMessages([]);
      }
    })();
  }, [run.run_id]);

  // Accept paper
  const handleAccept = useCallback(async () => {
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/paper_qa`, { action: 'no', question: '' });
    } catch (e) {
      console.error('Failed to accept paper:', e);
    }
  }, [run.run_id]);

  // Rewrite paper
  const handleRewrite = useCallback(async (prompt: string) => {
    const sysMsg: QAMessage = {
      role: 'system',
      content: `↻ Rewrite requested: "${prompt}"`,
      ts: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, sysMsg]);
    try {
      await apiPost(`/api/runs/${run.run_id}/gate/paper_qa`, {
        action: 'rewrite',
        question: prompt,
      });
    } catch (e) {
      console.error('Failed to trigger rewrite:', e);
    }
  }, [run.run_id]);

  // Resizable divider drag handling
  const handleMouseDown = useCallback(() => {
    setIsDragging(true);
  }, []);

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
      localStorage.setItem(SPLIT_KEY, String(splitPct));
    }

    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
    return () => {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
    };
  }, [isDragging, splitPct]);

  return (
    <div
      className="paper-review-panel"
      ref={containerRef}
      style={{ userSelect: isDragging ? 'none' : undefined }}
    >
      <div style={{ flex: `0 0 ${splitPct}%`, minWidth: 0, display: 'flex' }}>
        <PaperViewer
          run={run}
          paperVersion={paperVersion}
          isRewriting={isRewriting}
          theoryStatus={theoryTask?.status || 'pending'}
          writerStatus={writerTask?.status || 'pending'}
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
          run={run}
          messages={messages}
          setMessages={setMessages}
          isRewriting={isRewriting}
          onAccept={handleAccept}
          onRewrite={handleRewrite}
        />
      </div>
    </div>
  );
}
