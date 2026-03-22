import { useState, useRef, useEffect } from 'react';
import type { SessionRun } from '@/types';
import { useSessionStore } from '@/store/sessionStore';
import { apiPost } from '@/api/client';

interface DirectionDialogProps {
  run: SessionRun;
  onClose: () => void;
}

export function DirectionDialog({ run, onClose }: DirectionDialogProps) {
  const [input, setInput] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);

  const arts = run.artifacts ?? {};
  const brief = arts.research_brief ?? {};
  const openProblems = brief.open_problems ?? [];
  const keyObjects = brief.key_mathematical_objects ?? [];
  const conj = run.input_spec?.conjecture || run.input_spec?.query || '';
  const domain = run.input_spec?.domain || brief.domain || '';

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Close on Escape
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  const submit = async (hypothesis: string) => {
    if (!hypothesis.trim() || submitting) return;
    setSubmitting(true);
    try {
      const spec = run.input_spec ?? {};
      const newRun = await apiPost<SessionRun>('/api/runs', {
        mode: 'detailed',
        domain: spec.domain || '',
        conjecture: hypothesis.trim(),
        query: hypothesis.trim(),
        additional_context: spec.additional_context || '',
        selected_skills: spec.selected_skills || [],
      });
      setSessions([newRun, ...sessions.filter((s) => s.run_id !== newRun.run_id)]);
      setCurrentRunId(newRun.run_id);
      onClose();
    } catch (err) {
      alert(`Could not start new session: ${(err as Error).message}`);
    } finally {
      setSubmitting(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (input.trim()) {
        void submit(input);
      } else if (conj) {
        void submit(conj);
      }
    }
  };

  return (
    <div className="dir-dialog-overlay" onClick={onClose}>
      <div className="dir-dialog" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="dir-dialog-header">
          <div className="dir-dialog-header-left">
            <span className="dir-dialog-icon">💡</span>
            <div>
              <h3 className="dir-dialog-title">Choose a research direction</h3>
              <p className="dir-dialog-subtitle">
                Ideation returned 0 directions — please provide your own.
              </p>
            </div>
          </div>
          <button className="dir-dialog-close" onClick={onClose} aria-label="Close dialog">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        {/* Context section */}
        <div className="dir-dialog-body">
          {/* Survey context */}
          {(openProblems.length > 0 || keyObjects.length > 0) && (
            <div className="dir-dialog-context">
              <p className="dir-dialog-context-label">
                {domain ? `Survey findings in ${domain}:` : 'Survey findings:'}
              </p>
              {openProblems.length > 0 && (
                <>
                  <p className="dir-dialog-section-title">Open problems</p>
                  <ul className="dir-dialog-problems">
                    {openProblems.slice(0, 5).map((p, i) => (
                      <li key={i}>
                        <span className="dir-dialog-problem-text">
                          {typeof p === 'string' ? p : String(p)}
                        </span>
                        <button
                          className="dir-dialog-use-btn"
                          title="Use as direction"
                          onClick={() => setInput(typeof p === 'string' ? p : String(p))}
                        >
                          Use
                        </button>
                      </li>
                    ))}
                  </ul>
                </>
              )}
              {keyObjects.length > 0 && (
                <div className="dir-dialog-objects">
                  <p className="dir-dialog-section-title">Key mathematical objects</p>
                  <div className="dir-dialog-tags">
                    {keyObjects.slice(0, 8).map((obj, i) => (
                      <span key={i} className="dir-dialog-tag">{obj}</span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Conjecture */}
          {conj && (
            <div className="dir-dialog-conjecture">
              <p className="dir-dialog-section-title">Your conjecture</p>
              <blockquote className="dir-dialog-quote">{conj}</blockquote>
            </div>
          )}

          {/* Input area */}
          <div className="dir-dialog-input-area">
            <label className="dir-dialog-input-label" htmlFor="dir-dialog-input">
              Enter your research direction or hypothesis:
            </label>
            <div className="dir-dialog-input-wrap">
              <textarea
                ref={inputRef}
                id="dir-dialog-input"
                className="dir-dialog-textarea"
                rows={3}
                placeholder={conj
                  ? 'Type a direction, or press Enter to use your conjecture…'
                  : 'e.g. "Prove that sparse attention with low-rank kernels achieves O(n log n) complexity"'}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                disabled={submitting}
              />
              <button
                className="dir-dialog-send"
                disabled={submitting || (!input.trim() && !conj)}
                onClick={() => void submit(input.trim() || conj)}
                aria-label="Submit direction"
              >
                {submitting ? (
                  <span className="dir-dialog-spinner" />
                ) : (
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                    <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
                  </svg>
                )}
              </button>
            </div>
            <p className="dir-dialog-hint">
              {conj
                ? 'Press Enter to use your conjecture, or type a custom direction and press Enter.'
                : 'Press Enter to submit, or Shift+Enter for a new line.'}
            </p>
          </div>
        </div>

        {/* Footer actions */}
        <div className="dir-dialog-footer">
          {conj && (
            <button
              className="primary-btn"
              disabled={submitting}
              onClick={() => void submit(conj)}
            >
              Use original conjecture
            </button>
          )}
          <button
            className={conj ? 'secondary-btn' : 'primary-btn'}
            disabled={submitting || !input.trim()}
            onClick={() => void submit(input)}
          >
            {submitting ? 'Starting session…' : 'Use this direction'}
          </button>
          <button className="ghost-btn" onClick={onClose}>Cancel</button>
        </div>
      </div>
    </div>
  );
}
