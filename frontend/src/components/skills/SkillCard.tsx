import type { Skill } from '@/types';
import { humanize } from '@/lib/formatters';

interface SkillCardProps {
  skill: Skill;
  isSelected: boolean;
  onToggle: (name: string) => void;
  onDelete: (name: string) => void;
}

function skillSourceClass(source: string | undefined): string {
  return `skill-source--${(source || 'manual').replace(/[^a-z]/g, '')}`;
}

function skillSourceLabel(source: string | undefined): string {
  const map: Record<string, string> = { seed: 'Built-in', distilled: 'Learned', manual: 'Custom', clawhub: 'ClawHub' };
  return map[source || 'manual'] || source || 'Custom';
}

function skillIsDeletable(skill: Skill): boolean {
  return skill.source !== 'seed' && Boolean(skill.file_path) && (skill.file_path ?? '').includes('.eurekaclaw');
}

export function SkillCard({ skill, isSelected, onToggle, onDelete }: SkillCardProps) {
  const deletable = skillIsDeletable(skill);

  return (
    <div className={`skill-card-wrap${isSelected ? ' is-selected' : ''}`}>
      <div
        role="button"
        tabIndex={0}
        className="skill-card"
        onClick={() => onToggle(skill.name)}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') onToggle(skill.name); }}
      >
        {isSelected && (
          <span className="skill-card-check">
            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
          </span>
        )}
        <div className="skill-card-scroll">
          <div className="skill-card-top">
            <span className="skill-card-name">{humanize(skill.name)}</span>
            <span className={`skill-card-source ${skillSourceClass(skill.source)}`}>
              {skillSourceLabel(skill.source)}
            </span>
          </div>
          <p className="skill-card-desc">{humanize(skill.description || 'No description provided.')}</p>
        </div>
      </div>
      {deletable && (
        <button
          type="button"
          className="skill-card-delete"
          title={`Remove '${humanize(skill.name)}'`}
          onClick={(e) => { e.stopPropagation(); onDelete(skill.name); }}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
        </button>
      )}
    </div>
  );
}
