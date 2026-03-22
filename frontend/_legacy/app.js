const views = document.querySelectorAll(".view");
const navItems = document.querySelectorAll("[data-view-target]");

const inputModeEl = document.getElementById("input-mode");
const inputDomainEl = document.getElementById("input-domain");
const inputPromptEl = document.getElementById("input-prompt");
const inputPaperIdsEl = document.getElementById("input-paper-ids");
const paperIdsLabel = document.getElementById("paper-ids-label");
const promptLabelEl = document.getElementById("prompt-label");
const launchSessionBtn = document.getElementById("launch-session-btn");
const loadExampleBtn = document.getElementById("load-example-btn");
const runMetaEl = document.getElementById("run-meta");
const runStatusPillEl = document.getElementById("run-status-pill");
const tokenUsageValueEl = document.getElementById("token-usage-value");
const tokenUsageBreakdownEl = document.getElementById("token-usage-breakdown");
const agentTrackEl = document.getElementById("agent-track");
const liveActivityAreaEl = document.getElementById("live-activity-area");
const proofSketchPanelEl = document.getElementById("proof-sketch-panel");
const logStreamEl = document.getElementById("log-stream");
const logPaginationEl = document.getElementById("log-pagination");
const paperPreviewEl = document.getElementById("paper-preview");
const agentDrawerEl = document.getElementById("agent-drawer");
const agentDrawerBackdropEl = document.getElementById("agent-drawer-backdrop");
const agentDrawerIconEl = document.getElementById("agent-drawer-icon");
const agentDrawerTitleEl = document.getElementById("agent-drawer-title");
const agentDrawerStatusEl = document.getElementById("agent-drawer-status");
const agentDrawerBodyEl = document.getElementById("agent-drawer-body");
const closeAgentDrawerBtn = document.getElementById("close-agent-drawer-btn");
const theoryFeedbackSectionEl = document.getElementById("theory-feedback-section");
const theoryFeedbackToggleEl = document.getElementById("theory-feedback-toggle");
const theoryFeedbackBodyEl = document.getElementById("theory-feedback-body");
const theoryFeedbackInputEl = document.getElementById("theory-feedback-input");
const theoryFeedbackLemmaListEl = document.getElementById("theory-feedback-lemma-list");
const capabilityListEl = document.getElementById("capability-list");
const configFormEl = document.getElementById("config-form");
const configSaveStatusEl = document.getElementById("config-save-status");
const testConnectionBtn = document.getElementById("test-connection-btn");
const saveAndTestBtn = document.getElementById("save-and-test-btn");
const authGuidanceEl = document.getElementById("auth-guidance");
const authGuidanceShellEl = document.getElementById("auth-guidance-shell");
const authGuidanceToggleEl = document.getElementById("auth-guidance-toggle");
const authGuidanceToggleMetaEl = document.getElementById("auth-guidance-toggle-meta");
const configConditionalEls = document.querySelectorAll("[data-config-show]");
const skillSearchEl = document.getElementById("skill-search");
const skillSelectedEl = document.getElementById("skill-selected");
const skillListEl = document.getElementById("skill-list");
const skillMetaEl = document.getElementById("skill-meta");
const skillPaginationEl = document.getElementById("skill-pagination");
const clawhubInputEl = document.getElementById("clawhub-input");
const clawhubInstallBtn = document.getElementById("clawhub-install-btn");
const clawhubStatusEl = document.getElementById("clawhub-status");
const installSeedsBtnEl = document.getElementById("install-seeds-btn");
const selectAllSkillsBtnEl = document.getElementById("select-all-skills-btn");
const sessionListEl = document.getElementById("session-list");
const pauseSessionBtn = document.getElementById("pause-session-btn");
const resumeSessionBtn = document.getElementById("resume-session-btn");
const proofCtrlEl = document.getElementById("proof-ctrl");
const proofCtrlTrackEl = document.getElementById("proof-ctrl-track");
const proofCtrlRunningEl = document.getElementById("proof-ctrl-running");
const proofCtrlPausingEl = document.getElementById("proof-ctrl-pausing");
const proofCtrlPausedEl = document.getElementById("proof-ctrl-paused");
const proofCtrlResumingEl = document.getElementById("proof-ctrl-resuming");
const proofCtrlPausedStageEl = document.getElementById("proof-ctrl-paused-stage");
const proofCtrlLiveLabelEl = document.getElementById("proof-ctrl-live-label");
const proofCtrlLiveSubEl = document.getElementById("proof-ctrl-live-sub");
const proofCtrlRunningHintEl = document.getElementById("proof-ctrl-running-hint");
const pauseElapsedEl = document.getElementById("pause-elapsed");
const proofCtrlSessionIdEl = document.getElementById("proof-ctrl-session-id");
const copyResumeCmdBtn = document.getElementById("copy-resume-cmd-btn");
const copyResumeCmdLabelEl = document.getElementById("copy-resume-cmd-label");
const failedSessionNoteEl = document.getElementById("failed-session-note");
const failedSessionErrorTextEl = document.getElementById("failed-session-error-text");
const restartSessionBtn = document.getElementById("restart-session-btn");
const skipTutorialBtn = document.getElementById("skip-tutorial-btn");

// Canvas / session-detail pane switching
const newSessionPaneEl = document.getElementById("new-session-pane");
const sessionDetailPaneEl = document.getElementById("session-detail-pane");
const sessionTopbarNameEl = document.getElementById("session-topbar-name");
const sessionTopbarRenameBtnEl = document.getElementById("session-topbar-rename-btn");
const sessionTopbarNameInputEl = document.getElementById("session-topbar-name-input");
const canvasErrorEl = document.getElementById("canvas-error");

const wizardStage = document.getElementById("wizard-stage");
const wizardDotsRow = document.getElementById("wizard-dots-row");
const wizardProgressBar = document.getElementById("wizard-progress-bar");
const wizardStepLabel = document.getElementById("wizard-step-label");
const prevStepBtn = document.getElementById("prev-step-btn");
const nextStepBtn = document.getElementById("next-step-btn");

const TUTORIAL_SKIP_KEY = "eurekaclaw_tutorial_skipped";

let currentWizardStep = 0;
let currentRunId = null;
let isPausingRequested = false; // true between "Pause clicked" and server confirming paused status
let pauseRequestedAt = null;    // Date object set when pause is clicked (for elapsed timer)
let elapsedTimer = null;        // setInterval id for the pausing elapsed ticker
let pollTimer = null;
let pollErrors = 0;
const POLL_INTERVAL_FAST_MS = 500;   // while pausing / resuming — need fast feedback
const POLL_INTERVAL_ACTIVE_MS = 1200; // while running / queued
const POLL_INTERVAL_IDLE_MS = 3000;  // all sessions terminal — keep alive for new sessions
const POLL_MAX_ERRORS = 4;
let latestRun = null;           // latest full snapshot (for agent drawer re-render)
let openAgentDrawerRole = null; // which agent drawer is currently open
let activeWsTab = "live";       // currently active workspace tab
let prevTheoryTaskStatus = null; // track theory task status changes for auto-tab-switch
let availableSkills = [];
let selectedSkills = [];
let allSessions = [];
let currentSkillPage = 1;
const skillsPerPage = 4;
let currentLogPage = 1;
const logsPerPage = 6;

function showView(viewName) {
  views.forEach((view) => {
    view.classList.toggle("is-visible", view.dataset.view === viewName);
  });

  navItems.forEach((item) => {
    item.classList.toggle("is-active", item.dataset.viewTarget === viewName);
  });
}

function flashTransitionTo(viewName) {
  const overlay = document.getElementById("flash-overlay");
  overlay.classList.remove("flash-in", "flash-out");
  requestAnimationFrame(() => {
    overlay.classList.add("flash-in");
    setTimeout(() => {
      showView(viewName);
      overlay.classList.remove("flash-in");
      overlay.classList.add("flash-out");
      setTimeout(() => overlay.classList.remove("flash-out"), 380);
    }, 90);
  });
}

navItems.forEach((item) => {
  item.addEventListener("click", () => showView(item.dataset.viewTarget));
});

const wizardSteps = [
  {
    icon: "🦞",
    title: "Welcome to EurekaClaw",
    subtitle: "An AI co-author that takes your mathematical question all the way to a camera-ready paper.",
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
      { label: "Reads 100s of papers on arXiv & Semantic Scholar", note: "Identifies research gaps and related work automatically" },
      { label: "Generates theorems and proves them step by step", note: "Bottom-up proof pipeline with lemma verification — low-confidence steps are flagged" },
      { label: "Runs numerical experiments to validate theory", note: "Checks that bounds hold empirically before writing" },
      { label: "Produces a camera-ready LaTeX paper + PDF", note: "Theorem environments, bibliography, and figures included" },
      { label: "Your data stays on your machine — MIT licensed", note: "No data is sent anywhere except the AI model you configure" }
    ],
    tip: "Setup takes about 5 minutes. Optional tools like Lean4 and LaTeX can be added later — EurekaClaw runs in a useful mode without them."
  },
  {
    icon: "📦",
    title: "Install EurekaClaw",
    subtitle: "You need Python 3.11 or newer. Open your Terminal and run these commands in order.",
    items: [
      { label: "Clone the source code", code: "git clone https://github.com/EurekaClaw/EurekaClaw_dev_zero\ncd EurekaClaw_dev_zero" },
      { label: "Install the package and CLI", code: "pip install -e \".\"", note: "The eurekaclaw command will now be available in your terminal" },
      { label: "Create your settings file", code: "cp .env.example .env", note: "Open .env in any text editor to add your API key in the next step" },
      { label: "Start the web interface", code: "eurekaclaw ui", note: "Then open http://localhost:7860 in your browser — you're already there!" },
      { label: "Optional: OpenRouter / OAuth support", code: "pip install -e \".[openai,oauth]\"", optional: true }
    ],
    tip: "If pip install fails, try: python -m pip install -e \".\" — and make sure you have Python 3.11+ with: python --version"
  },
  {
    icon: "🔑",
    title: "Connect Your AI Model",
    subtitle: "EurekaClaw needs access to a large language model. Choose the option that fits you.",
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
    tip: "You can change the AI model at any time in the Settings tab — it writes back to .env automatically. Go to Settings → Test Connection to verify your key works."
  },
  {
    icon: "⚙️",
    title: "Key Settings to Know",
    subtitle: "You can set these in .env or change them live in the Settings tab — no restart needed.",
    visual: `
      <div class="wiz-settings-table">
        <div class="wiz-settings-row wiz-settings-header">
          <span>Setting</span><span>What it controls</span><span>Default</span>
        </div>
        <div class="wiz-settings-row">
          <code>GATE_MODE</code>
          <span>How much you review before each stage proceeds</span>
          <code>auto</code>
        </div>
        <div class="wiz-settings-row">
          <code>OUTPUT_FORMAT</code>
          <span>Paper output format: LaTeX PDF or Markdown</span>
          <code>latex</code>
        </div>
        <div class="wiz-settings-row">
          <code>THEORY_MAX_ITERATIONS</code>
          <span>Max proof loop attempts before giving up</span>
          <code>10</code>
        </div>
        <div class="wiz-settings-row">
          <code>EXPERIMENT_MODE</code>
          <span>When to run numerical validation</span>
          <code>auto</code>
        </div>
      </div>
    `,
    items: [
      { label: "GATE_MODE = none", note: "Fully autonomous — no check-ins from you. Good for overnight runs." },
      { label: "GATE_MODE = auto  (recommended)", note: "Pauses and asks you to review when confidence is low. Best for your first runs." },
      { label: "GATE_MODE = human", note: "Pauses at every stage boundary. Maximum control — slower but you see everything." }
    ],
    tip: "For your very first session, set GATE_MODE=human so you can see what each stage produces before it continues."
  },
  {
    icon: "🔧",
    title: "Optional Power Tools",
    subtitle: "None of these are required. Each one unlocks a specific capability.",
    items: [
      { label: "Lean 4 — formal proof verification", code: "curl https://elan.lean-lang.org/elan-init.sh | sh", note: "Makes EurekaClaw mathematically rigorous — proofs are formally checked, not just LLM-evaluated", optional: true },
      { label: "LaTeX / MacTeX — PDF compilation", code: "brew install --cask mactex-no-gui   # macOS\nsudo apt install texlive-full       # Linux", note: "Needed to compile paper.pdf — the .tex source file is always generated even without this", optional: true, badge: "macOS / Linux" },
      { label: "Docker — safe code sandbox", note: "Install from docker.com — lets experiments run in an isolated container", optional: true },
      { label: "Semantic Scholar API key", code: "S2_API_KEY=your-key-here   # in .env", note: "Unlocks citation counts, venue rankings, and richer paper metadata", optional: true },
      { label: "Wolfram Alpha App ID", code: "WOLFRAM_APP_ID=your-app-id   # in .env", note: "Enables symbolic computation and formula cross-checking", optional: true }
    ],
    tip: "Go to Settings → System Health to see which optional tools are detected. Missing tools appear as warnings, not errors — everything still works."
  },
  {
    icon: "🧠",
    title: "Activate Built-in Skills",
    subtitle: "Skills are proof strategies and writing rules that all agents share. Install them once.",
    items: [
      { label: "Install seed skills (run this once)", code: "eurekaclaw install-skills", note: "Saves proof patterns to ~/.eurekaclaw/skills/ — these persist across all future sessions" },
      { label: "See what skills are installed", code: "eurekaclaw skills" },
      { label: "Theory skills included", note: "Mathematical induction, proof by contradiction, compactness, concentration inequalities, UCB regret bounds" },
      { label: "Survey & writing skills included", note: "Literature gap analysis, theorem statement style, proof readability, reference formatting" },
      { label: "Add your own skills anytime", code: "# Save any .md file into ~/.eurekaclaw/skills/", note: "EurekaClaw also distills new skills automatically after each successful proof", optional: true }
    ],
    tip: "Think of skills as a growing personal proof library. After each successful session, EurekaClaw adds what it learned — your system gets smarter over time."
  },
  {
    icon: "🚀",
    title: "Launch Your First Session",
    subtitle: "Three research modes. Pick based on how much you already know about your topic.",
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
      { label: "Or use this browser UI", note: "Click the Research tab → fill in the form → Launch Session. Live progress streams in real time." },
      { label: "Results are saved here", code: "~/.eurekaclaw/runs/<session_id>/\n  paper.tex   paper.pdf   references.bib", note: "Also: theory_state.json, research_brief.json, experiment_result.json" }
    ],
    tip: "First time? Use the Research tab here, set Gate Mode to 'human', and start with a narrow domain you know well — that way you can judge the output quality."
  }
];

function renderWizardStep(index) {
  const step = wizardSteps[index];
  const total = wizardSteps.length;
  const progress = ((index + 1) / total) * 100;

  // Dots row
  wizardDotsRow.innerHTML = wizardSteps.map((_, i) => {
    const cls = i < index ? "wizard-dot is-done" : i === index ? "wizard-dot is-active" : "wizard-dot";
    const label = i < index ? "✓" : String(i + 1);
    return `<span class="${cls}">${label}</span>`;
  }).join("");

  // Content
  wizardStage.innerHTML = `
    <div class="wizard-step-header">
      <div class="wizard-step-icon">${step.icon}</div>
      <div>
        <h2 class="wizard-step-title">${step.title}</h2>
        <p class="wizard-step-subtitle">${step.subtitle}</p>
      </div>
    </div>
    ${step.visual ? `<div class="wizard-visual">${step.visual}</div>` : ""}
    ${step.items && step.items.length ? `
    <div class="wizard-items">
      ${step.items.map((item, i) => `
        <div class="wizard-item${item.optional ? " is-optional" : ""}">
          <span class="wizard-item-num">${item.optional ? "○" : String(i + 1)}</span>
          <div class="wizard-item-body">
            <strong>${item.label}</strong>${item.badge ? ` <span class="wizard-item-badge">${item.badge}</span>` : ""}
            ${item.code ? `<code class="wizard-item-code">${escapeHtml(item.code)}</code>` : ""}
            ${item.note ? `<span class="wizard-item-note">${item.note}</span>` : ""}
          </div>
        </div>
      `).join("")}
    </div>` : ""}
    ${step.tip ? `
      <div class="wizard-tip">
        <span class="wizard-tip-icon">💡</span>
        <p>${step.tip}</p>
      </div>
    ` : ""}
  `;

  wizardProgressBar.style.width = `${progress}%`;
  wizardStepLabel.textContent = `Step ${index + 1} of ${total}`;
  prevStepBtn.disabled = index === 0;
  nextStepBtn.textContent = index === total - 1 ? "Go to Research →" : "Next →";
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

// ── Pane switching ────────────────────────────────────────────────────────

function showNewSessionPane() {
  newSessionPaneEl.hidden = false;
  sessionDetailPaneEl.hidden = true;
}

function showSessionDetailPane() {
  newSessionPaneEl.hidden = true;
  sessionDetailPaneEl.hidden = false;
}

function truncateSessionName(run) {
  const text = run?.input_spec?.query || run?.input_spec?.domain || "Untitled session";
  return text.length > 64 ? text.slice(0, 61) + "…" : text;
}

function updateSessionTopbar(run) {
  if (!run) return;
  const name = run.name || truncateSessionName(run);
  sessionTopbarNameEl.textContent = name;
  sessionTopbarNameEl.hidden = false;
  sessionTopbarNameInputEl.hidden = true;
}

// ── Rename session ────────────────────────────────────────────────────────

async function renameRun(runId, newName) {
  if (!newName.trim() || !runId) return;
  try {
    await apiPost(`/api/runs/${runId}/rename`, { name: newName.trim() });
    const session = allSessions.find((s) => s.run_id === runId);
    if (session) session.name = newName.trim();
    if (runId === currentRunId) updateSessionTopbar(session);
    renderSessionList(allSessions);
  } catch (_) {
    // silently ignore — name reverts on next poll
  }
}

function startSidebarRename(runId) {
  const item = sessionListEl.querySelector(`[data-run-id="${CSS.escape(runId)}"]`);
  if (!item) return;
  const nameEl = item.querySelector(".session-item-name");
  if (!nameEl) return;
  const session = allSessions.find((s) => s.run_id === runId);
  const currentName = session?.name || nameEl.textContent || "";

  const input = document.createElement("input");
  input.className = "session-rename-input";
  input.value = currentName;
  input.maxLength = 80;

  nameEl.replaceWith(input);
  input.focus();
  input.select();

  const finish = async () => {
    const val = input.value.trim();
    if (val && val !== currentName) await renameRun(runId, val);
    else renderSessionList(allSessions);
  };
  input.addEventListener("blur", finish, { once: true });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") input.blur();
    if (e.key === "Escape") {
      input.removeEventListener("blur", finish);
      renderSessionList(allSessions);
    }
  });
}

// ── Restart session ───────────────────────────────────────────────────────

async function restartRun(runId) {
  const btn = document.getElementById("restart-session-btn");
  const btnLabel = btn && btn.querySelector("span");
  const originalLabel = btnLabel ? btnLabel.textContent : "";
  if (btn) { btn.disabled = true; }
  if (btnLabel) btnLabel.textContent = "Restarting…";
  try {
    const newRun = await apiPost(`/api/runs/${runId}/restart`, {});
    allSessions = [newRun, ...allSessions.filter((s) => s.run_id !== newRun.run_id)];
    currentRunId = newRun.run_id;
    currentLogPage = 1;
    renderSessionList(allSessions);
    renderRun(newRun);
    if (!pollTimer) startPolling(newRun.run_id);
  } catch (error) {
    if (btn) { btn.disabled = false; }
    if (btnLabel) btnLabel.textContent = originalLabel;
    // Show a clean error message — not the raw JSON body
    const msg = (() => {
      try { return JSON.parse(error.message).error || error.message; } catch { return error.message; }
    })();
    setRunStatus("failed", `Restart failed: ${msg}`);
  }
}

function titleCase(text) {
  return text
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function parseServerTimestamp(value) {
  if (!value) {
    return null;
  }
  const normalized = /[zZ]|[+-]\d{2}:\d{2}$/.test(value) ? value : `${value}Z`;
  const parsed = new Date(normalized);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatLocalTimestamp(value) {
  const parsed = parseServerTimestamp(value);
  if (!parsed) {
    return "--";
  }
  return parsed.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

function formatRelativeTime(value) {
  const parsed = parseServerTimestamp(value);
  if (!parsed) return "--";
  const diffMin = Math.floor((Date.now() - parsed.getTime()) / 60000);
  if (diffMin < 1) return "Just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  return `${Math.floor(diffHr / 24)}d ago`;
}

function renderSessionList(sessions) {
  allSessions = sessions;
  if (!sessions.length) {
    sessionListEl.innerHTML = '<p class="session-list-empty">No sessions yet.<br>Launch one to get started.</p>';
    return;
  }
  sessionListEl.innerHTML = sessions.map((s) => {
    const rawName = s.name || s.input_spec?.query || s.input_spec?.domain || "Untitled session";
    const displayName = rawName.length > 52 ? rawName.slice(0, 49) + "…" : rawName;
    const status = s.status || "queued";
    const time = formatRelativeTime(s.created_at);
    const isActive = s.run_id === currentRunId;
    const isFailed = status === "failed";
    const isPaused = status === "paused";
    const isPausing = status === "pausing";
    const isResuming = status === "resuming";
    const isRunning = status === "running" || status === "queued";
    const isLive = isRunning || isPausing || isResuming;
    const extraClass = isActive ? " is-active" : isFailed ? " is-failed" : "";
    const statusLabel = titleCase(status);
    const canDelete = !isLive;
    return `<div class="session-item${extraClass}" data-run-id="${escapeHtml(s.run_id)}">
      <div class="session-item-main">
        <div class="session-item-name">${escapeHtml(displayName)}</div>
        <div class="session-item-meta">
          <span class="session-status-dot ${status}" aria-label="${escapeHtml(statusLabel)}"></span>
          <span>${time}</span>
          ${isFailed ? `<span class="session-item-failed-tag">failed</span>` : ""}
          ${isPaused ? `<span class="session-item-failed-tag session-item-paused-tag">paused</span>` : ""}
          ${isPausing ? `<span class="session-item-failed-tag session-item-pausing-tag">pausing…</span>` : ""}
          ${isResuming ? `<span class="session-item-failed-tag session-item-resuming-tag">resuming…</span>` : ""}
        </div>
      </div>
      <div class="session-item-actions">
        ${isFailed ? `<button class="session-action-btn session-restart-sidebar-btn" data-restart-run-id="${escapeHtml(s.run_id)}" title="Restart session" aria-label="Restart session">
          <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/></svg>
        </button>` : ""}
        <button class="session-action-btn session-rename-sidebar-btn" data-rename-run-id="${escapeHtml(s.run_id)}" title="Rename" aria-label="Rename session">
          <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
        </button>
        ${canDelete ? `<button class="session-action-btn session-delete-btn" data-delete-run-id="${escapeHtml(s.run_id)}" title="Delete session" aria-label="Delete session">
          <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
        </button>` : ""}
      </div>
    </div>`;
  }).join("");
}

async function loadSessionList() {
  try {
    const data = await apiGet("/api/runs");
    renderSessionList(data.runs || []);
  } catch (_) {
    // Silently fail — don't disrupt the main UX
  }
}

function statusClass(status) {
  if (status === "completed" || status === "available") {
    return "status-complete";
  }
  if (status === "running" || status === "in_progress" || status === "configured") {
    return "status-active";
  }
  if (status === "failed" || status === "missing") {
    return "status-error";
  }
  if (status === "paused") {
    return "status-paused";
  }
  if (status === "pausing") {
    return "status-pausing";
  }
  if (status === "resuming") {
    return "status-resuming";
  }
  if (status === "optional") {
    return "status-warning";
  }
  return "status-idle";
}

function setRunStatus(status, detail) {
  runStatusPillEl.className = `status-pill ${statusClass(status)}`;
  runStatusPillEl.textContent = titleCase(status);
  if (detail !== undefined) {
    runMetaEl.textContent = detail;
    runMetaEl.style.color = "";
  }
}

function liveStatusDetail(run) {
  if (!run) return "Launch a session from the form above.";
  if (run.status === "queued") return "Session queued — waiting to start…";
  if (run.status === "running") {
    const activeTasks = (run.pipeline || []).filter((t) => t.status === "in_progress");
    if (activeTasks.length) {
      return `Running: ${activeTasks.map((t) => titleCase(t.name)).join(", ")}`;
    }
    const elapsed = run.started_at
      ? Math.floor((Date.now() - new Date(run.started_at).getTime()) / 1000)
      : 0;
    return `Running${elapsed ? ` · ${elapsed}s elapsed` : ""}`;
  }
  if (run.status === "completed") {
    const dir = run.output_dir ? ` → ${run.output_dir}` : "";
    return `Completed${dir}`;
  }
  if (run.status === "paused") {
    return "Proof paused at checkpoint — click Resume to continue, or use the Copy command button.";
  }
  if (run.status === "failed") return `Failed: ${run.error || "unknown error"}`;
  return `Run ${run.run_id.slice(0, 8)}`;
}

function renderTokenUsage(tasks) {
  const totals = (tasks || []).reduce(
    (acc, task) => {
      const usage = task?.outputs?.token_usage || {};
      acc.input += Number(usage.input || 0);
      acc.output += Number(usage.output || 0);
      return acc;
    },
    { input: 0, output: 0 }
  );

  const total = totals.input + totals.output;
  tokenUsageValueEl.textContent = `${total.toLocaleString()} total`;
  tokenUsageBreakdownEl.textContent = `Input ${totals.input.toLocaleString()} · Output ${totals.output.toLocaleString()}`;
}

// ── Agent manifest ────────────────────────────────────────────────────────────

const AGENT_MANIFEST = [
  { role: "survey",     icon: "📚", name: "Literature Survey",      tagline: "Mapping the research frontier" },
  { role: "ideation",   icon: "💡", name: "Idea Generation",        tagline: "Formulating research directions" },
  { role: "theory",     icon: "📐", name: "Theorem Proving",        tagline: "Building a rigorous proof" },
  { role: "experiment", icon: "🧪", name: "Validation",             tagline: "Testing theoretical bounds" },
  { role: "writer",     icon: "✍️", name: "Paper Writing",          tagline: "Composing the manuscript" },
];

function agentNarrativeLine(role, taskMap, run) {
  const task = taskMap.get(role);
  if (!task) return "Waiting to begin…";
  const arts = run?.artifacts || {};
  const st = task.status;
  if (role === "survey") {
    if (st === "in_progress") return "Navigating the academic landscape…";
    if (st === "completed") {
      const papers = (arts.bibliography?.papers || arts.research_brief?.papers || []).length;
      const problems = (arts.research_brief?.open_problems || []).length;
      return `${papers} paper${papers !== 1 ? "s" : ""} read · ${problems} open problem${problems !== 1 ? "s" : ""} found`;
    }
  }
  if (role === "ideation") {
    if (st === "in_progress") return "Exploring the hypothesis space…";
    if (st === "completed") {
      const dir = arts.research_brief?.selected_direction;
      const dirStr = typeof dir === "string" ? dir : dir?.title || dir?.direction || "";
      if (dirStr) return `"${dirStr.length > 55 ? dirStr.slice(0, 52) + "…" : dirStr}"`;
      return "Direction set — ready for proof";
    }
  }
  if (role === "theory") {
    if (st === "in_progress") return "Constructing proof, step by step…";
    if (st === "completed") {
      const ts = arts.theory_state;
      const proved = Object.keys(ts?.proven_lemmas || {}).length;
      const lowConf = (ts?.low_confidence_lemmas || []).length;
      if (proved > 0) return `${proved} lemma${proved !== 1 ? "s" : ""} proven${lowConf > 0 ? ` · ${lowConf} low-confidence` : " · proof complete"}`;
      return "Proof pipeline ran";
    }
  }
  if (role === "experiment") {
    if (st === "skipped") return "Skipped — experiment mode disabled";
    if (st === "in_progress") return "Running numerical validation…";
    if (st === "completed") {
      const score = arts.experiment_result?.alignment_score;
      return score != null ? `Alignment ${(score * 100).toFixed(0)}% · bounds validated` : "Completed";
    }
  }
  if (role === "writer") {
    if (st === "in_progress") return "Composing the manuscript…";
    if (st === "completed") {
      const paper = run?.result?.latex_paper || "";
      const words = paper.split(/\s+/).filter(Boolean).length;
      return `Paper ready · ${words} words`;
    }
  }
  const fallback = { pending: "Waiting…", failed: "Encountered an issue", awaiting_gate: "Awaiting your input", skipped: "Skipped" };
  return fallback[st] || titleCase(st);
}

function renderAgentTrack(tasks, run) {
  if (!agentTrackEl) return;
  const taskMap = new Map((tasks || []).map((t) => [t.agent_role, t]));
  agentTrackEl.innerHTML = AGENT_MANIFEST.map(({ role, icon, name }) => {
    const task = taskMap.get(role);
    const st = task?.status || "pending";
    const isDone = st === "completed" || st === "skipped";
    const isActive = st === "in_progress" || st === "awaiting_gate";
    const isFailed = st === "failed";
    const narrative = agentNarrativeLine(role, taskMap, run);
    const stateClass = isDone ? " is-done" : isActive ? " is-active" : isFailed ? " is-failed" : "";
    const statusLabel = isDone ? "done" : isActive ? "active" : isFailed ? "failed" : "pending";
    return `
      <button class="agent-step-card${stateClass}" data-agent-role="${escapeHtml(role)}" aria-label="View ${escapeHtml(name)} details">
        <span class="agent-step-icon" aria-hidden="true">${icon}</span>
        <div class="agent-step-body">
          <span class="agent-step-name">${escapeHtml(name)}</span>
          <span class="agent-step-summary">${escapeHtml(narrative)}</span>
        </div>
        <span class="agent-step-badge badge-${statusLabel}">${statusLabel}</span>
      </button>
    `;
  }).join("");
}

// ── Agent drawer ─────────────────────────────────────────────────────────────

function openAgentDrawer(role) {
  if (!latestRun) return;
  openAgentDrawerRole = role;
  const manifest = AGENT_MANIFEST.find((a) => a.role === role);
  if (!manifest) return;
  const taskMap = new Map((latestRun.pipeline || []).map((t) => [t.agent_role, t]));
  const task = taskMap.get(role);
  const st = task?.status || "pending";
  agentDrawerIconEl.textContent = manifest.icon;
  agentDrawerTitleEl.textContent = manifest.name;
  agentDrawerStatusEl.textContent = titleCase(st);
  agentDrawerStatusEl.className = `agent-drawer-status status-pill ${statusClass(st)}`;
  agentDrawerBodyEl.innerHTML = renderAgentDrawerBody(role, latestRun);
  agentDrawerBackdropEl.hidden = false;
  agentDrawerEl.classList.add("is-open");
  agentDrawerEl.setAttribute("aria-hidden", "false");
}

function closeAgentDrawer() {
  agentDrawerEl.classList.remove("is-open");
  agentDrawerEl.setAttribute("aria-hidden", "true");
  agentDrawerBackdropEl.hidden = true;
  openAgentDrawerRole = null;
}

function renderAgentDrawerBody(role, run) {
  const arts = run?.artifacts || {};
  if (role === "survey") return renderSurveyDrawer(arts);
  if (role === "ideation") return renderIdeationDrawer(arts, run);
  if (role === "theory") return renderTheoryDrawer(arts);
  if (role === "experiment") return renderExperimentDrawer(arts);
  if (role === "writer") return renderWriterDrawer(run);
  return `<p class="drawer-empty">No detail available for this agent.</p>`;
}

function renderSurveyDrawer(arts) {
  const brief = arts.research_brief || {};
  const papers = arts.bibliography?.papers || brief.papers || [];
  const problems = brief.open_problems || [];
  const keyObjects = brief.key_objects || brief.key_mathematical_objects || [];
  if (!papers.length && !problems.length) {
    return `<div class="drawer-empty-state"><span>📚</span><p>Survey hasn't run yet — results will appear here once the literature scan completes.</p></div>`;
  }
  return `
    ${papers.length ? `
    <div class="drawer-section">
      <h4>Papers surveyed</h4>
      <div class="drawer-paper-list">
        ${papers.slice(0, 15).map((p) => `
          <div class="drawer-paper-row">
            <span class="drawer-paper-year">${escapeHtml(String(p.year || "—"))}</span>
            <span>${escapeHtml(p.title || "Untitled")}</span>
          </div>
        `).join("")}
        ${papers.length > 15 ? `<p class="drawer-more">and ${papers.length - 15} more papers…</p>` : ""}
      </div>
    </div>` : ""}
    ${problems.length ? `
    <div class="drawer-section">
      <h4>Open problems identified</h4>
      <ul class="drawer-problems-list">
        ${problems.map((p) => `<li>${escapeHtml(typeof p === "string" ? p : p.description || JSON.stringify(p))}</li>`).join("")}
      </ul>
    </div>` : ""}
    ${keyObjects.length ? `
    <div class="drawer-section">
      <h4>Key mathematical objects</h4>
      <div class="drawer-tags-row">
        ${keyObjects.slice(0, 12).map((obj) => `<span class="drawer-object-tag">${escapeHtml(typeof obj === "string" ? obj : obj.name || JSON.stringify(obj))}</span>`).join("")}
      </div>
    </div>` : ""}
  `;
}

function renderIdeationDrawer(arts, run) {
  const brief = arts.research_brief || {};
  const direction = brief.selected_direction;
  const dirStr = typeof direction === "string" ? direction : direction?.title || direction?.direction || "";
  const mode = run?.input_spec?.mode;
  const conj = run?.input_spec?.conjecture || run?.input_spec?.query || "";
  return `
    <div class="drawer-section">
      <h4>Research direction</h4>
      ${dirStr
        ? `<blockquote class="drawer-direction-quote">${escapeHtml(dirStr)}</blockquote>`
        : (mode === "detailed" && conj
          ? `<p class="drawer-muted">Using your conjecture as the research direction.</p>
             <blockquote class="drawer-direction-quote">${escapeHtml(conj)}</blockquote>`
          : `<p class="drawer-muted">No direction generated yet — ideation will run after the literature survey completes.</p>`)
      }
    </div>
    ${brief.domain ? `
    <div class="drawer-section">
      <h4>Research domain</h4>
      <p>${escapeHtml(brief.domain)}</p>
    </div>` : ""}
  `;
}

function renderTheoryDrawer(arts) {
  const ts = arts.theory_state;
  if (!ts) return `<div class="drawer-empty-state"><span>📐</span><p>The proof hasn't started yet — the theorem sketch will appear here once the theory agent begins its work.</p></div>`;
  return renderProofSketchHtml(ts);
}

function renderExperimentDrawer(arts) {
  const er = arts.experiment_result;
  if (!er) return `<div class="drawer-empty-state"><span>🧪</span><p>Experimental results will appear here after the validation stage runs.</p></div>`;
  const bounds = er.bounds || [];
  const score = er.alignment_score;
  return `
    <div class="drawer-section">
      <h4>Alignment score</h4>
      <div class="drawer-alignment-row">
        <span class="drawer-alignment-score">${score != null ? (score * 100).toFixed(0) + "%" : "—"}</span>
        <span class="drawer-muted">1.0 = theory matches simulation perfectly</span>
      </div>
    </div>
    ${bounds.length ? `
    <div class="drawer-section">
      <h4>Bounds verification</h4>
      <table class="drawer-bounds-table">
        <thead><tr><th>Bound</th><th>Theoretical</th><th>Empirical</th><th></th></tr></thead>
        <tbody>
          ${bounds.map((b) => `
            <tr>
              <td>${escapeHtml(b.name || "—")}</td>
              <td>${escapeHtml(String(b.theoretical ?? "—"))}</td>
              <td>${escapeHtml(String(b.empirical ?? "—"))}</td>
              <td class="${b.passes ? "drawer-bounds-pass" : "drawer-bounds-fail"}">${b.passes ? "✓" : "✗"}</td>
            </tr>
          `).join("")}
        </tbody>
      </table>
    </div>` : ""}
    ${er.description ? `<div class="drawer-section"><h4>Description</h4><p>${escapeHtml(er.description)}</p></div>` : ""}
  `;
}

function renderWriterDrawer(run) {
  const paper = run?.result?.latex_paper || "";
  const outputDir = run?.output_dir || "";
  if (!paper && !outputDir) return `<div class="drawer-empty-state"><span>✍️</span><p>The paper will appear here once the writer agent completes its draft.</p></div>`;
  const words = paper ? paper.split(/\s+/).filter(Boolean).length : 0;
  const preview = paper ? paper.slice(0, 800) : "";
  return `
    ${words > 0 ? `
    <div class="drawer-section">
      <h4>Draft overview</h4>
      <p class="drawer-word-count">${words.toLocaleString()} words</p>
      ${outputDir ? `<p class="drawer-muted">Saved to: <code>${escapeHtml(outputDir)}</code></p>` : ""}
    </div>` : ""}
    ${preview ? `
    <div class="drawer-section">
      <h4>Paper excerpt</h4>
      <pre class="drawer-paper-excerpt">${escapeHtml(preview)}${paper.length > 800 ? "\n…" : ""}</pre>
    </div>` : ""}
  `;
}

// ── Proof sketch HTML builder ─────────────────────────────────────────────────

function renderProofSketchHtml(ts) {
  if (!ts) return `<div class="drawer-empty-state"><span>📐</span><p>No theory state available.</p></div>`;

  const theorem = ts.formal_statement || ts.proof_skeleton || "";
  const lemmas = ts.open_goals || [];
  const provenLemmas = ts.proven_lemmas || {};
  const counterexamples = ts.counterexamples || [];
  const iteration = ts.iteration ?? 0;

  // Build lemma rows: proven + open
  const provenEntries = Object.entries(provenLemmas).map(([name, proof]) => ({
    name, proof: typeof proof === "string" ? proof : JSON.stringify(proof),
    proven: true, conf: "verified"
  }));
  const openEntries = lemmas.map((g, i) => {
    const name = typeof g === "string" ? g : (g.name || `Goal ${i + 1}`);
    const conf = g.confidence || (g.status === "proven" ? "verified" : "low");
    return { name, proof: typeof g === "string" ? "" : (g.description || ""), proven: false, conf };
  });

  const allLemmas = [...provenEntries, ...openEntries];

  const lemmaChainHtml = allLemmas.length ? `
    <div class="proof-lemma-chain">
      ${allLemmas.map((l, i) => `
        <div class="proof-lemma-row">
          <span class="proof-lemma-number">${i + 1}</span>
          <div class="proof-lemma-content">
            <span class="proof-lemma-name">${escapeHtml(l.name)}</span>
            ${l.proof ? `<span class="proof-lemma-formal">${escapeHtml(l.proof.slice(0, 160))}${l.proof.length > 160 ? "…" : ""}</span>` : ""}
          </div>
          <span class="proof-lemma-badge badge-${escapeHtml(l.conf)}">${escapeHtml(l.conf)}</span>
        </div>
      `).join("")}
    </div>
  ` : `<p class="drawer-muted">No lemmas yet — the proof structure will appear as the theory agent works.</p>`;

  const counterHtml = counterexamples.length ? `
    <div class="proof-counterexample-warning">
      ⚠ ${counterexamples.length} counterexample${counterexamples.length > 1 ? "s" : ""} found — the theorem may need refinement.
    </div>
  ` : "";

  return `
    ${theorem ? `
    <div class="proof-theorem-block">
      <p class="proof-theorem-label">Theorem statement</p>
      <pre class="proof-theorem-text">${escapeHtml(theorem.slice(0, 600))}${theorem.length > 600 ? "\n…" : ""}</pre>
    </div>` : ""}
    ${iteration > 0 ? `<p class="drawer-muted">Iteration ${iteration} · ${provenEntries.length} proven · ${openEntries.length} open</p>` : ""}
    ${counterHtml}
    ${allLemmas.length ? `<h4 style="margin:12px 0 6px">Proof steps</h4>` : ""}
    ${lemmaChainHtml}
  `;
}

function renderProofSketch(theoryState) {
  if (!proofSketchPanelEl) return;
  if (!theoryState) {
    proofSketchPanelEl.innerHTML = `
      <div class="proof-sketch-empty">
        <span>📐</span>
        <p>The proof sketch will appear here once the theory agent starts building the argument.</p>
      </div>
    `;
    return;
  }
  proofSketchPanelEl.innerHTML = `<div class="drawer-section">${renderProofSketchHtml(theoryState)}</div>`;
}

// ── Live panel ─────────────────────────────────────────────────────────────────

function renderLivePanel(run) {
  if (!liveActivityAreaEl) return;
  if (!run) {
    liveActivityAreaEl.innerHTML = `<div class="live-idle-state"><span>🔬</span><p>Start a session to see live research activity.</p></div>`;
    return;
  }

  const status = run.status;
  const pipeline = run.pipeline || [];
  const arts = run.artifacts || {};
  const activeOuter = getActiveOuterStage(pipeline);

  // Direction gate: show when no directions found and ideation is done
  const brief = arts.research_brief || {};
  const dirs = brief.directions || brief.research_directions || [];
  const ideationDone = pipeline.some((t) => (t.name === "ideation" || t.name === "direction_selection_gate") && t.status === "completed");
  if (ideationDone && dirs.length === 0 && status !== "completed" && status !== "failed") {
    const conj = run.input_spec?.conjecture || run.input_spec?.query || "";
    liveActivityAreaEl.innerHTML = `
      <div class="direction-gate-card">
        <p class="direction-gate-heading">📍 No research directions were generated</p>
        <p class="drawer-muted">Ideation returned no candidate directions. EurekaClaw will use your original conjecture as the proof target:</p>
        ${conj ? `<blockquote class="drawer-direction-quote">${escapeHtml(conj)}</blockquote>` : ""}
        <p class="drawer-muted">The theory agent will proceed with this direction. If you'd like to guide the proof differently, pause the session and use the feedback box below.</p>
      </div>
    `;
    return;
  }

  if (status === "running" || status === "queued") {
    const innerStage = run.paused_stage || "";
    const innerLabel = innerStage ? `while ${friendlyInnerStage(innerStage)}` : "";
    const stageName = activeOuter ? AGENT_MANIFEST.find((a) => a.role === activeOuter)?.name || titleCase(activeOuter) : "Setting up";
    liveActivityAreaEl.innerHTML = `
      <div class="live-thinking-view">
        <div class="thinking-dots" aria-label="Working">
          <span class="thinking-dot"></span>
          <span class="thinking-dot"></span>
          <span class="thinking-dot"></span>
        </div>
        <p class="live-stage-label">${escapeHtml(stageName)} ${escapeHtml(innerLabel)}</p>
        <p class="drawer-muted live-stage-sub">${escapeHtml(agentNarrativeLine(activeOuter || "survey", new Map(pipeline.map((t) => [t.agent_role, t])), run))}</p>
      </div>
    `;
    return;
  }

  if (status === "paused" || status === "pausing") {
    liveActivityAreaEl.innerHTML = `
      <div class="live-thinking-view">
        <p class="live-stage-label" style="color:var(--amber)">⏸ Session paused</p>
        <p class="drawer-muted">Use the Resume button to continue, or add feedback below to guide the next proof attempt.</p>
      </div>
    `;
    return;
  }

  if (status === "completed") {
    const dir = typeof brief.selected_direction === "string"
      ? brief.selected_direction
      : (brief.selected_direction?.title || "");
    liveActivityAreaEl.innerHTML = `
      <div class="live-thinking-view">
        <p class="live-stage-label" style="color:var(--green)">✓ Research complete</p>
        ${dir ? `<blockquote class="drawer-direction-quote">${escapeHtml(dir)}</blockquote>` : ""}
        <p class="drawer-muted">Switch to the <strong>Paper</strong> tab to read the draft, or <strong>Proof</strong> for the theorem sketch.</p>
      </div>
    `;
    return;
  }

  if (status === "failed") {
    liveActivityAreaEl.innerHTML = `
      <div class="live-thinking-view">
        <p class="live-stage-label" style="color:var(--red)">✗ Session failed</p>
        <p class="drawer-muted">${escapeHtml(run.error || "An error occurred. Check the Logs tab for details.")}</p>
      </div>
    `;
    return;
  }

  liveActivityAreaEl.innerHTML = `<div class="live-idle-state"><span>🔬</span><p>Waiting for session to begin…</p></div>`;
}

// ── Theory feedback section ───────────────────────────────────────────────────

function updateTheoryFeedbackSection(theoryState, isPaused) {
  if (!theoryFeedbackSectionEl) return;
  // Only show when paused
  theoryFeedbackSectionEl.hidden = !isPaused;
  if (!isPaused || !theoryFeedbackLemmaListEl) return;

  // Populate lemma chips
  const lemmas = theoryState ? (theoryState.open_goals || []) : [];
  const provenLemmas = theoryState ? Object.keys(theoryState.proven_lemmas || {}) : [];
  const allLemmaNames = [
    ...provenLemmas,
    ...lemmas.map((g, i) => (typeof g === "string" ? g : (g.name || `Goal ${i + 1}`)))
  ];

  if (allLemmaNames.length) {
    theoryFeedbackLemmaListEl.innerHTML = allLemmaNames.map((name) => `
      <button type="button" class="theory-feedback-lemma-chip" data-lemma="${escapeHtml(name)}">
        ${escapeHtml(name.length > 40 ? name.slice(0, 40) + "…" : name)}
      </button>
    `).join("");
  } else {
    theoryFeedbackLemmaListEl.innerHTML = `<span class="drawer-muted" style="font-size:0.8rem">No lemmas yet</span>`;
  }
}

// ── Workspace tab switching ───────────────────────────────────────────────────

function switchWsTab(tabKey) {
  activeWsTab = tabKey;
  document.querySelectorAll(".ws-tab").forEach((btn) => {
    btn.classList.toggle("is-active", btn.dataset.wsTab === tabKey);
  });
  document.querySelectorAll(".ws-panel").forEach((panel) => {
    panel.classList.toggle("is-visible", panel.id === `ws-panel-${tabKey}`);
  });
}

function maybeAutoSwitchTab(run, prevRun) {
  if (!run) return;
  const tasks = run.pipeline || [];
  const theoryTask = tasks.find((t) => t.name === "theory" || t.agent_role === "theory");
  const wasRunning = prevRun?.pipeline?.find((t) => (t.name === "theory" || t.agent_role === "theory"))?.status === "in_progress";
  const nowDone = theoryTask?.status === "completed";
  // Auto-switch to Proof when theory just completed
  if (wasRunning && nowDone && activeWsTab === "live") {
    switchWsTab("proof");
  }
  // Auto-switch to Paper when run completes
  if (prevRun?.status !== "completed" && run.status === "completed" && activeWsTab === "live") {
    switchWsTab("paper");
  }
}

// ── Log humanizer ────────────────────────────────────────────────────────────

function humanizeLogMessage(taskName, eventType, detail) {
  const name = taskName || "";
  const role = STAGE_TASK_MAP[name] || name;
  const manifest = AGENT_MANIFEST.find((a) => a.role === role);
  const agentName = manifest?.name || titleCase(name);

  if (eventType === "started") {
    const starts = {
      survey: "📚 Literature survey started — scanning recent papers",
      ideation: "💡 Idea generation started — exploring research directions",
      theory: "📐 Theorem proving started — architecting the proof",
      experiment: "🧪 Validation started — running numerical experiments",
      writer: "✍️ Paper writing started — composing the manuscript",
      direction_selection_gate: "🧭 Selecting research direction…",
      theory_review_gate: "🔍 Theory review gate reached",
      final_review_gate: "✅ Final review gate reached",
    };
    return starts[name] || `${agentName} started`;
  }

  if (eventType === "completed") {
    const done = {
      survey: "📚 Literature survey complete — research brief ready",
      ideation: "💡 Directions generated — research direction selected",
      theory: "📐 Proof complete — theorem sketch ready for review",
      experiment: "🧪 Experiments finished — bounds verified",
      writer: "✍️ Paper draft complete",
      direction_selection_gate: "🧭 Direction confirmed",
      theory_review_gate: "🔍 Theory reviewed — proceeding to validation",
      final_review_gate: "✅ Final review complete",
    };
    return done[name] || `${agentName} complete`;
  }

  if (eventType === "error") {
    return `⚠ ${agentName} encountered an issue${detail ? ": " + detail : ""}`;
  }

  return `${agentName} ${eventType}`;
}

function renderLogs(run, tasks) {
  const items = [];
  if (run?.created_at) {
    items.push({ time: run.created_at, message: "🔬 Research session created", tone: "" });
  }
  (tasks || []).forEach((task) => {
    if (task.started_at) {
      items.push({
        time: task.started_at,
        message: humanizeLogMessage(task.name, "started", ""),
        tone: ""
      });
    }
    if (task.completed_at && task.status !== "failed") {
      items.push({
        time: task.completed_at,
        message: humanizeLogMessage(task.name, "completed", ""),
        tone: ""
      });
    }
    if (task.error_message) {
      items.push({
        time: task.completed_at || task.started_at || run?.created_at,
        message: humanizeLogMessage(task.name, "error", task.error_message),
        tone: "warning"
      });
    }
  });

  if (!items.length) {
    logStreamEl.innerHTML = `
      <div class="log-line">
        <span class="mono-label">--:--:--</span>
        <p>Run events will appear here once a session starts.</p>
      </div>
    `;
    logPaginationEl.innerHTML = "";
    return;
  }

  items.sort((a, b) => {
    const timeA = parseServerTimestamp(a.time)?.getTime() || 0;
    const timeB = parseServerTimestamp(b.time)?.getTime() || 0;
    return timeA - timeB;
  });
  const totalPages = Math.max(1, Math.ceil(items.length / logsPerPage));
  currentLogPage = Math.min(currentLogPage, totalPages);
  const startIndex = (currentLogPage - 1) * logsPerPage;
  const visibleItems = items.slice(startIndex, startIndex + logsPerPage);

  logStreamEl.innerHTML = visibleItems
    .map((item) => {
      const time = formatLocalTimestamp(item.time);
      return `
        <div class="log-line ${item.tone}">
          <span class="mono-label">${escapeHtml(time)}</span>
          <p>${escapeHtml(item.message)}</p>
        </div>
      `;
    })
    .join("");

  logPaginationEl.innerHTML = totalPages > 1 ? `
    <button type="button" class="ghost-btn" data-log-page="prev" ${currentLogPage === 1 ? "disabled" : ""}>Previous</button>
    <span class="log-pagination-meta">Page ${currentLogPage} / ${totalPages}</span>
    <button type="button" class="ghost-btn" data-log-page="next" ${currentLogPage === totalPages ? "disabled" : ""}>Next</button>
  ` : "";
}

function renderOutput(run) {
  const theoryState = run?.artifacts?.theory_state;
  const result = run?.result;
  const title = run?.artifacts?.research_brief?.selected_direction?.title || "EurekaClaw Autonomous Research System";
  const paperText = result?.latex_paper || "";
  let summary = "Launch a session to produce a real paper draft and final run summary.";

  if (run?.status === "completed") {
    summary = paperText
      ? `${paperText.slice(0, 280)}...`
      : "The run completed and output artifacts are available, but no paper text was returned.";
  } else if (run?.status === "running") {
    summary = "The writer surface will populate as the pipeline produces theory and experiment artifacts.";
  } else if (run?.status === "failed") {
    summary = run.error || "The run failed before a paper could be generated.";
  }

  paperPreviewEl.innerHTML = `
    <div class="paper-sheet">
      <p class="paper-title">${escapeHtml(title)}</p>
      <p class="paper-meta">Status: ${escapeHtml(titleCase(run?.status || "not started"))}</p>
      <p>${escapeHtml(summary)}</p>
      ${
        theoryState
          ? `<p class="paper-meta">Proven lemmas: ${escapeHtml(String(Object.keys(theoryState.proven_lemmas || {}).length))} | Open goals: ${escapeHtml(String((theoryState.open_goals || []).length))}</p>`
          : ""
      }
    </div>
  `;
}

function updateSidebar(run) {
  if (!run) return;
  const item = sessionListEl.querySelector(`[data-run-id="${run.run_id}"]`);
  if (!item) return;
  const dot = item.querySelector(".session-status-dot");
  if (dot) dot.className = `session-status-dot ${run.status}`;
  sessionListEl.querySelectorAll(".session-item").forEach((el) => {
    el.classList.toggle("is-active", el.dataset.runId === currentRunId);
  });
}

// ── Stage name helpers ────────────────────────────────────────────────────────

// Maps outer pipeline task names → track stage keys
const STAGE_TASK_MAP = {
  survey: "survey",
  ideation: "ideation",
  direction_selection_gate: "ideation",
  theory: "theory",
  theory_review_gate: "theory",
  experiment: "experiment",
  final_review_gate: "experiment",
  writer: "writer",
};

// Maps Theory inner-loop stage names → readable descriptions
const INNER_STAGE_LABELS = {
  ArchitectAgent: "planning the proof structure",
  LemmaDeveloper: "developing key lemmas",
  Verifier: "checking the proof",
  CrystallizerAgent: "crystallising the theorem",
  CompressAgent: "compressing context",
  FormalAgent: "formalising the proof",
  AssemblerAgent: "assembling the argument",
};

function getActiveOuterStage(pipeline) {
  if (!pipeline || !pipeline.length) return null;
  const running = pipeline.find((t) => t.status === "in_progress" || t.status === "running");
  if (running) return STAGE_TASK_MAP[running.name] || null;
  // Fall back: last completed task
  const done = pipeline.filter((t) => t.status === "completed");
  if (done.length) return STAGE_TASK_MAP[done[done.length - 1].name] || null;
  return null;
}

function friendlyInnerStage(rawStage) {
  if (!rawStage) return null;
  return INNER_STAGE_LABELS[rawStage] || rawStage.replace(/Agent$/, "").replace(/([A-Z])/g, " $1").trim().toLowerCase();
}

// ── Stage track renderer ──────────────────────────────────────────────────────

function renderStageTrack(run) {
  if (!proofCtrlTrackEl) return;
  const status = run ? run.status : null;
  const pipeline = run ? (run.pipeline || []) : [];
  const activeOuter = getActiveOuterStage(pipeline);
  const isPaused = status === "paused" || status === "pausing";

  const stageOrder = ["survey", "ideation", "theory", "experiment", "writer"];

  stageOrder.forEach((stageKey) => {
    const el = proofCtrlTrackEl.querySelector(`[data-stage="${stageKey}"]`);
    if (!el) return;

    // Determine completion: any task mapping to this stage is completed
    const tasksForStage = pipeline.filter((t) => STAGE_TASK_MAP[t.name] === stageKey);
    const isCompleted = tasksForStage.length > 0 && tasksForStage.every((t) => t.status === "completed");
    const isActive = activeOuter === stageKey;
    const isPausedHere = isPaused && stageKey === "theory"; // pause only in theory

    el.classList.remove("is-active", "is-done", "is-paused");
    if (isCompleted) el.classList.add("is-done");
    else if (isPausedHere) el.classList.add("is-paused");
    else if (isActive) el.classList.add("is-active");
  });

  // Update connectors — fill up to the active stage
  const connectors = proofCtrlTrackEl.querySelectorAll(".pct-connector");
  let activeIdx = stageOrder.indexOf(activeOuter);
  if (activeIdx < 0) activeIdx = -1;
  connectors.forEach((c, i) => {
    c.classList.toggle("is-filled", i < activeIdx || (activeIdx < 0 && pipeline.some((t) => t.status === "completed")));
  });
}

// ── Pause caption based on current outer stage ────────────────────────────────

function updateRunningCaption(run) {
  const pipeline = run ? (run.pipeline || []) : [];
  const activeOuter = getActiveOuterStage(pipeline);

  const labels = {
    survey: { label: "Reading papers", sub: "Searching the literature — pause will queue for the proof stage" },
    ideation: { label: "Generating ideas", sub: "Exploring hypotheses — pause will queue for the proof stage" },
    theory: { label: "Proving the theorem", sub: "Pause will stop safely at the next proof checkpoint" },
    experiment: { label: "Running experiments", sub: "Validating the theory numerically" },
    writer: { label: "Writing the paper", sub: "Assembling your LaTeX paper" },
  };

  const info = labels[activeOuter] || { label: "Research in progress", sub: "EurekaClaw is thinking…" };

  if (proofCtrlLiveLabelEl) proofCtrlLiveLabelEl.textContent = info.label;
  if (proofCtrlLiveSubEl) proofCtrlLiveSubEl.textContent = info.sub;

  // Hint text below button
  if (proofCtrlRunningHintEl) {
    if (activeOuter === "theory") {
      proofCtrlRunningHintEl.textContent = "Your progress is safe — EurekaClaw will stop at the next natural checkpoint.";
    } else if (activeOuter === "experiment" || activeOuter === "writer") {
      proofCtrlRunningHintEl.textContent = "The theorem proof is complete. Pause is not available at this stage.";
      if (pauseSessionBtn) { pauseSessionBtn.disabled = true; pauseSessionBtn.style.opacity = "0.4"; }
    } else {
      proofCtrlRunningHintEl.textContent = "Pause will take effect when theorem-proving begins.";
      if (pauseSessionBtn) { pauseSessionBtn.disabled = false; pauseSessionBtn.style.opacity = ""; }
    }
    // Re-enable for theory
    if (activeOuter === "theory" && pauseSessionBtn) {
      pauseSessionBtn.disabled = false;
      pauseSessionBtn.style.opacity = "";
    }
  }
}

// ── Elapsed timer for "Pausing…" state ───────────────────────────────────────
function startElapsedTimer(fromDate) {
  stopElapsedTimer();
  pauseRequestedAt = fromDate || new Date();
  function tick() {
    const secs = Math.round((Date.now() - pauseRequestedAt.getTime()) / 1000);
    if (pauseElapsedEl) pauseElapsedEl.textContent = secs < 2 ? "" : `${secs}s`;
  }
  tick();
  elapsedTimer = setInterval(tick, 1000);
}
function stopElapsedTimer() {
  if (elapsedTimer) { clearInterval(elapsedTimer); elapsedTimer = null; }
  if (pauseElapsedEl) pauseElapsedEl.textContent = "";
  pauseRequestedAt = null;
}

// ── Proof-ctrl state machine ──────────────────────────────────────────────────
function updateSessionControls(run) {
  const status = run ? run.status : null;
  const isRunning = status === "running";
  const isPausing = status === "pausing" || (status === "running" && isPausingRequested);
  const isPaused = status === "paused";
  const isResuming = status === "resuming";
  const isFailed = status === "failed";
  const showCtrl = isRunning || isPausing || isPaused || isResuming;

  // Sync local optimistic flag with authoritative server status
  if (status === "pausing" || status === "paused" || status === "resuming") {
    isPausingRequested = false;
  }

  // Elapsed timer
  if (isPausing && !elapsedTimer) {
    const fromDate = run && run.pause_requested_at ? new Date(run.pause_requested_at) : null;
    startElapsedTimer(fromDate);
  } else if (!isPausing) {
    stopElapsedTimer();
  }

  // Entry animations
  if (isPaused && proofCtrlPausedEl && proofCtrlPausedEl.hidden) {
    proofCtrlPausedEl.classList.remove("ctrl-flash-in");
    requestAnimationFrame(() => proofCtrlPausedEl.classList.add("ctrl-flash-in"));
  }
  if (isRunning && !isPausingRequested && proofCtrlRunningEl && proofCtrlRunningEl.hidden) {
    proofCtrlRunningEl.classList.remove("ctrl-flash-in");
    requestAnimationFrame(() => proofCtrlRunningEl.classList.add("ctrl-flash-in"));
  }

  // Outer container
  proofCtrlEl.hidden = !showCtrl;

  // Sub-states (mutually exclusive)
  proofCtrlRunningEl.hidden = !isRunning || isPausing;
  proofCtrlPausingEl.hidden = !isPausing;
  proofCtrlPausedEl.hidden = !isPaused;
  proofCtrlResumingEl.hidden = !isResuming;

  // Stage track (shown in all active states)
  if (proofCtrlTrackEl) proofCtrlTrackEl.hidden = false;
  renderStageTrack(run);

  // Running caption
  if (isRunning && !isPausing) updateRunningCaption(run);

  // Paused details
  if (isPaused && run) {
    if (proofCtrlSessionIdEl && run.session_id) {
      proofCtrlSessionIdEl.textContent = run.session_id.slice(0, 16) + "…";
      proofCtrlSessionIdEl.title = `eurekaclaw resume ${run.session_id}`;
    }
    if (proofCtrlPausedStageEl) {
      const friendly = run.paused_stage ? friendlyInnerStage(run.paused_stage) : null;
      proofCtrlPausedStageEl.textContent = friendly
        ? `Paused while ${friendly}`
        : "Ready to continue whenever you are";
    }
  }

  // Failed session note
  failedSessionNoteEl.hidden = !isFailed;
  if (isFailed && failedSessionErrorTextEl) {
    const errMsg = run && run.error ? `Error: ${run.error}` : "";
    failedSessionErrorTextEl.textContent = errMsg;
    failedSessionErrorTextEl.hidden = !errMsg;
  }
}

async function apiGet(path) {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }
  return response.json();
}

async function apiPost(path, payload) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const errorText = await response.text();
    if (response.status === 501 && errorText.includes("Unsupported method")) {
      throw new Error(
        "This page is being served by a static file server. Start the real backend with `eurekaclaw ui` and open http://127.0.0.1:8080/."
      );
    }
    throw new Error(errorText || `Request failed: ${response.status}`);
  }
  return response.json();
}

async function apiDelete(path) {
  const response = await fetch(path, { method: "DELETE" });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(errorText || `Request failed: ${response.status}`);
  }
  return response.json();
}

async function deleteRun(runId) {
  if (!confirm("Delete this session? This cannot be undone.")) return;
  try {
    await apiDelete(`/api/runs/${runId}`);
    allSessions = allSessions.filter((s) => s.run_id !== runId);
    if (currentRunId === runId) {
      stopPolling();
      currentRunId = null;
      currentLogPage = 1;
      renderRun(null);
    }
    renderSessionList(allSessions);
  } catch (error) {
    alert(`Could not delete session: ${error.message}`);
  }
}

function configPayloadFromForm() {
  const payload = Object.fromEntries(new FormData(configFormEl).entries());
  configFormEl.querySelectorAll('input[type="checkbox"]').forEach((field) => {
    payload[field.name] = field.checked;
  });
  return payload;
}

function skillSearchText(skill) {
  return [
    skill.name,
    skill.description,
    ...(skill.tags || []),
    ...(skill.agent_roles || []),
    ...(skill.pipeline_stages || []),
    skill.source
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function toggleSkill(name) {
  if (selectedSkills.includes(name)) {
    selectedSkills = selectedSkills.filter((skillName) => skillName !== name);
  } else {
    selectedSkills = [...selectedSkills, name];
  }
  renderSkillIntent();
}

// Source badge label + CSS class
function skillSourceClass(source) {
  return `skill-source--${(source || "manual").replace(/[^a-z]/g, "")}`;
}

function skillSourceLabel(source) {
  return { seed: "seed", distilled: "auto-learned", manual: "manual", clawhub: "ClawHub" }[source] || source || "manual";
}

// Is the skill deletable (user-installed, not a bundled seed)?
function skillIsDeletable(skill) {
  return skill.source !== "seed" && skill.file_path && skill.file_path.includes(".eurekaclaw");
}

function renderSkillIntent() {
  const query = skillSearchEl.value.trim().toLowerCase();
  const filtered = availableSkills
    .filter((skill) => !query || skillSearchText(skill).includes(query))
    .sort((a, b) => {
      const aSelected = selectedSkills.includes(a.name) ? 1 : 0;
      const bSelected = selectedSkills.includes(b.name) ? 1 : 0;
      if (aSelected !== bSelected) return bSelected - aSelected;
      return a.name.localeCompare(b.name);
    });
  const totalPages = Math.max(1, Math.ceil(filtered.length / skillsPerPage));
  currentSkillPage = Math.min(currentSkillPage, totalPages);
  const startIndex = (currentSkillPage - 1) * skillsPerPage;
  const visibleSkills = filtered.slice(startIndex, startIndex + skillsPerPage);

  skillSelectedEl.innerHTML = selectedSkills.length
    ? selectedSkills.map((name) => `
        <span class="intent-chip">
          <span>${escapeHtml(name)}</span>
          <button type="button" data-remove-skill="${escapeHtml(name)}" aria-label="Remove ${escapeHtml(name)}">×</button>
        </span>
      `).join("")
    : '<div class="intent-empty">No skills selected — select from the library.</div>';

  if (!filtered.length) {
    skillListEl.innerHTML = '<div class="intent-empty">No skills match this search.</div>';
    skillMetaEl.textContent = `${selectedSkills.length} selected`;
    skillPaginationEl.innerHTML = "";
    return;
  }

  skillListEl.innerHTML = visibleSkills.map((skill) => {
    const isSelected = selectedSkills.includes(skill.name);
    const deletable = skillIsDeletable(skill);
    const usageCount = skill.usage_count || 0;
    const successRate = skill.success_rate;

    const stagesHtml = (skill.pipeline_stages || []).slice(0, 3)
      .map((s) => `<span class="skill-pipeline-tag">${escapeHtml(s)}</span>`).join("");
    const tagsHtml = (skill.tags || []).slice(0, 3)
      .map((t) => `<span class="intent-tag">${escapeHtml(t)}</span>`).join("");

    const statsHtml = (usageCount > 0 || successRate != null) ? `
      <div class="skill-stats-bar">
        ${usageCount > 0 ? `<span class="skill-usage-badge">${usageCount} use${usageCount !== 1 ? "s" : ""}</span>` : ""}
        ${successRate != null ? `
          <span class="skill-success-label">${Math.round(successRate * 100)}% success</span>
          <div class="skill-success-track"><div class="skill-success-fill" style="width:${Math.round(successRate * 100)}%"></div></div>
        ` : ""}
      </div>` : "";

    return `
      <div class="intent-skill-wrap ${isSelected ? "is-selected" : ""}">
        <button type="button" class="intent-skill" data-skill-name="${escapeHtml(skill.name)}">
          <div class="intent-skill-head">
            <span class="intent-skill-name">${escapeHtml(skill.name)}</span>
            <span class="intent-skill-source ${skillSourceClass(skill.source)}">${escapeHtml(skillSourceLabel(skill.source))}</span>
          </div>
          <p class="intent-skill-desc">${escapeHtml(skill.description || "No description.")}</p>
          <div class="intent-tag-row">
            ${stagesHtml}
            ${tagsHtml}
          </div>
          ${statsHtml}
        </button>
        ${deletable ? `<button type="button" class="skill-delete-btn" data-delete-skill="${escapeHtml(skill.name)}" title="Remove '${escapeHtml(skill.name)}' from ~/.eurekaclaw/skills/">🗑</button>` : ""}
      </div>
    `;
  }).join("");

  const matchingText = query ? `${filtered.length} matching` : `${availableSkills.length} available`;
  skillMetaEl.textContent = `${selectedSkills.length} selected · ${matchingText} · page ${currentSkillPage}/${totalPages}`;
  skillPaginationEl.innerHTML = totalPages > 1 ? `
    <button type="button" class="ghost-btn" data-skill-page="prev" ${currentSkillPage === 1 ? "disabled" : ""}>← Prev</button>
    <span class="skill-pagination-meta">${currentSkillPage} / ${totalPages}</span>
    <button type="button" class="ghost-btn" data-skill-page="next" ${currentSkillPage === totalPages ? "disabled" : ""}>Next →</button>
  ` : "";
}

// ── ClawHub install / seed install ──────────────────────────────────────────

function showClawHubStatus(message, isError = false) {
  clawhubStatusEl.textContent = message;
  clawhubStatusEl.className = `clawhub-status ${isError ? "is-error" : "is-ok"}`;
  clawhubStatusEl.hidden = false;
}

async function installSkill(skillname) {
  const label = skillname ? `'${skillname}'` : "seed skills";
  clawhubInstallBtn.disabled = true;
  installSeedsBtnEl.disabled = true;
  showClawHubStatus(`Installing ${label}…`);
  try {
    const result = await apiPost("/api/skills/install", { skillname: skillname || "" });
    if (result.ok) {
      showClawHubStatus(`✓ ${result.message}`);
      if (skillname) clawhubInputEl.value = "";
      await loadSkills(); // refresh library
    } else {
      showClawHubStatus(result.error || "Install failed.", true);
    }
  } catch (err) {
    showClawHubStatus(err.message || "Install failed.", true);
  } finally {
    clawhubInstallBtn.disabled = false;
    installSeedsBtnEl.disabled = false;
  }
}

async function deleteSkill(name) {
  if (!confirm(`Remove skill '${name}' from ~/.eurekaclaw/skills/?\n\nThis only deletes your local copy; seed skills remain built-in.`)) return;
  try {
    await apiDelete(`/api/skills/${encodeURIComponent(name)}`);
    availableSkills = availableSkills.filter((s) => s.name !== name);
    selectedSkills = selectedSkills.filter((n) => n !== name);
    renderSkillIntent();
    showClawHubStatus(`Removed '${name}'.`);
  } catch (err) {
    showClawHubStatus(`Could not delete: ${err.message}`, true);
  }
}

function updateConfigVisibility() {
  const payload = configPayloadFromForm();
  const backend = payload.llm_backend || "anthropic";
  const authMode = payload.anthropic_auth_mode || "api_key";

  configConditionalEls.forEach((el) => {
    const rule = el.dataset.configShow || "always";

    if (rule === "always") {
      el.hidden = false;
      return;
    }

    const parts = rule.split(/\s+/).filter(Boolean);
    const visible = parts.every((part) => {
      const [kind, value] = part.split(":");
      if (kind === "backend") {
        return backend === value;
      }
      if (kind === "auth") {
        return authMode === value;
      }
      return true;
    });

    el.hidden = !visible;
  });
}

function setAuthGuidanceOpen(isOpen) {
  authGuidanceShellEl.classList.toggle("is-open", isOpen);
  authGuidanceEl.hidden = !isOpen;
  authGuidanceToggleEl.setAttribute("aria-expanded", String(isOpen));
  authGuidanceToggleMetaEl.textContent = isOpen ? "Tap to hide" : "Tap to view";
}

function renderAuthGuidance() {
  const payload = configPayloadFromForm();
  const backend = payload.llm_backend || "anthropic";
  const authMode = payload.anthropic_auth_mode || "api_key";
  const ccproxyPort = payload.ccproxy_port || "8000";

  let title = "Connection guidance";

  if (backend === "anthropic" && authMode === "oauth") {
    title = "Anthropic OAuth guidance";
    authGuidanceEl.innerHTML = `
      <div>
        <p class="eyebrow">OAuth Guidance</p>
        <h4>Anthropic + OAuth requires local ccproxy setup</h4>
      </div>
      <p>
        This mode does not work from frontend settings alone. EurekaClaw must be
        able to find a working <code>ccproxy</code> binary and a valid OAuth login
        for <code>claude_api</code>.
      </p>
      <div class="hint-grid">
        <div class="hint-card">
          <h5>What to configure</h5>
          <ul>
            <li>Set <code>LLM_BACKEND=anthropic</code></li>
            <li>Set <code>ANTHROPIC_AUTH_MODE=oauth</code></li>
            <li>Choose a <code>CCPROXY_PORT</code> such as <code>${escapeHtml(ccproxyPort)}</code></li>
            <li>Leave <code>ANTHROPIC_API_KEY</code> empty</li>
          </ul>
        </div>
        <div class="hint-card">
          <h5>What must exist locally</h5>
          <ul>
            <li><code>ccproxy</code> installed and on PATH</li>
            <li>OAuth login completed with Claude provider</li>
            <li>The selected port available locally</li>
          </ul>
        </div>
      </div>
      <div>
        <h5>Recommended terminal checks</h5>
        <pre>which ccproxy
ccproxy auth login claude_api
ccproxy auth status claude_api</pre>
      </div>
      <p>
        If <code>Test connection</code> still fails, the most likely causes are:
        missing <code>ccproxy</code>, no OAuth login, wrong port, or missing
        project OAuth dependencies.
      </p>
    `;
    const _tl = authGuidanceToggleEl.querySelector(".auth-guidance-toggle-label"); if (_tl) _tl.textContent = title;
    return;
  }

  if (backend === "anthropic") {
    title = "Anthropic API key guidance";
    authGuidanceEl.innerHTML = `
      <div>
        <p class="eyebrow">API Key Guidance</p>
        <h4>Anthropic API key is the simplest way to get running</h4>
      </div>
      <p>
        Use this path if you want the fastest setup. Fill in
        <code>ANTHROPIC_API_KEY</code>, keep <code>ANTHROPIC_AUTH_MODE=api_key</code>,
        then click <code>Test connection</code>.
      </p>
      <div class="hint-grid">
        <div class="hint-card">
          <h5>Required</h5>
          <ul>
            <li><code>LLM_BACKEND=anthropic</code></li>
            <li><code>ANTHROPIC_AUTH_MODE=api_key</code></li>
            <li>A valid <code>ANTHROPIC_API_KEY</code></li>
          </ul>
        </div>
        <div class="hint-card">
          <h5>Common issues</h5>
          <ul>
            <li>Empty or expired key</li>
            <li>Extra whitespace when pasting</li>
            <li>Model access not enabled for the selected model</li>
          </ul>
        </div>
      </div>
    `;
    const _tl = authGuidanceToggleEl.querySelector(".auth-guidance-toggle-label"); if (_tl) _tl.textContent = title;
    return;
  }

  title = "OpenAI-compatible guidance";
  authGuidanceEl.innerHTML = `
    <div>
      <p class="eyebrow">OpenAI-Compatible Guidance</p>
      <h4>Custom endpoint mode needs base URL, API key, and model</h4>
    </div>
    <p>
      Use this mode for OpenRouter, vLLM, SGLang, LM Studio, or another
      OpenAI-compatible endpoint. All three fields should be treated as required
      unless your provider explicitly documents otherwise.
    </p>
    <div class="hint-grid">
      <div class="hint-card">
        <h5>Required</h5>
        <ul>
          <li><code>OPENAI_COMPAT_BASE_URL</code></li>
          <li><code>OPENAI_COMPAT_API_KEY</code></li>
          <li><code>OPENAI_COMPAT_MODEL</code></li>
        </ul>
      </div>
      <div class="hint-card">
        <h5>Common issues</h5>
        <ul>
          <li>Missing <code>/v1</code> suffix in base URL</li>
          <li>Model name not supported by the endpoint</li>
          <li>OpenAI Python package not installed in the backend environment</li>
        </ul>
      </div>
    </div>
  `;
  const _tl = authGuidanceToggleEl.querySelector(".auth-guidance-toggle-label");
  if (_tl) _tl.textContent = title;
}

const MODE_CONFIG = {
  detailed: {
    promptLabel: "Conjecture / theorem to prove",
    promptPlaceholder: "e.g. The sample complexity of transformers is O(L·d·log(d)/ε²)",
    requirePrompt: true,
    requireDomain: false,
    showPaperIds: false,
  },
  reference: {
    promptLabel: "Research focus (optional)",
    promptPlaceholder: "e.g. Find gaps in sparse attention theory, or leave blank to auto-detect",
    requirePrompt: false,
    requireDomain: true,
    showPaperIds: true,
  },
  exploration: {
    promptLabel: "Guiding question (optional)",
    promptPlaceholder: "e.g. What are the tightest known regret lower bounds for stochastic bandits?",
    requirePrompt: false,
    requireDomain: true,
    showPaperIds: false,
  },
};

function updateModeUI() {
  const mode = inputModeEl.value;
  const cfg = MODE_CONFIG[mode] || MODE_CONFIG.detailed;
  promptLabelEl.textContent = cfg.promptLabel;
  inputPromptEl.placeholder = cfg.promptPlaceholder;
  paperIdsLabel.hidden = !cfg.showPaperIds;
}

function validateInputSpec() {
  const mode = inputModeEl.value;
  const cfg = MODE_CONFIG[mode] || MODE_CONFIG.detailed;
  const domain = inputDomainEl.value.trim();
  const prompt = inputPromptEl.value.trim();

  if (cfg.requireDomain && !domain) {
    return `Research domain is required for ${mode} mode.`;
  }
  if (cfg.requirePrompt && !prompt) {
    return mode === "detailed"
      ? "Please enter the conjecture or theorem you want EurekaClaw to prove."
      : "Research prompt is required for this mode.";
  }
  return null;
}

function normalizeInputSpec() {
  const mode = inputModeEl.value;
  const domain = inputDomainEl.value.trim();
  const prompt = inputPromptEl.value.trim();
  const selectedSkillContext = selectedSkills.length
    ? `User-selected skills: ${selectedSkills.join(", ")}`
    : "";

  const paperIds = (inputPaperIdsEl.value || "")
    .split(/[\n,\s]+/)
    .map((id) => id.trim())
    .filter(Boolean);

  if (mode === "reference") {
    return {
      mode: "reference",
      domain,
      query: prompt || `Find research gaps in ${domain}`,
      paper_ids: paperIds,
      additional_context: selectedSkillContext,
      selected_skills: selectedSkills,
    };
  }

  if (mode === "exploration") {
    return {
      mode: "exploration",
      domain,
      query: prompt || `Survey the frontier of ${domain} and identify open problems`,
      additional_context: selectedSkillContext,
      selected_skills: selectedSkills,
    };
  }

  // detailed (default)
  return {
    mode: "detailed",
    domain,
    conjecture: prompt,
    query: prompt,
    additional_context: selectedSkillContext,
    selected_skills: selectedSkills,
  };
}

async function loadSkills() {
  try {
    const data = await apiGet("/api/skills");
    availableSkills = data.skills || [];
    renderSkillIntent();
  } catch (error) {
    skillListEl.innerHTML = `<div class="intent-empty">${escapeHtml(error.message)}</div>`;
    skillMetaEl.textContent = "Skill bank unavailable";
  }
}

async function loadCapabilities() {
  try {
    const data = await apiGet("/api/capabilities");
    capabilityListEl.innerHTML = Object.entries(data.capabilities)
      .map(([key, value]) => `
        <div class="capability-row">
          <span>${escapeHtml(titleCase(key))}</span>
          <span class="status-pill ${statusClass(value.status)}">${escapeHtml(value.detail)}</span>
        </div>
      `)
      .join("");
  } catch (error) {
    capabilityListEl.innerHTML = `
      <div class="capability-row">
        <span>Capabilities unavailable</span>
        <span class="status-pill status-error">${escapeHtml(error.message)}</span>
      </div>
    `;
  }
}

async function loadConfig() {
  try {
    const data = await apiGet("/api/config");
    Object.entries(data.config).forEach(([key, value]) => {
      const field = configFormEl.elements.namedItem(key);
      if (field) {
        if (field.type === "checkbox") {
          field.checked = value === true || value === "true";
        } else {
          field.value = value ?? "";
        }
        // Sync slider display label if present
        const label = document.getElementById(`${key}-val`);
        if (label) label.textContent = value ?? "";
      }
    });
    updateConfigVisibility();
    renderAuthGuidance();
  } catch (error) {
    configSaveStatusEl.textContent = `Could not load config: ${error.message}`;
  }
}

function renderRun(run) {
  if (!run) {
    showNewSessionPane();
    return;
  }
  const prevRun = latestRun;
  latestRun = run;
  showSessionDetailPane();
  updateSessionTopbar(run);
  const tasks = run?.pipeline || [];
  const theoryState = run?.artifacts?.theory_state;
  const isPaused = run.status === "paused";

  renderAgentTrack(tasks, run);
  renderLivePanel(run);
  renderProofSketch(theoryState);
  renderOutput(run);
  renderLogs(run, tasks);
  renderTokenUsage(tasks);
  updateSidebar(run);
  updateSessionControls(run);
  updateTheoryFeedbackSection(theoryState, isPaused);
  maybeAutoSwitchTab(run, prevRun);
  setRunStatus(run ? run.status : "idle", liveStatusDetail(run));

  // Refresh open drawer if any
  if (openAgentDrawerRole) {
    agentDrawerBodyEl.innerHTML = renderAgentDrawerBody(openAgentDrawerRole, run);
  }
}


// ── Polling engine ──────────────────────────────────────────────────────────
// Adaptive-rate polling: fast (500 ms) while pausing/resuming, normal (1.2 s)
// while running/queued, and idle (3 s) when all sessions are terminal.
// One fetch returns ALL sessions so every sidebar dot updates together.

let _currentPollInterval = POLL_INTERVAL_ACTIVE_MS;

function _computePollInterval(sessions) {
  const hasTransient = sessions.some(
    (s) => s.status === "pausing" || s.status === "resuming"
  );
  if (hasTransient || isPausingRequested) return POLL_INTERVAL_FAST_MS;
  const hasLive = sessions.some(
    (s) => s.status === "running" || s.status === "queued"
  );
  return hasLive ? POLL_INTERVAL_ACTIVE_MS : POLL_INTERVAL_IDLE_MS;
}

function startPolling(runId) {
  if (runId) currentRunId = runId;
  if (pollTimer) return; // already running
  pollErrors = 0;
  _pollTick();
  pollTimer = setInterval(_pollTick, _currentPollInterval);
}

function stopPolling() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  pollErrors = 0;
}

// Immediately restart poll at fast rate (called on user-initiated pause/resume)
function restartPollingFast() {
  stopPolling();
  _currentPollInterval = POLL_INTERVAL_FAST_MS;
  pollErrors = 0;
  _pollTick();
  pollTimer = setInterval(_pollTick, _currentPollInterval);
}

async function _pollTick() {
  try {
    const sessionsData = await apiGet("/api/runs");
    pollErrors = 0;

    allSessions = sessionsData.runs || [];
    renderSessionList(allSessions);

    if (currentRunId) {
      const run = allSessions.find((s) => s.run_id === currentRunId);
      if (run) renderRun(run);
    }

    // Recalculate interval and reschedule if it changed
    const newInterval = _computePollInterval(allSessions);
    if (newInterval !== _currentPollInterval) {
      _currentPollInterval = newInterval;
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = setInterval(_pollTick, _currentPollInterval);
      }
    }
  } catch (_err) {
    pollErrors += 1;
    if (pollErrors >= POLL_MAX_ERRORS) {
      setRunStatus("missing", "Backend not responding — check that `eurekaclaw ui` is running.");
    }
  }
}

async function refreshRun(runId) {
  // One-shot fetch for the full sessions list — updates sidebar and panel.
  try {
    const data = await apiGet("/api/runs");
    allSessions = data.runs || [];
    renderSessionList(allSessions);
    if (runId === currentRunId) {
      const run = allSessions.find((s) => s.run_id === runId);
      if (run) renderRun(run);
    }
  } catch (_err) {
    // Silently ignore — polling will surface persistent errors
  }
}

async function loadMostRecentRun() {
  try {
    const data = await apiGet("/api/runs");
    allSessions = data.runs || [];
    renderSessionList(allSessions);
    const latest = allSessions[0];
    if (latest) {
      currentRunId = latest.run_id;
      currentLogPage = 1;
      renderRun(latest);
    } else {
      renderRun(null);
    }
    // Start polling if any session is still live
    const hasLive = allSessions.some(
      (s) => s.status === "running" || s.status === "queued"
    );
    if (hasLive) startPolling(null);
  } catch (_err) {
    // Don't flash "missing" on startup — backend may just be starting up
    renderRun(null);
  }
}

inputModeEl.addEventListener("change", updateModeUI);
updateModeUI();

launchSessionBtn.addEventListener("click", async () => {
  const validationError = validateInputSpec();
  if (validationError) {
    canvasErrorEl.textContent = validationError;
    canvasErrorEl.hidden = false;
    setTimeout(() => { canvasErrorEl.hidden = true; }, 4000);
    return;
  }
  canvasErrorEl.hidden = true;

  launchSessionBtn.disabled = true;
  setRunStatus("running", "Creating session…");
  try {
    const run = await apiPost("/api/runs", normalizeInputSpec());
    // Keep allSessions in sync immediately (no waiting for next poll)
    allSessions = [run, ...allSessions.filter((s) => s.run_id !== run.run_id)];
    currentRunId = run.run_id;
    currentLogPage = 1;
    renderSessionList(allSessions);
    renderRun(run);
    showView("workspace");
    startPolling(run.run_id); // sets currentRunId + starts timer if not already running
  } catch (error) {
    setRunStatus("failed", `Could not start session: ${error.message}`);
  } finally {
    launchSessionBtn.disabled = false;
  }
});

loadExampleBtn.addEventListener("click", () => {
  inputModeEl.value = "detailed";
  inputDomainEl.value = "Machine learning theory";
  inputPromptEl.value =
    "Prove a generalization bound for sparse transformer attention under low-rank kernel assumptions.";
  updateModeUI();
});

skillSearchEl.addEventListener("input", () => {
  currentSkillPage = 1;
  renderSkillIntent();
});

skillSelectedEl.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;
  const skillName = target.getAttribute("data-remove-skill");
  if (skillName) toggleSkill(skillName);
});

skillListEl.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;
  // Delete button inside card
  const deleteBtn = target.closest("[data-delete-skill]");
  if (deleteBtn instanceof HTMLElement) {
    deleteSkill(deleteBtn.dataset.deleteSkill || "");
    return;
  }
  // Toggle selection
  const button = target.closest("[data-skill-name]");
  if (button instanceof HTMLElement) {
    toggleSkill(button.dataset.skillName || "");
  }
});

clawhubInstallBtn.addEventListener("click", () => {
  const slug = clawhubInputEl.value.trim();
  if (!slug) {
    clawhubInputEl.focus();
    showClawHubStatus("Enter a ClawHub skill slug, e.g. steipete/github", true);
    return;
  }
  installSkill(slug);
});

clawhubInputEl.addEventListener("keydown", (event) => {
  if (event.key === "Enter") clawhubInstallBtn.click();
});

installSeedsBtnEl.addEventListener("click", () => installSkill(""));

selectAllSkillsBtnEl.addEventListener("click", () => {
  selectedSkills = availableSkills.map((s) => s.name);
  renderSkillIntent();
});

skillPaginationEl.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }
  const action = target.getAttribute("data-skill-page");
  if (action === "prev" && currentSkillPage > 1) {
    currentSkillPage -= 1;
    renderSkillIntent();
  }
  if (action === "next") {
    currentSkillPage += 1;
    renderSkillIntent();
  }
});

logPaginationEl.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }
  const action = target.getAttribute("data-log-page");
  if (action === "prev" && currentLogPage > 1) {
    currentLogPage -= 1;
    if (currentRunId) refreshRun(currentRunId);
  }
  if (action === "next") {
    currentLogPage += 1;
    if (currentRunId) refreshRun(currentRunId);
  }
});

document.getElementById("new-session-btn").addEventListener("click", () => {
  // Clear the active selection but keep polling — other sessions may be live
  currentRunId = null;
  currentLogPage = 1;
  renderSessionList(allSessions);
  showView("workspace");
  showNewSessionPane();
  canvasErrorEl.hidden = true;
  setTimeout(() => inputPromptEl.focus(), 80);
});

sessionListEl.addEventListener("click", (event) => {
  // Rename button
  const renameBtn = event.target.closest(".session-rename-sidebar-btn");
  if (renameBtn) {
    event.stopPropagation();
    const runId = renameBtn.dataset.renameRunId;
    if (runId) startSidebarRename(runId);
    return;
  }

  // Restart button (for failed sessions)
  const restartBtn = event.target.closest(".session-restart-sidebar-btn");
  if (restartBtn) {
    event.stopPropagation();
    const runId = restartBtn.dataset.restartRunId;
    if (runId) restartRun(runId);
    return;
  }

  // Delete button
  const deleteBtn = event.target.closest(".session-delete-btn");
  if (deleteBtn) {
    event.stopPropagation();
    const runId = deleteBtn.dataset.deleteRunId;
    if (runId) deleteRun(runId);
    return;
  }

  const item = event.target.closest(".session-item");
  if (!item) return;
  const runId = item.dataset.runId;
  if (!runId || runId === currentRunId) return;

  // Just switch which session is displayed — don't stop/restart the global
  // poll timer. The poll already tracks ALL sessions simultaneously.
  currentRunId = runId;
  currentLogPage = 1;
  renderSessionList(allSessions);
  showView("workspace");

  // Show this session immediately from cached data, then refresh
  const cached = allSessions.find((s) => s.run_id === runId);
  if (cached) renderRun(cached);
  refreshRun(runId);

  // Ensure polling is active if any live sessions exist
  const hasLive = allSessions.some(
    (s) => s.status === "running" || s.status === "queued"
  );
  if (hasLive && !pollTimer) startPolling(null);
});

pauseSessionBtn.addEventListener("click", async () => {
  if (!currentRunId) return;
  pauseSessionBtn.disabled = true;
  // Optimistic UI: immediately show the pausing state
  isPausingRequested = true;
  proofCtrlRunningEl.hidden = true;
  proofCtrlPausingEl.hidden = false;
  startElapsedTimer(new Date());
  // Accelerate polling so the transition to "paused" is detected quickly
  restartPollingFast();
  try {
    await apiPost(`/api/runs/${currentRunId}/pause`, {});
  } catch (error) {
    // Rollback optimistic change if the request failed
    isPausingRequested = false;
    stopElapsedTimer();
    proofCtrlPausingEl.hidden = true;
    proofCtrlRunningEl.hidden = false;
    setRunStatus("running", `Pause failed: ${error.message}`);
  } finally {
    pauseSessionBtn.disabled = false;
  }
});

resumeSessionBtn.addEventListener("click", async () => {
  if (!currentRunId) return;
  resumeSessionBtn.disabled = true;
  const feedback = theoryFeedbackInputEl ? theoryFeedbackInputEl.value.trim() : "";
  if (theoryFeedbackInputEl) theoryFeedbackInputEl.value = "";
  if (theoryFeedbackBodyEl) theoryFeedbackBodyEl.hidden = true;
  if (theoryFeedbackToggleEl) theoryFeedbackToggleEl.setAttribute("aria-expanded", "false");
  // Optimistic UI: immediately show resuming state
  proofCtrlPausedEl.hidden = true;
  proofCtrlResumingEl.hidden = false;
  restartPollingFast();
  try {
    await apiPost(`/api/runs/${currentRunId}/resume`, { feedback });
    // Ensure poll is running now that a session is live
    if (!pollTimer) startPolling(currentRunId);
  } catch (error) {
    // Rollback
    proofCtrlResumingEl.hidden = true;
    proofCtrlPausedEl.hidden = false;
    setRunStatus("paused", `Resume failed: ${error.message}`);
    resumeSessionBtn.disabled = false;
  }
});

copyResumeCmdBtn.addEventListener("click", () => {
  if (!currentRunId) return;
  const run = allSessions.find((s) => s.run_id === currentRunId);
  if (!run || !run.session_id) return;
  const cmd = `eurekaclaw resume ${run.session_id}`;
  navigator.clipboard.writeText(cmd).then(() => {
    const lbl = copyResumeCmdLabelEl;
    const prev = lbl.textContent;
    lbl.textContent = "Copied!";
    setTimeout(() => { lbl.textContent = prev; }, 2000);
  }).catch(() => {
    // Fallback: select the session ID element text
    const range = document.createRange();
    range.selectNode(proofCtrlSessionIdEl);
    window.getSelection()?.removeAllRanges();
    window.getSelection()?.addRange(range);
  });
});

// ── Session topbar rename ─────────────────────────────────────────────────

sessionTopbarRenameBtnEl.addEventListener("click", () => {
  if (!currentRunId) return;
  const run = allSessions.find((s) => s.run_id === currentRunId);
  sessionTopbarNameInputEl.value = run?.name || truncateSessionName(run) || "";
  sessionTopbarNameEl.hidden = true;
  sessionTopbarRenameBtnEl.hidden = true;
  sessionTopbarNameInputEl.hidden = false;
  sessionTopbarNameInputEl.focus();
  sessionTopbarNameInputEl.select();
});

async function commitTopbarRename() {
  const newName = sessionTopbarNameInputEl.value.trim();
  sessionTopbarNameEl.hidden = false;
  sessionTopbarRenameBtnEl.hidden = false;
  sessionTopbarNameInputEl.hidden = true;
  if (!newName || !currentRunId) return;
  const run = allSessions.find((s) => s.run_id === currentRunId);
  const oldName = run?.name || "";
  if (newName === oldName) return;
  await renameRun(currentRunId, newName);
  sessionTopbarNameEl.textContent = newName;
}

sessionTopbarNameInputEl.addEventListener("blur", commitTopbarRename);
sessionTopbarNameInputEl.addEventListener("keydown", (e) => {
  if (e.key === "Enter") sessionTopbarNameInputEl.blur();
  if (e.key === "Escape") {
    const run = allSessions.find((s) => s.run_id === currentRunId);
    sessionTopbarNameEl.textContent = run?.name || truncateSessionName(run) || "";
    sessionTopbarNameEl.hidden = false;
    sessionTopbarRenameBtnEl.hidden = false;
    sessionTopbarNameInputEl.hidden = true;
  }
});

// ── Restart session from failed-session-note ──────────────────────────────

restartSessionBtn.addEventListener("click", () => {
  if (!currentRunId) return;
  restartRun(currentRunId);
});

closeAgentDrawerBtn.addEventListener("click", closeAgentDrawer);
agentDrawerBackdropEl.addEventListener("click", closeAgentDrawer);
window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeAgentDrawer();
});

// Workspace tab bar
document.querySelector(".ws-tab-bar")?.addEventListener("click", (event) => {
  const btn = event.target.closest(".ws-tab");
  if (btn instanceof HTMLElement && btn.dataset.wsTab) {
    switchWsTab(btn.dataset.wsTab);
  }
});

// Agent track card clicks
agentTrackEl?.addEventListener("click", (event) => {
  const card = event.target.closest("[data-agent-role]");
  if (card instanceof HTMLElement && card.dataset.agentRole) {
    openAgentDrawer(card.dataset.agentRole);
  }
});

// Theory feedback toggle
theoryFeedbackToggleEl?.addEventListener("click", () => {
  const isOpen = !theoryFeedbackBodyEl.hidden;
  theoryFeedbackBodyEl.hidden = isOpen;
  theoryFeedbackToggleEl.setAttribute("aria-expanded", String(!isOpen));
  theoryFeedbackToggleEl.querySelector(".theory-feedback-toggle-chevron")?.classList.toggle("is-open", !isOpen);
});

// Lemma chip click → append to textarea
theoryFeedbackLemmaListEl?.addEventListener("click", (event) => {
  const chip = event.target.closest("[data-lemma]");
  if (chip instanceof HTMLElement && theoryFeedbackInputEl) {
    const lemma = chip.dataset.lemma || "";
    const existing = theoryFeedbackInputEl.value.trim();
    theoryFeedbackInputEl.value = existing ? `${existing}\nLemma "${lemma}": ` : `Lemma "${lemma}": `;
    theoryFeedbackInputEl.focus();
  }
});

configFormEl.addEventListener("input", () => {
  updateConfigVisibility();
  renderAuthGuidance();
});

authGuidanceToggleEl.addEventListener("click", () => {
  setAuthGuidanceOpen(!authGuidanceShellEl.classList.contains("is-open"));
});

authGuidanceToggleEl.addEventListener("mouseenter", () => {
  if (window.matchMedia("(hover: hover)").matches) {
    setAuthGuidanceOpen(true);
  }
});

authGuidanceShellEl.addEventListener("mouseleave", () => {
  if (window.matchMedia("(hover: hover)").matches) {
    setAuthGuidanceOpen(false);
  }
});

configFormEl.addEventListener("submit", async (event) => {
  event.preventDefault();
  const payload = configPayloadFromForm();
  configSaveStatusEl.textContent = "Saving configuration...";
  try {
    await apiPost("/api/config", payload);
    configSaveStatusEl.textContent = "Configuration saved to the live backend and .env.";
    await loadCapabilities();
  } catch (error) {
    configSaveStatusEl.textContent = `Could not save config: ${error.message}`;
  }
});

async function testConnection(payload, saveAfter = false) {
  const originalText = configSaveStatusEl.textContent;
  configSaveStatusEl.textContent = saveAfter
    ? "Testing connection before saving..."
    : "Testing connection...";
  try {
    const result = await apiPost("/api/auth/test", payload);
    if (!result.ok) {
      configSaveStatusEl.textContent = `Connection failed: ${result.message}`;
      return;
    }

    if (saveAfter) {
      await apiPost("/api/config", payload);
      await loadConfig();
      await loadCapabilities();
      configSaveStatusEl.textContent = `Connection verified and config saved. Reply preview: ${result.reply_preview || "OK"}`;
      return;
    }

    configSaveStatusEl.textContent = `Connection verified. Reply preview: ${result.reply_preview || "OK"}`;
  } catch (error) {
    configSaveStatusEl.textContent = `Could not test connection: ${error.message}`;
    return;
  }

  if (!saveAfter) {
    setTimeout(() => {
      if (configSaveStatusEl.textContent.startsWith("Connection verified.")) {
        configSaveStatusEl.textContent = originalText;
      }
    }, 5000);
  }
}

testConnectionBtn.addEventListener("click", async () => {
  await testConnection(configPayloadFromForm(), false);
});

saveAndTestBtn.addEventListener("click", async () => {
  await testConnection(configPayloadFromForm(), true);
});

prevStepBtn.addEventListener("click", () => {
  currentWizardStep = Math.max(0, currentWizardStep - 1);
  renderWizardStep(currentWizardStep);
});

nextStepBtn.addEventListener("click", () => {
  if (currentWizardStep < wizardSteps.length - 1) {
    currentWizardStep += 1;
    renderWizardStep(currentWizardStep);
    return;
  }
  flashTransitionTo("workspace");
});

document.getElementById("tutorial-btn").addEventListener("click", () => {
  localStorage.removeItem(TUTORIAL_SKIP_KEY);
  currentWizardStep = 0;
  renderWizardStep(0);
  flashTransitionTo("onboarding");
});

skipTutorialBtn.addEventListener("click", () => {
  localStorage.setItem("eurekaclaw_tutorial_skipped", "1");
  flashTransitionTo("workspace");
});

renderWizardStep(currentWizardStep);
// Skip tutorial automatically if user has opted out before
if (localStorage.getItem(TUTORIAL_SKIP_KEY) === "1") {
  showView("workspace");
} else {
  showView("onboarding");
}
loadCapabilities();
loadConfig();
loadMostRecentRun();
loadSkills();
updateConfigVisibility();
renderAuthGuidance();
setAuthGuidanceOpen(false);
