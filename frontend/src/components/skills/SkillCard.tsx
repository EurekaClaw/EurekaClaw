import type { Skill } from '@/types';

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
  const map: Record<string, string> = { seed: 'seed', distilled: 'auto-learned', manual: 'manual', clawhub: 'ClawHub' };
  return map[source || 'manual'] || source || 'manual';
}

function skillIsDeletable(skill: Skill): boolean {
  return skill.source !== 'seed' && Boolean(skill.file_path) && (skill.file_path ?? '').includes('.eurekaclaw');
}

export function SkillCard({ skill, isSelected, onToggle, onDelete }: SkillCardProps) {
  const deletable = skillIsDeletable(skill);
  const usageCount = skill.usage_count ?? 0;
  const successRate = skill.success_rate;

  const stagesHtml = (skill.pipeline_stages ?? []).slice(0, 3);
  const tags = (skill.tags ?? []).slice(0, 3);

  return (
    <div className={`intent-skill-wrap${isSelected ? ' is-selected' : ''}`}>
      <button
        type="button"
        className="intent-skill"
        data-skill-name={skill.name}
        onClick={() => onToggle(skill.name)}
      >
        <div className="intent-skill-head">
          <span className="intent-skill-name">{skill.name}</span>
          <span className={`intent-skill-source ${skillSourceClass(skill.source)}`}>
            {skillSourceLabel(skill.source)}
          </span>
        </div>
        <p className="intent-skill-desc">{skill.description || 'No description.'}</p>
        <div className="intent-tag-row">
          {stagesHtml.map((s) => (
            <span key={s} className="skill-pipeline-tag">{s}</span>
          ))}
          {tags.map((t) => (
            <span key={t} className="intent-tag">{t}</span>
          ))}
        </div>
        {(usageCount > 0 || successRate != null) && (
          <div className="skill-stats-bar">
            {usageCount > 0 && (
              <span className="skill-usage-badge">{usageCount} use{usageCount !== 1 ? 's' : ''}</span>
            )}
            {successRate != null && (
              <>
                <span className="skill-success-label">{Math.round(successRate * 100)}% success</span>
                <div className="skill-success-track">
                  <div className="skill-success-fill" style={{ width: `${Math.round(successRate * 100)}%` }} />
                </div>
              </>
            )}
          </div>
        )}
      </button>
      {deletable && (
        <button
          type="button"
          className="skill-delete-btn"
          data-delete-skill={skill.name}
          title={`Remove '${skill.name}' from ~/.eurekaclaw/skills/`}
          onClick={() => onDelete(skill.name)}
        >
          🗑
        </button>
      )}
    </div>
  );
}
