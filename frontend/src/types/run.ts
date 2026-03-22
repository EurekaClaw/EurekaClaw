export interface TokenUsage {
  input?: number;
  output?: number;
}

export interface PipelineTask {
  name: string;
  agent_role: string;
  status: 'pending' | 'queued' | 'in_progress' | 'running' | 'completed' | 'failed' | 'skipped' | 'awaiting_gate';
  started_at?: string;
  completed_at?: string;
  error_message?: string;
  outputs?: {
    token_usage?: TokenUsage;
  };
}

export interface Paper {
  title?: string;
  year?: number;
  arxiv_id?: string;
}

export interface Bound {
  name?: string;
  theoretical?: string | number;
  empirical?: string | number;
  passes?: boolean;
}

export interface ExperimentResult {
  alignment_score?: number;
  bounds?: Bound[];
  description?: string;
}

export interface ResearchBrief {
  papers?: Paper[];
  open_problems?: Array<string | { description: string }>;
  key_objects?: Array<string | { name: string }>;
  key_mathematical_objects?: Array<string | { name: string }>;
  selected_direction?: string | { title?: string; direction?: string };
  directions?: string[];
  research_directions?: string[];
  domain?: string;
}

export interface TheoryState {
  formal_statement?: string;
  proof_skeleton?: string;
  open_goals?: Array<string | { name?: string; description?: string; confidence?: string; status?: string }>;
  proven_lemmas?: Record<string, string | object>;
  low_confidence_lemmas?: string[];
  counterexamples?: string[];
  iteration?: number;
}

export interface Artifacts {
  research_brief?: ResearchBrief;
  bibliography?: { papers?: Paper[] };
  theory_state?: TheoryState;
  experiment_result?: ExperimentResult;
}

export interface InputSpec {
  mode?: string;
  domain?: string;
  query?: string;
  conjecture?: string;
  paper_ids?: string[];
  additional_context?: string;
  selected_skills?: string[];
}

export interface RunResult {
  latex_paper?: string;
}

export type RunStatus =
  | 'queued'
  | 'running'
  | 'pausing'
  | 'paused'
  | 'resuming'
  | 'completed'
  | 'failed';

export interface SessionRun {
  run_id: string;
  session_id?: string;
  name?: string;
  status: RunStatus;
  created_at?: string;
  started_at?: string;
  completed_at?: string;
  paused_stage?: string;
  pause_requested_at?: string;
  error?: string;
  pipeline?: PipelineTask[];
  artifacts?: Artifacts;
  result?: RunResult;
  output_dir?: string;
  input_spec?: InputSpec;
}
