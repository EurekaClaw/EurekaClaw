import { useUiStore } from '@/store/uiStore';
import { escapeHtml } from '@/lib/formatters';
import type { WizardStep } from '@/types';

const WIZARD_STEPS: WizardStep[] = [
  {
    icon: '🦞',
    title: 'Welcome to EurekaClaw',
    subtitle: 'An AI co-author that takes your mathematical question all the way to a camera-ready paper.',
    visual: `
      <div class="wiz-pipeline">
        <div class="wiz-pipe-step"><span class="wiz-pipe-icon">📚</span><span>Survey</span></div>
        <div class="wiz-pipe-arrow">→</div>
        <div class="wiz-pipe-step"><span class="wiz-pipe-icon">💡</span><span>Ideation</span></div>
        <div class="wiz-pipe-arrow">→</div>
        <div class="wiz-pipe-step"><span class="wiz-pipe-icon">📐</span><span>Theory</span></div>
        <div class="wiz-pipe-arrow">→</div>
        <div class="wiz-pipe-step"><span class="wiz-pipe-icon">🧪</span><span>Experiment</span></div>
        <div class="wiz-pipe-arrow">→</div>
        <div class="wiz-pipe-step"><span class="wiz-pipe-icon">✍️</span><span>Paper</span></div>
      </div>
      <p class="wiz-pipeline-caption">You give a question or domain. EurekaClaw does the rest — reading papers, formulating theorems, proving them, and writing a LaTeX paper.</p>
    `,
    items: [
      { label: 'Reads 100s of papers on arXiv & Semantic Scholar', note: 'Identifies research gaps and related work automatically' },
      { label: 'Generates theorems and proves them step by step', note: 'Bottom-up proof pipeline with lemma verification — low-confidence steps are flagged' },
      { label: 'Runs numerical experiments to validate theory', note: 'Checks that bounds hold empirically before writing' },
      { label: 'Produces a camera-ready LaTeX paper + PDF', note: 'Theorem environments, bibliography, and figures included' },
      { label: 'Your data stays on your machine — MIT licensed', note: 'No data is sent anywhere except the AI model you configure' },
    ],
    tip: 'Setup takes about 5 minutes. Optional tools like Lean4 and LaTeX can be added later — EurekaClaw runs in a useful mode without them.',
  },
  {
    icon: '📦',
    title: 'Install EurekaClaw',
    subtitle: 'You need Python 3.11 or newer. Open your Terminal and run these commands in order.',
    items: [
      { label: 'Clone the source code', code: 'git clone https://github.com/EurekaClaw/EurekaClaw\ncd EurekaClaw' },
      { label: 'Install the package and CLI', code: 'pip install -e "."', note: 'The eurekaclaw command will now be available in your terminal' },
      { label: 'Create your settings file', code: 'cp .env.example .env', note: 'Open .env in any text editor to add your API key in the next step' },
      { label: 'Start the web interface', code: 'eurekaclaw ui', note: "Then open http://localhost:7860 in your browser — you're already there!" },
      { label: 'Optional: OpenRouter / OAuth support', code: 'pip install -e ".[openai,oauth]"', optional: true },
    ],
    tip: 'If pip install fails, try: python -m pip install -e "." — and make sure you have Python 3.11+ with: python --version',
  },
  {
    icon: '🔑',
    title: 'Connect Your AI Model',
    subtitle: 'EurekaClaw needs access to a large language model. Choose the option that fits you.',
    visual: `
      <div class="wiz-options-grid">
        <div class="wiz-option-card wiz-option-recommended">
          <div class="wiz-option-badge">Recommended</div>
          <div class="wiz-option-title">Anthropic API Key</div>
          <div class="wiz-option-desc">Sign up at console.anthropic.com, get an API key, add it to .env</div>
          <code class="wiz-option-code">ANTHROPIC_API_KEY=sk-ant-...</code>
        </div>
        <div class="wiz-option-card">
          <div class="wiz-option-title">Claude Pro / Max</div>
          <div class="wiz-option-desc">Already pay for Claude? Use your existing subscription — no separate API key needed.</div>
          <code class="wiz-option-code">ANTHROPIC_AUTH_MODE=oauth</code>
        </div>
        <div class="wiz-option-card">
          <div class="wiz-option-title">OpenRouter</div>
          <div class="wiz-option-desc">Access dozens of models (GPT-4o, Gemini, Llama…) via one API key.</div>
          <code class="wiz-option-code">LLM_BACKEND=openrouter</code>
        </div>
        <div class="wiz-option-card">
          <div class="wiz-option-title">Local Model</div>
          <div class="wiz-option-desc">Run a model on your own machine with vLLM or Ollama.</div>
          <code class="wiz-option-code">LLM_BACKEND=local</code>
        </div>
      </div>
    `,
    items: [],
    tip: 'You can change the AI model at any time in the Settings tab — it writes back to .env automatically. Go to Settings → Test Connection to verify your key works.',
  },
  {
    icon: '⚙️',
    title: 'Key Settings to Know',
    subtitle: 'You can set these in .env or change them live in the Settings tab — no restart needed.',
    visual: `
      <div class="wiz-settings-table">
        <div class="wiz-settings-row wiz-settings-header"><span>Setting</span><span>What it controls</span><span>Default</span></div>
        <div class="wiz-settings-row"><code>GATE_MODE</code><span>How much you review before each stage proceeds</span><code>auto</code></div>
        <div class="wiz-settings-row"><code>OUTPUT_FORMAT</code><span>Paper output format: LaTeX PDF or Markdown</span><code>latex</code></div>
        <div class="wiz-settings-row"><code>THEORY_MAX_ITERATIONS</code><span>Max proof loop attempts before giving up</span><code>10</code></div>
        <div class="wiz-settings-row"><code>EXPERIMENT_MODE</code><span>When to run numerical validation</span><code>auto</code></div>
      </div>
    `,
    items: [
      { label: 'GATE_MODE = none', note: 'Fully autonomous — no check-ins from you. Good for overnight runs.' },
      { label: 'GATE_MODE = auto  (recommended)', note: 'Pauses and asks you to review when confidence is low. Best for your first runs.' },
      { label: 'GATE_MODE = human', note: 'Pauses at every stage boundary. Maximum control — slower but you see everything.' },
    ],
    tip: "For your very first session, set GATE_MODE=human so you can see what each stage produces before it continues.",
  },
  {
    icon: '🔧',
    title: 'Optional Power Tools',
    subtitle: 'None of these are required. Each one unlocks a specific capability.',
    items: [
      { label: 'Lean 4 — formal proof verification', code: 'curl https://elan.lean-lang.org/elan-init.sh | sh', note: 'Makes EurekaClaw mathematically rigorous — proofs are formally checked, not just LLM-evaluated', optional: true },
      { label: 'LaTeX / MacTeX — PDF compilation', code: 'brew install --cask mactex-no-gui   # macOS\nsudo apt install texlive-full       # Linux', note: 'Needed to compile paper.pdf — the .tex source file is always generated even without this', optional: true, badge: 'macOS / Linux' },
      { label: 'Docker — safe code sandbox', note: 'Install from docker.com — lets experiments run in an isolated container', optional: true },
      { label: 'Semantic Scholar API key', code: 'S2_API_KEY=your-key-here   # in .env', note: 'Unlocks citation counts, venue rankings, and richer paper metadata', optional: true },
      { label: 'Wolfram Alpha App ID', code: 'WOLFRAM_APP_ID=your-app-id   # in .env', note: 'Enables symbolic computation and formula cross-checking', optional: true },
    ],
    tip: 'Go to Settings → System Health to see which optional tools are detected. Missing tools appear as warnings, not errors — everything still works.',
  },
  {
    icon: '🧠',
    title: 'Activate Built-in Skills',
    subtitle: 'Skills are proof strategies and writing rules that all agents share. Install them once.',
    items: [
      { label: 'Install seed skills (run this once)', code: 'eurekaclaw install-skills', note: 'Saves proof patterns to ~/.eurekaclaw/skills/ — these persist across all future sessions' },
      { label: 'See what skills are installed', code: 'eurekaclaw skills' },
      { label: 'Theory skills included', note: 'Mathematical induction, proof by contradiction, compactness, concentration inequalities, UCB regret bounds' },
      { label: 'Survey & writing skills included', note: 'Literature gap analysis, theorem statement style, proof readability, reference formatting' },
      { label: 'Add your own skills anytime', code: '# Save any .md file into ~/.eurekaclaw/skills/', note: 'EurekaClaw also distills new skills automatically after each successful proof', optional: true },
    ],
    tip: 'Think of skills as a growing personal proof library. After each successful session, EurekaClaw adds what it learned — your system gets smarter over time.',
  },
  {
    icon: '🚀',
    title: 'Launch Your First Session',
    subtitle: 'Three research modes. Pick based on how much you already know about your topic.',
    visual: `
      <div class="wiz-modes-grid">
        <div class="wiz-mode-card">
          <div class="wiz-mode-icon">🔭</div>
          <div class="wiz-mode-title">Explore a domain</div>
          <div class="wiz-mode-desc">You give a broad area. EurekaClaw finds open problems and proposes conjectures.</div>
          <code class="wiz-mode-code">eurekaclaw explore "multi-armed bandit theory"</code>
        </div>
        <div class="wiz-mode-card">
          <div class="wiz-mode-icon">📐</div>
          <div class="wiz-mode-title">Prove a conjecture</div>
          <div class="wiz-mode-desc">You state the theorem. EurekaClaw builds a full proof and writes the paper.</div>
          <code class="wiz-mode-code">eurekaclaw prove "O(n log n) via sparse attention" --domain "ML theory"</code>
        </div>
        <div class="wiz-mode-card">
          <div class="wiz-mode-icon">📄</div>
          <div class="wiz-mode-title">Start from papers</div>
          <div class="wiz-mode-desc">Paste arXiv IDs. EurekaClaw reads them and generates follow-up research.</div>
          <code class="wiz-mode-code">eurekaclaw from-papers 1706.03762 2005.14165</code>
        </div>
      </div>
    `,
    items: [
      { label: 'Or use this browser UI', note: 'Click the Research tab → fill in the form → Launch Session. Live progress streams in real time.' },
      { label: 'Results are saved here', code: '~/.eurekaclaw/runs/<session_id>/\n  paper.tex   paper.pdf   references.bib', note: 'Also: theory_state.json, research_brief.json, experiment_result.json' },
    ],
    tip: "First time? Use the Research tab here, set Gate Mode to 'human', and start with a narrow domain you know well — that way you can judge the output quality.",
  },
];

export function WizardPanel() {
  const currentWizardStep = useUiStore((s) => s.currentWizardStep);
  const setCurrentWizardStep = useUiStore((s) => s.setCurrentWizardStep);
  const setActiveView = useUiStore((s) => s.setActiveView);

  const total = WIZARD_STEPS.length;
  const step = WIZARD_STEPS[currentWizardStep];
  const progress = ((currentWizardStep + 1) / total) * 100;

  const handleNext = () => {
    if (currentWizardStep < total - 1) {
      setCurrentWizardStep(currentWizardStep + 1);
    } else {
      setActiveView('workspace');
    }
  };

  const handleSkip = () => {
    localStorage.setItem('eurekaclaw_tutorial_skipped', '1');
    setActiveView('workspace');
  };

  if (!step) return null;

  return (
    <article className="panel wizard-panel">
      <div className="wizard-dots-row" id="wizard-dots-row" aria-hidden="true">
        {WIZARD_STEPS.map((_, i) => {
          const cls = i < currentWizardStep ? 'wizard-dot is-done' : i === currentWizardStep ? 'wizard-dot is-active' : 'wizard-dot';
          return <span key={i} className={cls}>{i < currentWizardStep ? '✓' : String(i + 1)}</span>;
        })}
      </div>

      <div className="wizard-progress">
        <div className="wizard-progress-bar" id="wizard-progress-bar" style={{ width: `${progress}%` }} />
      </div>

      <div className="wizard-content" id="wizard-stage">
        <div className="wizard-step-header">
          <div className="wizard-step-icon">{step.icon}</div>
          <div>
            <h2 className="wizard-step-title">{step.title}</h2>
            <p className="wizard-step-subtitle">{step.subtitle}</p>
          </div>
        </div>
        {step.visual && <div className="wizard-visual" dangerouslySetInnerHTML={{ __html: step.visual }} />}
        {step.items && step.items.length > 0 && (
          <div className="wizard-items">
            {step.items.map((item, i) => (
              <div key={i} className={`wizard-item${item.optional ? ' is-optional' : ''}`}>
                <span className="wizard-item-num">{item.optional ? '○' : String(i + 1)}</span>
                <div className="wizard-item-body">
                  <strong>{item.label}</strong>
                  {item.badge && <span className="wizard-item-badge">{item.badge}</span>}
                  {item.code && <code className="wizard-item-code">{escapeHtml(item.code)}</code>}
                  {item.note && <span className="wizard-item-note">{item.note}</span>}
                </div>
              </div>
            ))}
          </div>
        )}
        {step.tip && (
          <div className="wizard-tip">
            <span className="wizard-tip-icon">💡</span>
            <p>{step.tip}</p>
          </div>
        )}
      </div>

      <div className="wizard-footer">
        <button className="secondary-btn" id="prev-step-btn" disabled={currentWizardStep === 0} onClick={() => setCurrentWizardStep(Math.max(0, currentWizardStep - 1))}>
          ← Back
        </button>
        <span className="wizard-step-counter" id="wizard-step-label">Step {currentWizardStep + 1} of {total}</span>
        <button className="primary-btn" id="next-step-btn" onClick={handleNext}>
          {currentWizardStep === total - 1 ? 'Go to Research →' : 'Next →'}
        </button>
      </div>
      <div className="wizard-skip-row">
        <button className="ghost-btn wizard-skip-btn" id="skip-tutorial-btn" onClick={handleSkip}>
          Skip — go to workspace
        </button>
      </div>
    </article>
  );
}
