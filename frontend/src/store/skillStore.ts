import { create } from 'zustand';
import type { Skill } from '@/types';

interface SkillState {
  availableSkills: Skill[];
  selectedSkills: string[];
  currentSkillPage: number;
  searchQuery: string;

  setAvailableSkills: (skills: Skill[]) => void;
  setSelectedSkills: (skills: string[]) => void;
  toggleSkill: (name: string) => void;
  setCurrentSkillPage: (page: number) => void;
  setSearchQuery: (q: string) => void;
  deselectAll: () => void;
}

export const useSkillStore = create<SkillState>((set, get) => ({
  availableSkills: [],
  selectedSkills: [],
  currentSkillPage: 1,
  searchQuery: '',

  setAvailableSkills: (skills) => set({ availableSkills: skills }),
  setSelectedSkills: (skills) => set({ selectedSkills: skills }),

  toggleSkill: (name) => {
    const { selectedSkills } = get();
    if (selectedSkills.includes(name)) {
      set({ selectedSkills: selectedSkills.filter((n) => n !== name) });
    } else {
      set({ selectedSkills: [...selectedSkills, name] });
    }
  },

  setCurrentSkillPage: (page) => set({ currentSkillPage: page }),
  setSearchQuery: (q) => set({ searchQuery: q, currentSkillPage: 1 }),
  deselectAll: () => set({ selectedSkills: [] }),
}));
