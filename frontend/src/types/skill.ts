export interface Skill {
  name: string;
  description?: string;
  tags?: string[];
  agent_roles?: string[];
  pipeline_stages?: string[];
  source?: 'seed' | 'distilled' | 'manual' | 'clawhub' | string;
  file_path?: string;
  usage_count?: number;
  success_rate?: number;
}
