import { useState } from 'react';
import { apiPost } from '@/api/client';
import { useSkillStore } from '@/store/skillStore';
import type { Skill } from '@/types';

interface ClawHubPanelProps {
  status: string;
  statusError: boolean;
  onStatus: (msg: string, isError?: boolean) => void;
}

interface InstallResponse {
  ok: boolean;
  message?: string;
  error?: string;
}

interface SkillsResponse {
  skills: Skill[];
}

export function ClawHubPanel({ status, statusError, onStatus }: ClawHubPanelProps) {
  const [inputVal, setInputVal] = useState('');
  const [installing, setInstalling] = useState(false);
  const setAvailableSkills = useSkillStore((s) => s.setAvailableSkills);

  const refreshSkills = async () => {
    try {
      const data = await apiPost<SkillsResponse>('/api/skills', {});
      setAvailableSkills(data.skills ?? []);
    } catch {
      // silently ignore
    }
  };

  const installSkill = async (skillname: string) => {
    const label = skillname ? `'${skillname}'` : 'seed skills';
    setInstalling(true);
    onStatus(`Installing ${label}…`);
    try {
      const result = await apiPost<InstallResponse>('/api/skills/install', { skillname: skillname || '' });
      if (result.ok) {
        onStatus(`✓ ${result.message ?? 'Done'}`);
        if (skillname) setInputVal('');
        await refreshSkills();
      } else {
        onStatus(result.error || 'Install failed.', true);
      }
    } catch (err) {
      onStatus((err as Error).message || 'Install failed.', true);
    } finally {
      setInstalling(false);
    }
  };

  return (
    <article className="panel clawhub-panel">
      <div className="clawhub-header">
        <span className="clawhub-logo-mark" aria-hidden="true">🦞</span>
        <div className="clawhub-header-text">
          <p className="eyebrow">ClawHub</p>
          <h3>Install Skills</h3>
        </div>
        <p className="clawhub-tagline">
          Add community proof strategies, domain plugins, or your own —
          they become available in every future session automatically.
        </p>
      </div>
      <div className="clawhub-body">
        <div className="clawhub-input-row">
          <label className="clawhub-input-label" htmlFor="clawhub-input">Install from ClawHub</label>
          <div className="clawhub-input-group">
            <input
              id="clawhub-input"
              type="text"
              placeholder="author/skill-name  (e.g. steipete/github)"
              autoComplete="off"
              spellCheck={false}
              value={inputVal}
              disabled={installing}
              onChange={(e) => setInputVal(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void installSkill(inputVal.trim());
              }}
            />
            <button
              className="clawhub-hub-btn"
              id="clawhub-install-btn"
              disabled={installing}
              onClick={() => {
                const slug = inputVal.trim();
                if (!slug) {
                  onStatus('Enter a ClawHub skill slug, e.g. steipete/github', true);
                  return;
                }
                void installSkill(slug);
              }}
            >
              Install
            </button>
          </div>
          <span className="clawhub-input-hint">
            Needs the <code>clawhub</code> CLI →
            <code>pip install clawhub</code>
          </span>
        </div>
        <div className="clawhub-divider"><span>or</span></div>
        <div className="clawhub-seeds-row">
          <button
            className="clawhub-seeds-btn"
            id="install-seeds-btn"
            disabled={installing}
            onClick={() => void installSkill('')}
          >
            📦 Install built-in seed skills
          </button>
          <span className="clawhub-seeds-hint">Copies bundled proof strategies to <code>~/.eurekaclaw/skills/</code></span>
        </div>
        {status && (
          <p id="clawhub-status" className={`clawhub-status${statusError ? ' is-error' : ' is-ok'}`}>
            {status}
          </p>
        )}
      </div>
    </article>
  );
}
