import { create } from 'zustand';

type ActiveView = 'workspace' | 'skills' | 'systems' | 'onboarding';
type ActiveWsTab = 'live' | 'proof' | 'paper' | 'logs';

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

export const useUiStore = create<UiState>((set, get) => ({
  activeView: 'onboarding',
  activeWsTab: 'live',
  openAgentDrawerRole: null,
  currentWizardStep: 0,
  isFlashing: false,

  setActiveView: (view) => set({ activeView: view }),
  setActiveWsTab: (tab) => set({ activeWsTab: tab }),
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
