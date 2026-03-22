export interface WizardItem {
  label: string;
  code?: string;
  note?: string;
  optional?: boolean;
  badge?: string;
}

export interface WizardStep {
  icon: string;
  title: string;
  subtitle: string;
  visual?: string;
  items?: WizardItem[];
  tip?: string;
}
