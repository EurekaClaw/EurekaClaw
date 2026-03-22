import { useSkillStore } from '@/store/skillStore';
import { apiDelete } from '@/api/client';
import { SkillCard } from './SkillCard';
import type { Skill } from '@/types';

const SKILLS_PER_PAGE = 4;

function skillSearchText(skill: Skill): string {
  return [
    skill.name,
    skill.description,
    ...(skill.tags ?? []),
    ...(skill.agent_roles ?? []),
    ...(skill.pipeline_stages ?? []),
    skill.source,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}

interface SkillLibraryProps {
  onClawHubStatus: (msg: string, isError?: boolean) => void;
}

export function SkillLibrary({ onClawHubStatus }: SkillLibraryProps) {
  const availableSkills = useSkillStore((s) => s.availableSkills);
  const selectedSkills = useSkillStore((s) => s.selectedSkills);
  const setAvailableSkills = useSkillStore((s) => s.setAvailableSkills);
  const setSelectedSkills = useSkillStore((s) => s.setSelectedSkills);
  const toggleSkill = useSkillStore((s) => s.toggleSkill);
  const currentSkillPage = useSkillStore((s) => s.currentSkillPage);
  const setCurrentSkillPage = useSkillStore((s) => s.setCurrentSkillPage);
  const searchQuery = useSkillStore((s) => s.searchQuery);
  const setSearchQuery = useSkillStore((s) => s.setSearchQuery);

  const query = searchQuery.toLowerCase();
  const filtered = availableSkills
    .filter((skill) => !query || skillSearchText(skill).includes(query))
    .sort((a, b) => {
      const aSelected = selectedSkills.includes(a.name) ? 1 : 0;
      const bSelected = selectedSkills.includes(b.name) ? 1 : 0;
      if (aSelected !== bSelected) return bSelected - aSelected;
      return a.name.localeCompare(b.name);
    });

  const totalPages = Math.max(1, Math.ceil(filtered.length / SKILLS_PER_PAGE));
  const safePage = Math.min(currentSkillPage, totalPages);
  const startIndex = (safePage - 1) * SKILLS_PER_PAGE;
  const visible = filtered.slice(startIndex, startIndex + SKILLS_PER_PAGE);

  const matchingText = query ? `${filtered.length} matching` : `${availableSkills.length} available`;
  const metaText = `${selectedSkills.length} selected · ${matchingText} · page ${safePage}/${totalPages}`;

  const handleDelete = async (name: string) => {
    if (!confirm(`Remove skill '${name}' from ~/.eurekaclaw/skills/?\n\nThis only deletes your local copy; seed skills remain built-in.`)) return;
    try {
      await apiDelete(`/api/skills/${encodeURIComponent(name)}`);
      setAvailableSkills(availableSkills.filter((s) => s.name !== name));
      setSelectedSkills(selectedSkills.filter((n) => n !== name));
      onClawHubStatus(`Removed '${name}'.`);
    } catch (err) {
      onClawHubStatus(`Could not delete: ${(err as Error).message}`, true);
    }
  };

  return (
    <article className="panel skill-library-panel">
      <div className="panel-header">
        <div>
          <p className="eyebrow">Skill Library</p>
          <h3>Choose skills for next run</h3>
        </div>
        <span className="mono-label" id="skill-meta">{metaText}</span>
      </div>
      <label className="intent-search skill-search-bar">
        <span>Search</span>
        <input
          id="skill-search"
          type="text"
          placeholder="proof, survey, induction…"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
        />
      </label>
      <div className="intent-list skill-library-list" id="skill-list">
        {filtered.length === 0 ? (
          <div className="intent-empty">No skills match this search.</div>
        ) : (
          visible.map((skill) => (
            <SkillCard
              key={skill.name}
              skill={skill}
              isSelected={selectedSkills.includes(skill.name)}
              onToggle={toggleSkill}
              onDelete={(name) => void handleDelete(name)}
            />
          ))
        )}
      </div>
      {totalPages > 1 && (
        <div className="skill-pagination" id="skill-pagination">
          <button
            type="button"
            className="ghost-btn"
            disabled={safePage === 1}
            onClick={() => setCurrentSkillPage(safePage - 1)}
          >
            ← Prev
          </button>
          <span className="skill-pagination-meta">{safePage} / {totalPages}</span>
          <button
            type="button"
            className="ghost-btn"
            disabled={safePage === totalPages}
            onClick={() => setCurrentSkillPage(safePage + 1)}
          >
            Next →
          </button>
        </div>
      )}
    </article>
  );
}
