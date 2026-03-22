import { useSkillStore } from '@/store/skillStore';

export function SelectedSkillsPanel() {
  const selectedSkills = useSkillStore((s) => s.selectedSkills);
  const toggleSkill = useSkillStore((s) => s.toggleSkill);
  const selectAll = useSkillStore((s) => s.selectAll);

  return (
    <article className="panel skill-selection-panel">
      <div className="panel-header">
        <div>
          <p className="eyebrow">Research Intent</p>
          <h3>Active for this session</h3>
        </div>
        <button className="ghost-btn skill-select-all-btn" id="select-all-skills-btn" onClick={selectAll}>
          Select all
        </button>
      </div>
      <div className="intent-selected skill-selected-panel" id="skill-selected">
        {selectedSkills.length > 0 ? (
          selectedSkills.map((name) => (
            <span key={name} className="intent-chip">
              <span>{name}</span>
              <button type="button" data-remove-skill={name} aria-label={`Remove ${name}`} onClick={() => toggleSkill(name)}>
                ×
              </button>
            </span>
          ))
        ) : (
          <div className="intent-empty">No skills selected — select from the library.</div>
        )}
      </div>
      <p className="inline-note">
        Skills are injected into agent prompts before each stage —
        the system also auto-learns new strategies after every successful proof.
      </p>
    </article>
  );
}
