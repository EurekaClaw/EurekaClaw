import { useState } from 'react';
import { apiGet, apiPost } from '@/api/client';
import { useSkillStore } from '@/store/skillStore';
import { humanize } from '@/lib/formatters';
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
      const data = await apiGet<SkillsResponse>('/api/skills');
      setAvailableSkills(data.skills ?? []);
    } catch {
      // silently ignore
    }
  };

  const installSkill = async (skillname: string) => {
    const label = skillname ? `'${humanize(skillname)}'` : 'seed skills';
    setInstalling(true);
    onStatus(`Installing ${label}…`);
    try {
      const result = await apiPost<InstallResponse>('/api/skills/install', { skillname: skillname || '' });
      if (result.ok) {
        onStatus(`${result.message ?? 'Done'}`);
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
    <div className="skills-hub-bar">
      <div className="skills-hub-bar-left">
        <button
          className="skills-hub-seed-btn-compact"
          disabled={installing}
          onClick={() => void installSkill('')}
        >
          <span className="skills-hub-seed-icon">&#x1F4E6;</span>
          <span>Install built-in strategies</span>
        </button>
      </div>

      <div className="skills-hub-bar-right">
        <span className="skills-hub-bar-label">ClawHub</span>
        <input
          type="text"
          className="skills-hub-input"
          placeholder="author/skill-name"
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
          className="primary-btn skills-hub-install-btn"
          disabled={installing || !inputVal.trim()}
          onClick={() => void installSkill(inputVal.trim())}
        >
          Install
        </button>
      </div>

      {status && (
        <span className={`skills-hub-bar-status${statusError ? ' is-error' : ' is-ok'}`}>
          {status}
        </span>
      )}
    </div>
  );
}
