import { useState, useEffect, useCallback } from 'react';
import type { SessionRun, QAMessage } from '@/types';
import { apiGet, apiPost } from '@/api/client';
import { PaperViewer } from './paper-review/PaperViewer';
import { QAChat } from './paper-review/QAChat';

interface PaperPanelProps {
  run: SessionRun | null;
}

interface HistoryResponse {
  messages: QAMessage[];
}

/**
 * Unified Paper panel — flat layout with PDF/LaTeX viewer and inline QA.
 *
 * For completed sessions: shows paper preview + QA chat side by side.
 * For running/pending: shows progress placeholder.
 * No separate "Review Paper" button needed — the review is always available.
 */
export function PaperPanel({ run }: PaperPanelProps) {
  const [messages, setMessages] = useState<QAMessage[]>([]);
  const [reviewStatus, setReviewStatus] = useState<'idle' | 'loading' | 'ready' | 'failed'>('idle');

  const isCompleted = run?.status === 'completed';
  const isRunning = run?.status === 'running';
  const isFailed = run?.status === 'failed';
  const writerTask = run?.pipeline?.find((t) => t.name === 'writer');
  const hasPaper = !!(
    (writerTask?.outputs?.latex_paper) ||
    run?.result?.latex_paper
  );

  // Activate review mode (load bus on backend) when completed session has a paper
  useEffect(() => {
    if (!isCompleted || !hasPaper || !run?.run_id || reviewStatus !== 'idle') return;
    setReviewStatus('loading');
    void (async () => {
      try {
        await apiPost(`/api/runs/${run.run_id}/review`, {});
        setReviewStatus('ready');
      } catch {
        setReviewStatus('failed');
      }
    })();
  }, [isCompleted, hasPaper, run?.run_id, reviewStatus]);

  // Load QA history only after review is activated
  useEffect(() => {
    if (!run?.run_id || reviewStatus !== 'ready') return;
    void (async () => {
      try {
        const data = await apiGet<HistoryResponse>(`/api/runs/${run.run_id}/paper-qa/history`);
        setMessages(data.messages ?? []);
      } catch {
        setMessages([]);
      }
    })();
  }, [run?.run_id, reviewStatus]);

  // Handle rewrite
  const handleRewrite = useCallback(async (prompt: string) => {
    if (!run?.run_id) return;
    const sysMsg: QAMessage = {
      role: 'system',
      content: `↻ Rewrite requested: "${prompt}"`,
      ts: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, sysMsg]);
    try {
      await apiPost(`/api/runs/${run.run_id}/review/rewrite`, { revision_prompt: prompt });
    } catch (e) {
      console.error('Failed to trigger rewrite:', e);
    }
  }, [run?.run_id]);

  // No-op accept for completed sessions (just a visual confirmation)
  const handleAccept = useCallback(() => {
    // For completed sessions, "Accept" is cosmetic — nothing to submit
  }, []);

  // Not ready states
  if (!run) {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <p>Launch a session to produce a research paper.</p>
        </div>
      </div>
    );
  }

  if (isRunning) {
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

  if (isFailed && !hasPaper) {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <p>{run.error || 'The session failed before a paper could be generated.'}</p>
        </div>
      </div>
    );
  }

  if (!hasPaper) {
    return (
      <div className="paper-preview">
        <div className="paper-empty-state">
          <p>No paper generated yet.</p>
        </div>
      </div>
    );
  }

  // Show loading state while activating review (loading bus on backend)
  if (reviewStatus === 'loading') {
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

  // Flat split layout: PDF/LaTeX left, QA chat right
  const paperVersion = 1 + messages.filter(
    (m) => m.role === 'system' && m.content.startsWith('↻')
  ).length;

  return (
    <div className="paper-review-panel">
      <div style={{ flex: '0 0 58%', minWidth: 0, display: 'flex' }}>
        <PaperViewer
          run={run}
          paperVersion={paperVersion}
          isRewriting={false}
          theoryStatus={writerTask?.status || 'completed'}
          writerStatus={writerTask?.status || 'completed'}
        />
      </div>

      <div className="review-divider">
        <div className="review-divider-handle" />
      </div>

      <div style={{ flex: 1, minWidth: 0, display: 'flex' }}>
        <QAChat
          run={run}
          messages={messages}
          setMessages={setMessages}
          isRewriting={false}
          isHistorical={true}
          onAccept={handleAccept}
          onRewrite={handleRewrite}
        />
      </div>
    </div>
  );
}
