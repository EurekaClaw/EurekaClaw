import type { SessionRun, PipelineTask } from '@/types';
import { titleCase } from './formatters';

export interface AgentManifestEntry {
  role: string;
  icon: string;
  name: string;
  tagline: string;
}

export const AGENT_MANIFEST: AgentManifestEntry[] = [
  { role: 'survey',     icon: '📚', name: 'Literature Survey',   tagline: 'Mapping the research frontier' },
  { role: 'ideation',   icon: '💡', name: 'Idea Generation',     tagline: 'Formulating research directions' },
  { role: 'theory',     icon: '📐', name: 'Theorem Proving',     tagline: 'Building a rigorous proof' },
  { role: 'experiment', icon: '🧪', name: 'Validation',          tagline: 'Testing theoretical bounds' },
  { role: 'writer',     icon: '✍️', name: 'Paper Writing',        tagline: 'Composing the manuscript' },
];

export const STAGE_TASK_MAP: Record<string, string> = {
  survey: 'survey',
  ideation: 'ideation',
  direction_selection_gate: 'ideation',
  theory: 'theory',
  theory_review_gate: 'theory',
  experiment: 'experiment',
  final_review_gate: 'experiment',
  writer: 'writer',
};

export const INNER_STAGE_LABELS: Record<string, string> = {
  ArchitectAgent: 'planning the proof structure',
  LemmaDeveloper: 'developing key lemmas',
  Verifier: 'checking the proof',
  CrystallizerAgent: 'crystallising the theorem',
  CompressAgent: 'compressing context',
  FormalAgent: 'formalising the proof',
  AssemblerAgent: 'assembling the argument',
};

export function agentNarrativeLine(
  role: string,
  taskMap: Map<string, PipelineTask>,
  run: SessionRun | null
): string {
  const task = taskMap.get(role);
  if (!task) return 'Waiting to begin…';
  const arts = run?.artifacts ?? {};
  const st = task.status;

  if (role === 'survey') {
    if (st === 'in_progress') return 'Navigating the academic landscape…';
    if (st === 'completed') {
      const papers = (arts.bibliography?.papers || arts.research_brief?.papers || []).length;
      const problems = (arts.research_brief?.open_problems || []).length;
      return `${papers} paper${papers !== 1 ? 's' : ''} read · ${problems} open problem${problems !== 1 ? 's' : ''} found`;
    }
  }
  if (role === 'ideation') {
    if (st === 'in_progress') return 'Exploring the hypothesis space…';
    if (st === 'completed') {
      const dir = arts.research_brief?.selected_direction;
      const dirStr = typeof dir === 'string' ? dir : dir?.title || dir?.direction || '';
      if (dirStr) return `"${dirStr.length > 55 ? dirStr.slice(0, 52) + '…' : dirStr}"`;
      return 'Direction set — ready for proof';
    }
  }
  if (role === 'theory') {
    if (st === 'in_progress') return 'Constructing proof, step by step…';
    if (st === 'completed') {
      const ts = arts.theory_state;
      const proved = Object.keys(ts?.proven_lemmas || {}).length;
      const lowConf = (ts?.low_confidence_lemmas || []).length;
      if (proved > 0)
        return `${proved} lemma${proved !== 1 ? 's' : ''} proven${lowConf > 0 ? ` · ${lowConf} low-confidence` : ' · proof complete'}`;
      return 'Proof pipeline ran';
    }
  }
  if (role === 'experiment') {
    if (st === 'skipped') return 'Skipped — experiment mode disabled';
    if (st === 'in_progress') return 'Running numerical validation…';
    if (st === 'completed') {
      const score = arts.experiment_result?.alignment_score;
      return score != null ? `Alignment ${(score * 100).toFixed(0)}% · bounds validated` : 'Completed';
    }
  }
  if (role === 'writer') {
    if (st === 'in_progress') return 'Composing the manuscript…';
    if (st === 'completed') {
      const paper = run?.result?.latex_paper || '';
      const words = paper.split(/\s+/).filter(Boolean).length;
      return `Paper ready · ${words} words`;
    }
  }

  const fallback: Record<string, string> = {
    pending: 'Waiting…',
    failed: 'Encountered an issue',
    awaiting_gate: 'Awaiting your input',
    skipped: 'Skipped',
  };
  return fallback[st] || titleCase(st);
}
