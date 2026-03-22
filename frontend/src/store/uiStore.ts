import { create } from 'zustand';

type ActiveView = 'workspace' | 'skills' | 'systems' | 'onboarding';
type ActiveWsTab = 'live' | 'proof' | 'paper' | 'logs';

const STORAGE_KEY = 'eurekaclaw_ui';

function loadPersistedUi(): { activeView: ActiveView; activeWsTab: ActiveWsTab } {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      const validViews: ActiveView[] = ['workspace', 'skills', 'systems', 'onboarding'];
      const validTabs: ActiveWsTab[] = ['live', 'proof', 'paper', 'logs'];
      return {
        activeView: validViews.includes(parsed.activeView) ? parsed.activeView : 'onboarding',
        activeWsTab: validTabs.includes(parsed.activeWsTab) ? parsed.activeWsTab : 'live',
      };
    }
  } catch { /* ignore */ }
  return { activeView: 'onboarding', activeWsTab: 'live' };
}

function persistUi(view: ActiveView, tab: ActiveWsTab) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ activeView: view, activeWsTab: tab })); } catch { /* ignore */ }
}

interface UiState {
  activeView: ActiveView;
  activeWsTab: ActiveWsTab;
  openAgentDrawerRole: string | null;
  currentWizardStep: number;
  isFlashing: boolean;

  setActiveView: (view: ActiveView) => void;
  setActiveWsTab: (tab: ActiveWsTab) => void;
  setOpenAgentDrawerRole: (role: string | null) => void;
  setCurrentWizardStep: (step: number) => void;
  flashTransitionTo: (view: ActiveView) => void;
}

const initial = loadPersistedUi();

export const useUiStore = create<UiState>((set, get) => ({
  activeView: initial.activeView,
  activeWsTab: initial.activeWsTab,
  openAgentDrawerRole: null,
  currentWizardStep: 0,
  isFlashing: false,

  setActiveView: (view) => { set({ activeView: view }); persistUi(view, get().activeWsTab); },
  setActiveWsTab: (tab) => { set({ activeWsTab: tab }); persistUi(get().activeView, tab); },
  setOpenAgentDrawerRole: (role) => set({ openAgentDrawerRole: role }),
  setCurrentWizardStep: (step) => set({ currentWizardStep: step }),

  flashTransitionTo: (view) => {
    set({ isFlashing: true });
    setTimeout(() => {
      set({ activeView: view, isFlashing: false });
    }, 90);
    // The FlashOverlay handles the animation via CSS class
    const { setActiveView } = get();
    setActiveView(view);
  },
}));
