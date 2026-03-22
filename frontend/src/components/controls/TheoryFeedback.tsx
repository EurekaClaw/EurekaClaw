import { useState } from 'react';
import type { TheoryState } from '@/types';

interface TheoryFeedbackProps {
  theoryState: TheoryState | null | undefined;
  feedbackRef: React.MutableRefObject<string>;
}

export function TheoryFeedback({ theoryState, feedbackRef }: TheoryFeedbackProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [feedbackText, setFeedbackText] = useState('');

  const lemmaDAG = theoryState?.lemma_dag ?? {};
  const openGoalIds = theoryState?.open_goals ?? [];
  const provenLemmaIds = Object.keys(theoryState?.proven_lemmas ?? {});

  // Resolve readable names via lemma_dag; fall back to raw ID
  const resolveName = (id: string) => {
    const node = lemmaDAG[id];
    return node?.informal || node?.statement || id;
  };

  const allLemmaNames = [
    ...provenLemmaIds.map(resolveName),
    ...openGoalIds.map(resolveName),
  ];

  const handleChipClick = (name: string) => {
    const existing = feedbackText.trim();
    const newVal = existing ? `${existing}\nLemma "${name}": ` : `Lemma "${name}": `;
    setFeedbackText(newVal);
    feedbackRef.current = newVal;
  };

  const handleTextChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setFeedbackText(e.target.value);
    feedbackRef.current = e.target.value;
  };

  return (
    <div className="theory-feedback-section" id="theory-feedback-section">
      <button
        className="theory-feedback-toggle"
        id="theory-feedback-toggle"
        aria-expanded={isOpen}
        onClick={() => setIsOpen(!isOpen)}
      >
        <span className="theory-feedback-toggle-label">📐 Guide the proof before resuming</span>
        <span className={`theory-feedback-toggle-chevron${isOpen ? ' is-open' : ''}`} aria-hidden="true">›</span>
      </button>
      {isOpen && (
        <div className="theory-feedback-body" id="theory-feedback-body">
          <p className="theory-feedback-desc">
            Flag a step you want to challenge, or suggest a different approach.
            Your guidance will be injected as context when the proof resumes.
          </p>
          <div className="theory-feedback-lemma-list" id="theory-feedback-lemma-list">
            {allLemmaNames.length > 0 ? (
              allLemmaNames.map((name) => (
                <button
                  key={name}
                  type="button"
                  className="theory-feedback-lemma-chip"
                  data-lemma={name}
                  onClick={() => handleChipClick(name)}
                >
                  {name.length > 40 ? name.slice(0, 40) + '…' : name}
                </button>
              ))
            ) : (
              <span className="drawer-muted" style={{ fontSize: '0.8rem' }}>No lemmas yet</span>
            )}
          </div>
          <textarea
            className="theory-feedback-input"
            id="theory-feedback-input"
            rows={3}
            value={feedbackText}
            onChange={handleTextChange}
            placeholder='e.g. The inductive step in L3 needs a stronger hypothesis. Try bounding the spectral norm first…'
          />
        </div>
      )}
    </div>
  );
}
