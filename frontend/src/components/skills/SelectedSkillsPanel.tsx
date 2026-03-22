import { useSkillStore } from '@/store/skillStore';
import { humanize } from '@/lib/formatters';

export function SelectedSkillsPanel() {
  const selectedSkills = useSkillStore((s) => s.selectedSkills);
  const toggleSkill = useSkillStore((s) => s.toggleSkill);
  const deselectAll = useSkillStore((s) => s.deselectAll);

  return (
    <div className="skills-active-bar">
      <div className="skills-active-header">
        <div className="skills-active-title-row">
          <span className="skills-active-icon">&#9733;</span>
          <span className="skills-active-label">
            Active skills for next session
          </span>
          <span className="skills-active-count">{selectedSkills.length}</span>
        </div>
        {selectedSkills.length > 0 && (
          <button className="skills-active-deselect-all" onClick={deselectAll}>
            Deselect all
          </button>
        )}
      </div>
      <div className="skills-active-chips">
        {selectedSkills.length > 0 ? (
          selectedSkills.map((name) => (
            <span key={name} className="intent-chip">
              <span>{humanize(name)}</span>
              <button type="button" aria-label={`Remove ${humanize(name)}`} onClick={() => toggleSkill(name)}>
                ×
              </button>
            </span>
          ))
        ) : (
          <span className="skills-active-empty">
            No skills selected — browse the library below and click to activate.
          </span>
        )}
      </div>
    </div>
  );
}
