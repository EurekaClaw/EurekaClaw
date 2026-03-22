import { useSkillStore } from '@/store/skillStore';
import { apiDelete } from '@/api/client';
import { SkillCard } from './SkillCard';
import { humanize } from '@/lib/formatters';
import type { Skill } from '@/types';

const SKILLS_PER_PAGE = 6;

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

  const handleDelete = async (name: string) => {
    if (!confirm(`Remove skill '${humanize(name)}'?\n\nThis deletes your local copy. Built-in seed skills can be reinstalled anytime.`)) return;
    try {
      await apiDelete(`/api/skills/${encodeURIComponent(name)}`);
      setAvailableSkills(availableSkills.filter((s) => s.name !== name));
      setSelectedSkills(selectedSkills.filter((n) => n !== name));
      onClawHubStatus(`Removed '${humanize(name)}'.`);
    } catch (err) {
      onClawHubStatus(`Could not delete: ${(err as Error).message}`, true);
    }
  };

  return (
    <div className="skills-library">
      <div className="skills-library-header">
        <h3 className="skills-library-title">Skill Library</h3>
        <span className="skills-library-meta">
          {query ? `${filtered.length} matching` : `${availableSkills.length} skills`}
        </span>
      </div>

      <div className="skills-search-wrap">
        <svg className="skills-search-icon" xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <input
          className="skills-search-input"
          type="text"
          placeholder="Search by name, topic, or proof technique…"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
        />
      </div>

      <div className="skills-grid">
        {filtered.length === 0 ? (
          <div className="skills-empty">
            <p>No skills match your search.</p>
            <p>Try a different keyword, or install new skills from ClawHub.</p>
          </div>
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
        <div className="skills-pagination">
          <button
            type="button"
            className="skills-page-btn"
            disabled={safePage === 1}
            onClick={() => setCurrentSkillPage(safePage - 1)}
          >
            ‹ Previous
          </button>
          <div className="skills-page-dots">
            {Array.from({ length: totalPages }, (_, i) => (
              <button
                key={i}
                type="button"
                className={`skills-page-dot${safePage === i + 1 ? ' is-active' : ''}`}
                onClick={() => setCurrentSkillPage(i + 1)}
              >
                {i + 1}
              </button>
            ))}
          </div>
          <button
            type="button"
            className="skills-page-btn"
            disabled={safePage === totalPages}
            onClick={() => setCurrentSkillPage(safePage + 1)}
          >
            Next ›
          </button>
        </div>
      )}
    </div>
  );
}
