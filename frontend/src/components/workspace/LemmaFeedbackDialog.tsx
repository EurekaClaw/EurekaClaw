import { useState, useRef, useEffect } from 'react';

interface LemmaFeedbackDialogProps {
  lemmaId: string;
  lemmaName: string;
  onSubmit: (reason: string) => void;
  onClose: () => void;
}

export function LemmaFeedbackDialog({
  lemmaId,
  lemmaName,
  onSubmit,
  onClose,
}: LemmaFeedbackDialogProps) {
  const [reason, setReason] = useState('');
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (reason.trim()) onSubmit(reason.trim());
    }
  };

  return (
    <div className="lemma-fb-overlay" onClick={onClose}>
      <div className="lemma-fb-dialog" onClick={(e) => e.stopPropagation()}>
        <div className="lemma-fb-header">
          <div>
            <h3 className="lemma-fb-title">Describe the issue</h3>
            <p className="lemma-fb-subtitle">
              Flagged: <strong>{lemmaName}</strong>
              <span className="lemma-fb-id">({lemmaId})</span>
            </p>
          </div>
          <button className="dir-dialog-close" onClick={onClose} aria-label="Close">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>
        <div className="lemma-fb-body">
          <p className="lemma-fb-desc">
            Be specific — the theory agent will re-examine this lemma and fix the logical chain with your feedback.
          </p>
          <textarea
            ref={inputRef}
            className="lemma-fb-textarea"
            rows={4}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder='e.g. "The inductive step assumes bounded variance without proving it. The spectral norm bound in Step 2 does not follow from the stated hypothesis."'
          />
          <p className="lemma-fb-hint">Press Enter to submit, Shift+Enter for a new line.</p>
        </div>
        <div className="lemma-fb-footer">
          <button
            className="primary-btn"
            disabled={!reason.trim()}
            onClick={() => onSubmit(reason.trim())}
          >
            Retry with feedback
          </button>
          <button className="ghost-btn" onClick={onClose}>Cancel</button>
        </div>
      </div>
    </div>
  );
}
