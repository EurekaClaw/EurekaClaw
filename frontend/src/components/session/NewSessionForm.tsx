import { useState } from 'react';
import { useSessionStore } from '@/store/sessionStore';
import { useSkillStore } from '@/store/skillStore';
import { useUiStore } from '@/store/uiStore';
import { apiPost } from '@/api/client';
import type { SessionRun } from '@/types';

const MODE_CONFIG: Record<string, { promptLabel: string; promptPlaceholder: string; requirePrompt: boolean; requireDomain: boolean; showPaperIds: boolean }> = {
  detailed: {
    promptLabel: 'Conjecture / theorem to prove',
    promptPlaceholder: 'e.g. The sample complexity of transformers is O(L·d·log(d)/ε²)',
    requirePrompt: true,
    requireDomain: false,
    showPaperIds: false,
  },
  reference: {
    promptLabel: 'Research focus (optional)',
    promptPlaceholder: 'e.g. Find gaps in sparse attention theory, or leave blank to auto-detect',
    requirePrompt: false,
    requireDomain: true,
    showPaperIds: true,
  },
  exploration: {
    promptLabel: 'Guiding question (optional)',
    promptPlaceholder: 'e.g. What are the tightest known regret lower bounds for stochastic bandits?',
    requirePrompt: false,
    requireDomain: true,
    showPaperIds: false,
  },
};

export function NewSessionForm() {
  const [mode, setMode] = useState('detailed');
  const [domain, setDomain] = useState('Machine learning theory');
  const [prompt, setPrompt] = useState('');
  const [paperIds, setPaperIds] = useState('');
  const [error, setError] = useState('');
  const [launching, setLaunching] = useState(false);

  const selectedSkills = useSkillStore((s) => s.selectedSkills);
  const sessions = useSessionStore((s) => s.sessions);
  const setSessions = useSessionStore((s) => s.setSessions);
  const setCurrentRunId = useSessionStore((s) => s.setCurrentRunId);
  const setCurrentLogPage = useSessionStore((s) => s.setCurrentLogPage);
  const setActiveView = useUiStore((s) => s.setActiveView);

  const cfg = MODE_CONFIG[mode] ?? MODE_CONFIG.detailed;

  const validate = (): string | null => {
    if (cfg.requireDomain && !domain.trim()) return `Research domain is required for ${mode} mode.`;
    if (cfg.requirePrompt && !prompt.trim()) {
      return mode === 'detailed'
        ? 'Please enter the conjecture or theorem you want EurekaClaw to prove.'
        : 'Research prompt is required for this mode.';
    }
    return null;
  };

  const buildPayload = () => {
    const skillCtx = selectedSkills.length ? `User-selected skills: ${selectedSkills.join(', ')}` : '';
    const ids = paperIds.split(/[\n,\s]+/).map((id) => id.trim()).filter(Boolean);
    if (mode === 'reference') {
      return { mode: 'reference', domain: domain.trim(), query: prompt.trim() || `Find research gaps in ${domain}`, paper_ids: ids, additional_context: skillCtx, selected_skills: selectedSkills };
    }
    if (mode === 'exploration') {
      return { mode: 'exploration', domain: domain.trim(), query: prompt.trim() || `Survey the frontier of ${domain} and identify open problems`, additional_context: skillCtx, selected_skills: selectedSkills };
    }
    return { mode: 'detailed', domain: domain.trim(), conjecture: prompt.trim(), query: prompt.trim(), additional_context: skillCtx, selected_skills: selectedSkills };
  };

  const handleLaunch = async () => {
    const validErr = validate();
    if (validErr) {
      setError(validErr);
      setTimeout(() => setError(''), 4000);
      return;
    }
    setError('');
    setLaunching(true);
    try {
      const run = await apiPost<SessionRun>('/api/runs', buildPayload());
      setSessions([run, ...sessions.filter((s) => s.run_id !== run.run_id)]);
      setCurrentRunId(run.run_id);
      setCurrentLogPage(1);
      setActiveView('workspace');
    } catch (err) {
      setError(`Could not start session: ${(err as Error).message}`);
    } finally {
      setLaunching(false);
    }
  };

  const loadExample = () => {
    setMode('detailed');
    setDomain('Machine learning theory');
    setPrompt('Prove a generalization bound for sparse transformer attention under low-rank kernel assumptions.');
  };

  return (
    <div className="new-session-pane" id="new-session-pane">
      <div className="new-session-card">
        <div className="canvas-heading">
          <h2 className="canvas-title">What would you like to prove?</h2>
          <p className="canvas-sub">EurekaClaw surveys the literature, generates theorems, and writes a complete mathematical proof — autonomously.</p>
        </div>
        <div className="canvas-form-body">
          <div className="canvas-row-duo">
            <label>
              <span className="canvas-label">Mode</span>
              <select id="input-mode" value={mode} onChange={(e) => setMode(e.target.value)}>
                <option value="detailed">Detailed proof</option>
                <option value="reference">Reference-driven</option>
                <option value="exploration">Open exploration</option>
              </select>
            </label>
            <label>
              <span className="canvas-label">Research domain</span>
              <input id="input-domain" type="text" value={domain} onChange={(e) => setDomain(e.target.value)} placeholder="e.g. computational complexity" />
            </label>
          </div>
          {cfg.showPaperIds && (
            <label className="canvas-full" id="paper-ids-label">
              <span className="canvas-label">arXiv / Semantic Scholar IDs <em className="field-note">(one per line)</em></span>
              <textarea id="input-paper-ids" rows={2} value={paperIds} onChange={(e) => setPaperIds(e.target.value)} placeholder={'1706.03762\n2005.14165'} />
            </label>
          )}
          <label className="canvas-full">
            <span className="canvas-label" id="prompt-label">{cfg.promptLabel}</span>
            <textarea id="input-prompt" rows={5} value={prompt} onChange={(e) => setPrompt(e.target.value)} placeholder={cfg.promptPlaceholder} />
          </label>
          {selectedSkills.length > 0 && (
            <div className="canvas-skill-chips">
              {selectedSkills.map((name) => (
                <span key={name} className="intent-chip">{name}</span>
              ))}
            </div>
          )}
          <div className="canvas-actions">
            <button className="canvas-launch-btn" id="launch-session-btn" disabled={launching} onClick={() => void handleLaunch()}>
              <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>
              {launching ? 'Launching…' : 'Launch research session'}
            </button>
            <button className="ghost-btn" id="load-example-btn" onClick={loadExample}>Load example</button>
          </div>
          {error && <p className="canvas-error" id="canvas-error">{error}</p>}
        </div>
      </div>
    </div>
  );
}
