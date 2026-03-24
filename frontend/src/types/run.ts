export interface TokenUsage {
  input?: number;
  output?: number;
}

export interface PipelineTask {
  task_id: string;
  name: string;
  agent_role: string;
  description?: string;
  status: 'pending' | 'queued' | 'in_progress' | 'running' | 'completed' | 'failed' | 'skipped' | 'awaiting_gate';
  started_at?: string;
  completed_at?: string;
  error_message?: string;
  outputs?: {
    token_usage?: TokenUsage;
    [key: string]: unknown;
  };
}

export interface Paper {
  paper_id?: string;
  title?: string;
  authors?: string[];
  year?: number;
  abstract?: string;
  venue?: string;
  arxiv_id?: string;
  semantic_scholar_id?: string;
  citation_count?: number;
  url?: string;
  relevance_score?: number;
}

// ── Theory types ──────────────────────────────────────────────────────────────

export interface LemmaNode {
  lemma_id: string;
  statement: string;
  informal?: string;
  dependencies?: string[];
  verified?: boolean | null;
  confidence_score?: number | null;
  verification_method?: string | null;
}

export interface ProofRecord {
  lemma_id: string;
  proof_text: string;
  lean4_proof?: string;
  coq_proof?: string;
  verification_method?: string;
  verified?: boolean;
  verifier_notes?: string;
  proved_at?: string;
}

export interface Counterexample {
  lemma_id: string;
  counterexample_description: string;
  falsifies_conjecture?: boolean;
  suggested_refinement?: string;
  discovered_at?: string;
}

export interface FailedAttempt {
  lemma_id: string;
  attempt_text: string;
  failure_reason: string;
  iteration: number;
  timestamp?: string;
}

export interface KnownResult {
  source_paper_id: string;
  source_paper_title: string;
  result_type: 'theorem' | 'lemma' | 'corollary' | 'algorithm' | 'technique';
  extraction_source?: 'abstract_summary' | 'pdf_result_sections';
  statement: string;
  theorem_content?: string;
  assumptions?: string;
  proof_idea?: string;
  reuse_judgment?: 'direct_reusable' | 'adaptable' | 'background_only' | 'unclear';
  informal?: string;
  proof_technique?: string;
  notation?: Record<string, string>;
}

export interface ProofPlanEntry {
  lemma_id: string;
  statement: string;
  informal?: string;
  provenance: 'known' | 'adapted' | 'new';
  source?: string;
  adaptation_note?: string;
  dependencies?: string[];
}

export interface ResearchDirection {
  direction_id: string;
  title: string;
  hypothesis: string;
  approach_sketch?: string;
  novelty_score?: number;
  soundness_score?: number;
  transformative_score?: number;
  composite_score?: number;
}

// ── Bound / Experiment ────────────────────────────────────────────────────────

export interface Bound {
  name?: string;
  theoretical?: string | number;
  empirical?: string | number;
  aligned?: boolean | null;
}

export interface ExperimentResult {
  session_id?: string;
  experiment_id?: string;
  alignment_score?: number;
  bounds?: Bound[];
  description?: string;
  code?: string;
  outputs?: Record<string, unknown>;
  sandbox_log?: string;
  execution_time_s?: number;
  succeeded?: boolean;
}

// ── Research Brief ────────────────────────────────────────────────────────────

export interface ResearchBrief {
  session_id?: string;
  input_mode?: string;
  domain?: string;
  query?: string;
  conjecture?: string | null;
  reference_paper_ids?: string[];
  open_problems?: string[];
  key_mathematical_objects?: string[];
  directions?: ResearchDirection[];
  selected_direction?: ResearchDirection | null;
  selected_skills?: string[];
}

// ── Theory State ──────────────────────────────────────────────────────────────

export interface TheoryState {
  session_id?: string;
  theorem_id?: string;
  informal_statement?: string;
  formal_statement?: string;
  memory_theorems?: string[];
  problem_type?: string;
  analysis_notes?: string;
  proof_template?: string;
  proof_skeleton?: string;
  assembled_proof?: string;
  research_gap?: string;
  status?: 'pending' | 'in_progress' | 'proved' | 'refuted' | 'abandoned';
  known_results?: KnownResult[];
  proof_plan?: ProofPlanEntry[];
  /** lemma_id → LemmaNode — use this to get readable names for open_goals */
  lemma_dag?: Record<string, LemmaNode>;
  /** lemma_id → ProofRecord */
  proven_lemmas?: Record<string, ProofRecord>;
  /** list of lemma_ids not yet proven — look up names via lemma_dag */
  open_goals?: string[];
  failed_attempts?: FailedAttempt[];
  counterexamples?: Counterexample[];
  iteration?: number;
}

// ── Artifacts ─────────────────────────────────────────────────────────────────

export interface Artifacts {
  research_brief?: ResearchBrief;
  bibliography?: { papers?: Paper[]; bibtex?: string };
  theory_state?: TheoryState;
  experiment_result?: ExperimentResult;
  resource_analysis?: Record<string, unknown> | null;
}

// ── InputSpec ─────────────────────────────────────────────────────────────────

export interface InputSpec {
  mode?: 'detailed' | 'reference' | 'exploration';
  domain?: string;
  query?: string;
  conjecture?: string | null;
  paper_ids?: string[];
  paper_texts?: string[];
  additional_context?: string;
  selected_skills?: string[];
}

// ── RunResult ─────────────────────────────────────────────────────────────────

export interface RunResult {
  session_id?: string;
  latex_paper?: string;
  pdf_path?: string | null;
  theory_state_json?: string;
  experiment_result_json?: string;
  research_brief_json?: string;
  bibliography_json?: string;
  eval_report_json?: string;
  skills_distilled?: string[];
}

// ── SessionRun ────────────────────────────────────────────────────────────────

export type RunStatus =
  | 'queued'
  | 'running'
  | 'pausing'
  | 'paused'
  | 'resuming'
  | 'awaiting_gate'
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
  paused_at?: string;
  pause_requested_at?: string;
  paused_stage?: string;
  theory_feedback?: string;
  error?: string;
  pipeline?: PipelineTask[];
  artifacts?: Artifacts;
  result?: RunResult;
  output_dir?: string;
  output_summary?: Record<string, unknown>;
  input_spec?: InputSpec;
}
