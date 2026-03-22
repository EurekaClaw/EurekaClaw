export interface Capability {
  status: string;
  detail: string;
}

export interface AppConfig {
  llm_backend?: string;
  anthropic_auth_mode?: string;
  ccproxy_port?: string | number;
  eurekaclaw_model?: string;
  eurekaclaw_fast_model?: string;
  theory_pipeline?: string;
  theory_max_iterations?: number;
  auto_verify_confidence?: number;
  verifier_pass_confidence?: number;
  output_format?: string;
  paper_reader_use_pdf?: boolean;
  paper_reader_abstract_papers?: number;
  paper_reader_pdf_papers?: number;
  anthropic_api_key?: string;
  openai_compat_base_url?: string;
  openai_compat_api_key?: string;
  openai_compat_model?: string;
  minimax_api_key?: string;
  minimax_model?: string;
  eurekaclaw_mode?: string;
  gate_mode?: string;
  experiment_mode?: string;
  eurekaclaw_dir?: string;
  max_tokens_agent?: number;
  max_tokens_prover?: number;
  max_tokens_planner?: number;
  max_tokens_architect?: number;
  max_tokens_decomposer?: number;
  max_tokens_assembler?: number;
  max_tokens_formalizer?: number;
  max_tokens_crystallizer?: number;
  max_tokens_analyst?: number;
  max_tokens_sketch?: number;
  max_tokens_verifier?: number;
  max_tokens_compress?: number;
  [key: string]: string | number | boolean | undefined;
}

export interface CapabilitiesMap {
  [key: string]: Capability;
}
