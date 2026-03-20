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
const pipelineListEl = document.getElementById("pipeline-list");
const agentGridEl = document.getElementById("agent-grid");
const artifactListEl = document.getElementById("artifact-list");
const logStreamEl = document.getElementById("log-stream");
const logPaginationEl = document.getElementById("log-pagination");
const paperPreviewEl = document.getElementById("paper-preview");
const outputStatusPillEl = document.getElementById("output-status-pill");
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
const sessionListEl = document.getElementById("session-list");
const artifactDrawerEl = document.getElementById("artifact-drawer");
const artifactDrawerBackdropEl = document.getElementById("artifact-drawer-backdrop");
const artifactDrawerTitleEl = document.getElementById("artifact-drawer-title");
const artifactDrawerBodyEl = document.getElementById("artifact-drawer-body");
const closeArtifactDrawerBtn = document.getElementById("close-artifact-drawer-btn");

const wizardStage = document.getElementById("wizard-stage");
const wizardDotsRow = document.getElementById("wizard-dots-row");
const wizardProgressBar = document.getElementById("wizard-progress-bar");
const wizardStepLabel = document.getElementById("wizard-step-label");
const prevStepBtn = document.getElementById("prev-step-btn");
const nextStepBtn = document.getElementById("next-step-btn");

let currentWizardStep = 0;
let currentRunId = null;
let pollTimer = null;
let pollErrors = 0;
const POLL_INTERVAL_MS = 2000;
const POLL_MAX_ERRORS = 4;   // show "connection lost" only after 4 consecutive failures
let latestArtifacts = null;
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
    subtitle: "From a question to a publishable paper — autonomously",
    items: [
      { label: "Crawls arXiv & Semantic Scholar", note: "Finds, summarizes, and cross-references relevant papers" },
      { label: "Generates theorems + multi-stage proofs", note: "7-stage bottom-up proof pipeline with lemma verification" },
      { label: "Runs numerical experiments", note: "Validates theoretical bounds; flags low-confidence lemmas" },
      { label: "Writes camera-ready LaTeX papers", note: "Full bibliography, theorem environments, and PDF compilation" },
      { label: "Fully local-first, private by default", note: "Your data never leaves your machine — MIT licensed" }
    ],
    tip: "Setup takes ~5 minutes for the core system. Optional tools (Lean4, LaTeX, Docker) can be added later — EurekaClaw runs in a useful degraded mode without them."
  },
  {
    icon: "📦",
    title: "Install EurekaClaw",
    subtitle: "Python 3.11 or newer required",
    items: [
      { label: "Clone the repository", code: "git clone https://github.com/EurekaClaw/EurekaClaw_dev_zero" },
      { label: "Enter the project directory", code: "cd EurekaClaw_dev_zero" },
      { label: "Install in editable mode", code: "pip install -e \".\"", note: "Installs the eurekaclaw CLI immediately" },
      { label: "Copy the environment file", code: "cp .env.example .env", note: "This is where all your keys and settings live" },
      { label: "Optional extras (OpenRouter / OAuth)", code: "pip install -e \".[openai,oauth]\"" }
    ],
    tip: "The -e flag installs in editable mode so changes to the source take effect immediately without reinstalling."
  },
  {
    icon: "🔑",
    title: "Connect Your Language Model",
    subtitle: "Choose how EurekaClaw reaches an AI model",
    items: [
      { label: "Option A — Anthropic API key (fastest)", code: "ANTHROPIC_API_KEY=sk-ant-...   # add to .env", note: "Recommended for most users" },
      { label: "Option B — Claude Pro/Max via OAuth (no API key)", code: "pip install \"eurekaclaw[oauth]\"\nANTHROPIC_AUTH_MODE=oauth   # add to .env", note: "ccproxy auto-reads ~/.claude/.credentials.json" },
      { label: "Option C — OpenRouter", code: "LLM_BACKEND=openrouter\nOPENAI_COMPAT_API_KEY=sk-or-...   # add to .env" },
      { label: "Option D — Local model (vLLM / Ollama)", code: "LLM_BACKEND=local   # defaults to http://localhost:8000/v1" }
    ],
    tip: "You can also change backend and API keys in the Settings tab — they write back to .env automatically without manual file editing."
  },
  {
    icon: "⚙️",
    title: "Configure Runtime Settings",
    subtitle: "Tune key parameters in .env or the Settings tab",
    items: [
      { label: "Primary model", code: "EUREKACLAW_MODEL=claude-sonnet-4-6", note: "Fast model defaults to claude-haiku-4-5-20251001" },
      { label: "Gate mode (human review control)", code: "GATE_MODE=auto", note: "none = fully auto · auto = escalates on low-confidence lemmas · human = pauses at every stage" },
      { label: "Output format", code: "OUTPUT_FORMAT=latex", note: "latex (default, generates PDF) or markdown" },
      { label: "Experiment validation", code: "EXPERIMENT_MODE=auto", note: "auto = run when needed · true = always · false = skip" },
      { label: "Max proof loop iterations", code: "THEORY_MAX_ITERATIONS=10", note: "Increase if proofs are being abandoned prematurely" }
    ],
    tip: "The Settings tab has live sliders for all 7 token-limit knobs (agent, prover, planner, decomposer, formalizer, verifier, compress) — no .env editing required."
  },
  {
    icon: "🔧",
    title: "Optional Tools",
    subtitle: "Each unlocks a meaningful capability — none are blockers",
    items: [
      { label: "Lean4 — formal proof verification", code: "curl https://elan.lean-lang.org/elan-init.sh | sh", note: "Lets EurekaClaw formally verify proofs, not just LLM-check them" },
      { label: "TeX Live / MacTeX — PDF compilation", code: "brew install --cask mactex-no-gui   # macOS", note: "Required for paper.pdf output; paper.tex is always generated" },
      { label: "Docker — sandboxed code execution", note: "Install from docker.com — enables safe experiment runs" },
      { label: "Semantic Scholar API key", code: "S2_API_KEY=...   # add to .env", note: "Unlocks citation counts and venue metadata for papers" },
      { label: "Wolfram Alpha API key", code: "WOLFRAM_APP_ID=...   # add to .env", note: "Enables symbolic computation and formula verification" }
    ],
    tip: "Missing optional tools appear as warnings (not errors) in the System Health panel under Settings. The system auto-detects what is available on startup."
  },
  {
    icon: "🧠",
    title: "Install Built-in Skills",
    subtitle: "One command adds proof strategies to all agents",
    items: [
      { label: "Install seed skills (run once)", code: "eurekaclaw install-skills", note: "Installs to ~/.eurekaclaw/skills/ and persists across sessions" },
      { label: "Browse all available skills", code: "eurekaclaw skills" },
      { label: "Theory skills", note: "Induction, contradiction, compactness, concentration inequalities, UCB regret analysis" },
      { label: "Survey & writing skills", note: "Literature decomposition, gap analysis, paper structure, proof readability rules" },
      { label: "Add your own custom skills", code: "# Drop any .md file into ~/.eurekaclaw/skills/", note: "EurekaClaw also distills new skills automatically after each successful run" }
    ],
    tip: "After each session, the continual learning loop extracts what worked and distills it into new skills — your system gets better over time automatically."
  },
  {
    icon: "🚀",
    title: "Launch Your First Session",
    subtitle: "Three research modes — pick the one that fits",
    items: [
      { label: "Browser UI (this tab)", note: "Click Launch session on the Research tab — live progress, log stream, and results viewer" },
      { label: "Prove a specific conjecture", code: "eurekaclaw prove \"O(n log n) complexity via sparse attention\" --domain \"ML theory\"" },
      { label: "Explore a broad research area", code: "eurekaclaw explore \"multi-armed bandit theory\"" },
      { label: "Start from existing papers", code: "eurekaclaw from-papers 1706.03762 2005.14165 --domain \"attention mechanisms\"" },
      { label: "Results are saved to", code: "./results/<session_id>/paper.tex  ·  paper.pdf  ·  references.bib", note: "Also: theory_state.json, research_brief.json, experiment_result.json" }
    ],
    tip: "Go to Settings → Test connection first to confirm your model is reachable. Use --gate human on your first run to review each stage before it continues."
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
    <div class="wizard-items">
      ${step.items.map((item, i) => `
        <div class="wizard-item">
          <span class="wizard-item-num">${i + 1}</span>
          <div class="wizard-item-body">
            <strong>${item.label}</strong>
            ${item.code ? `<code class="wizard-item-code">${escapeHtml(item.code)}</code>` : ""}
            ${item.note ? `<span class="wizard-item-note">${item.note}</span>` : ""}
          </div>
        </div>
      `).join("")}
    </div>
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
    const prompt = s.input_spec?.query || s.input_spec?.domain || "Untitled session";
    const domain = s.input_spec?.domain || "";
    const status = s.status || "queued";
    const time = formatRelativeTime(s.created_at);
    const isActive = s.run_id === currentRunId;
    return `<div class="session-item${isActive ? " is-active" : ""}" data-run-id="${escapeHtml(s.run_id)}">
      <div class="session-item-prompt">${escapeHtml(prompt)}</div>
      <div class="session-item-meta">
        <span class="session-status-dot ${status}"></span>
        <span>${time}</span>
        ${domain ? `<span>·</span><span>${escapeHtml(domain)}</span>` : ""}
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

function renderPipeline(tasks) {
  if (!tasks || !tasks.length) {
    pipelineListEl.innerHTML = `
      <div class="pipeline-step">
        <span class="step-index">--</span>
        <div>
          <strong>No active run</strong>
          <p>Launch a session to populate the live pipeline.</p>
        </div>
        <span class="status-pill status-idle">Idle</span>
      </div>
    `;
    return;
  }

  pipelineListEl.innerHTML = tasks
    .map((task, index) => {
      const activeClass = task.status === "in_progress" ? " is-active" : "";
      const completeClass = task.status === "completed" ? " is-complete" : "";
      return `
        <div class="pipeline-step${activeClass}${completeClass}">
          <span class="step-index">${String(index + 1).padStart(2, "0")}</span>
          <div>
            <strong>${escapeHtml(titleCase(task.name))}</strong>
            <p>${escapeHtml(task.description || "No description")}</p>
          </div>
          <span class="status-pill ${statusClass(task.status)}">${escapeHtml(titleCase(task.status))}</span>
        </div>
      `;
    })
    .join("");
}

function renderAgents(tasks) {
  const taskMap = new Map((tasks || []).map((task) => [task.agent_role, task]));
  const agents = [
    ["survey", "SurveyAgent"],
    ["ideation", "IdeationAgent"],
    ["theory", "TheoryAgent"],
    ["experiment", "ExperimentAgent"],
    ["writer", "WriterAgent"]
  ];

  agentGridEl.innerHTML = agents
    .map(([role, label]) => {
      const task = taskMap.get(role);
      const activeClass = task && task.status === "in_progress" ? " active" : "";
      const summary = task
        ? `${titleCase(task.status)}${task.error_message ? `: ${task.error_message}` : ""}`
        : "Waiting for pipeline data.";
      return `
        <div class="agent-card${activeClass}">
          <h4>${label}</h4>
          <p>${escapeHtml(summary)}</p>
        </div>
      `;
    })
    .join("");
}

function renderArtifacts(artifacts) {
  latestArtifacts = artifacts || null;
  const entries = [
    ["research_brief", "Research brief"],
    ["bibliography", "Bibliography"],
    ["theory_state", "Theory state"],
    ["experiment_result", "Experiment result"],
    ["resource_analysis", "Resource analysis"]
  ].filter(([key]) => artifacts && artifacts[key]);

  const sidebarArtifactsEl = document.getElementById("sidebar-artifacts");
  if (sidebarArtifactsEl) sidebarArtifactsEl.textContent = String(entries.length);

  if (!entries.length) {
    artifactListEl.innerHTML = `
      <div class="artifact-item">
        <div>
          <strong>No artifacts yet</strong>
          <p>Artifacts will appear here as the run progresses.</p>
        </div>
        <span class="mono-label">waiting</span>
      </div>
    `;
    return;
  }

  artifactListEl.innerHTML = entries
    .map(([key, label]) => {
      const value = artifacts[key];
      const summary = Array.isArray(value?.papers)
        ? `${value.papers.length} papers`
        : Array.isArray(value?.open_goals)
          ? `${value.open_goals.length} open goals`
          : Array.isArray(value?.bounds)
            ? `${value.bounds.length} bounds`
            : `${Object.keys(value || {}).length} fields`;

      return `
        <div class="artifact-item" data-artifact-key="${escapeHtml(key)}">
          <div>
            <strong>${escapeHtml(label)}</strong>
            <p>${escapeHtml(summary)}</p>
          </div>
          <span class="mono-label">live</span>
        </div>
      `;
    })
    .join("");

  artifactListEl.querySelectorAll("[data-artifact-key]").forEach((item) => {
    item.addEventListener("click", () => openArtifactDrawer(item.dataset.artifactKey));
  });
}

function renderLogs(run, tasks) {
  const items = [];
  if (run?.created_at) {
    items.push({ time: run.created_at, message: "Session created from the workspace.", tone: "" });
  }
  (tasks || []).forEach((task) => {
    if (task.started_at) {
      items.push({
        time: task.started_at,
        message: `${titleCase(task.name)} started.`,
        tone: ""
      });
    }
    if (task.completed_at) {
      items.push({
        time: task.completed_at,
        message: `${titleCase(task.name)} completed.`,
        tone: ""
      });
    }
    if (task.error_message) {
      items.push({
        time: task.completed_at || task.started_at || run?.created_at,
        message: `${titleCase(task.name)} failed: ${task.error_message}`,
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

  outputStatusPillEl.className = `status-pill ${statusClass(run?.status || "idle")}`;
  outputStatusPillEl.textContent = titleCase(run?.status || "waiting");

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
  // Update the status dot for this session in the sidebar list
  const item = sessionListEl.querySelector(`[data-run-id="${run.run_id}"]`);
  if (!item) return;
  const dot = item.querySelector(".session-status-dot");
  if (dot) dot.className = `session-status-dot ${run.status}`;
  sessionListEl.querySelectorAll(".session-item").forEach((el) => {
    el.classList.toggle("is-active", el.dataset.runId === currentRunId);
  });
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

function configPayloadFromForm() {
  return Object.fromEntries(new FormData(configFormEl).entries());
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

function renderSkillIntent() {
  const query = skillSearchEl.value.trim().toLowerCase();
  const filtered = availableSkills
    .filter((skill) => !query || skillSearchText(skill).includes(query))
    .sort((a, b) => {
      const aSelected = selectedSkills.includes(a.name) ? 1 : 0;
      const bSelected = selectedSkills.includes(b.name) ? 1 : 0;
      if (aSelected !== bSelected) {
        return bSelected - aSelected;
      }
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
          <button type="button" data-remove-skill="${escapeHtml(name)}" aria-label="Remove ${escapeHtml(name)}">x</button>
        </span>
      `).join("")
    : '<div class="intent-empty">No skills selected yet.</div>';

  if (!filtered.length) {
    skillListEl.innerHTML = '<div class="intent-empty">No skills match this search.</div>';
    skillMetaEl.textContent = `${selectedSkills.length} selected`;
    skillPaginationEl.innerHTML = "";
    return;
  }

  skillListEl.innerHTML = visibleSkills.map((skill) => `
    <button type="button" class="intent-skill ${selectedSkills.includes(skill.name) ? "is-selected" : ""}" data-skill-name="${escapeHtml(skill.name)}">
      <div class="intent-skill-head">
        <span class="intent-skill-name">${escapeHtml(skill.name)}</span>
        <span class="intent-skill-source">${escapeHtml(skill.source || "manual")}</span>
      </div>
      <p class="intent-skill-desc">${escapeHtml(skill.description || "No description available.")}</p>
      <div class="intent-tag-row">
        ${(skill.tags || []).slice(0, 4).map((tag) => `<span class="intent-tag">${escapeHtml(tag)}</span>`).join("")}
      </div>
    </button>
  `).join("");

  const matchingText = query ? `${filtered.length} matching` : `${availableSkills.length} available`;
  skillMetaEl.textContent = `${selectedSkills.length} selected · ${matchingText} · page ${currentSkillPage} of ${totalPages}`;
  skillPaginationEl.innerHTML = totalPages > 1 ? `
    <button type="button" class="ghost-btn" data-skill-page="prev" ${currentSkillPage === 1 ? "disabled" : ""}>Previous</button>
    <span class="skill-pagination-meta">Page ${currentSkillPage} / ${totalPages}</span>
    <button type="button" class="ghost-btn" data-skill-page="next" ${currentSkillPage === totalPages ? "disabled" : ""}>Next</button>
  ` : "";
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
        field.value = value ?? "";
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
  const tasks = run?.pipeline || [];
  renderPipeline(tasks);
  renderAgents(tasks);
  renderArtifacts(run?.artifacts);
  renderLogs(run, tasks);
  renderOutput(run);
  renderTokenUsage(tasks);
  updateSidebar(run);
  setRunStatus(run ? run.status : "idle", liveStatusDetail(run));
}

function renderArtifactSummary(key, artifact) {
  if (!artifact) {
    return "<p>No data available.</p>";
  }

  if (key === "research_brief") {
    return `
      <section class="artifact-section">
        <h4>Overview</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Domain</strong><span>${escapeHtml(artifact.domain || "")}</span></div>
          <div class="artifact-kv-row"><strong>Query</strong><span>${escapeHtml(artifact.query || "")}</span></div>
          <div class="artifact-kv-row"><strong>Input mode</strong><span>${escapeHtml(artifact.input_mode || "")}</span></div>
          <div class="artifact-kv-row"><strong>Conjecture</strong><span>${escapeHtml(artifact.conjecture || "—")}</span></div>
        </div>
      </section>
      <section class="artifact-section">
        <h4>Open Problems</h4>
        <div class="artifact-chip-list">
          ${(artifact.open_problems || []).map((item) => `<span>${escapeHtml(item)}</span>`).join("") || "<span>None</span>"}
        </div>
      </section>
    `;
  }

  if (key === "bibliography") {
    const papers = artifact.papers || [];
    return `
      <section class="artifact-section">
        <h4>Paper Set</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Total papers</strong><span>${escapeHtml(String(papers.length))}</span></div>
          <div class="artifact-kv-row"><strong>Citation graph nodes</strong><span>${escapeHtml(String(Object.keys(artifact.citation_graph || {}).length))}</span></div>
        </div>
      </section>
      <section class="artifact-section">
        <h4>Top Papers</h4>
        <div class="artifact-kv">
          ${papers.slice(0, 8).map((paper) => `
            <div class="artifact-kv-row">
              <strong>${escapeHtml((paper.year || "—").toString())}</strong>
              <span>${escapeHtml(paper.title || "")}</span>
            </div>
          `).join("") || '<p>No papers available.</p>'}
        </div>
      </section>
    `;
  }

  if (key === "theory_state") {
    return `
      <section class="artifact-section">
        <h4>Theory Snapshot</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Status</strong><span>${escapeHtml(artifact.status || "")}</span></div>
          <div class="artifact-kv-row"><strong>Iteration</strong><span>${escapeHtml(String(artifact.iteration ?? 0))}</span></div>
          <div class="artifact-kv-row"><strong>Formal statement</strong><span>${escapeHtml(artifact.formal_statement || "—")}</span></div>
        </div>
      </section>
      <section class="artifact-section">
        <h4>Proof Progress</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Open goals</strong><span>${escapeHtml(String((artifact.open_goals || []).length))}</span></div>
          <div class="artifact-kv-row"><strong>Proven lemmas</strong><span>${escapeHtml(String(Object.keys(artifact.proven_lemmas || {}).length))}</span></div>
          <div class="artifact-kv-row"><strong>Counterexamples</strong><span>${escapeHtml(String((artifact.counterexamples || []).length))}</span></div>
        </div>
      </section>
    `;
  }

  if (key === "experiment_result") {
    return `
      <section class="artifact-section">
        <h4>Experiment Result</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Description</strong><span>${escapeHtml(artifact.description || "—")}</span></div>
          <div class="artifact-kv-row"><strong>Alignment</strong><span>${escapeHtml(String(artifact.alignment_score ?? 0))}</span></div>
          <div class="artifact-kv-row"><strong>Succeeded</strong><span>${escapeHtml(String(Boolean(artifact.succeeded)))}</span></div>
        </div>
      </section>
      <section class="artifact-section">
        <h4>Bounds</h4>
        <div class="artifact-kv">
          ${(artifact.bounds || []).map((bound) => `
            <div class="artifact-kv-row">
              <strong>${escapeHtml(bound.name || "bound")}</strong>
              <span>Theoretical: ${escapeHtml(String(bound.theoretical ?? "—"))} | Empirical: ${escapeHtml(String(bound.empirical ?? "—"))}</span>
            </div>
          `).join("") || '<p>No bounds available.</p>'}
        </div>
      </section>
    `;
  }

  if (key === "resource_analysis") {
    return `
      <section class="artifact-section">
        <h4>Resource Analysis</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Atomic components</strong><span>${escapeHtml(String((artifact.atomic_components || []).length))}</span></div>
          <div class="artifact-kv-row"><strong>Math-to-code map</strong><span>${escapeHtml(String(Object.keys(artifact.math_to_code || {}).length))}</span></div>
          <div class="artifact-kv-row"><strong>Code-to-math map</strong><span>${escapeHtml(String(Object.keys(artifact.code_to_math || {}).length))}</span></div>
        </div>
      </section>
    `;
  }

  return "<p>No formatter available for this artifact.</p>";
}

function openArtifactDrawer(key) {
  if (!latestArtifacts || !latestArtifacts[key]) {
    return;
  }

  const artifact = latestArtifacts[key];
  artifactDrawerTitleEl.textContent = titleCase(key);
  artifactDrawerBodyEl.innerHTML = `
    ${renderArtifactSummary(key, artifact)}
    <section class="artifact-section">
      <h4>Raw JSON</h4>
      <pre class="artifact-json">${escapeHtml(JSON.stringify(artifact, null, 2))}</pre>
    </section>
  `;
  artifactDrawerBackdropEl.hidden = false;
  artifactDrawerEl.classList.add("is-open");
  artifactDrawerEl.setAttribute("aria-hidden", "false");
}

function closeArtifactDrawer() {
  artifactDrawerEl.classList.remove("is-open");
  artifactDrawerEl.setAttribute("aria-hidden", "true");
  artifactDrawerBackdropEl.hidden = true;
}

// ── Polling engine ──────────────────────────────────────────────────────────

function startPolling(runId) {
  stopPolling();
  currentRunId = runId;
  pollErrors = 0;
  // First tick immediately, then on interval
  _pollTick();
  pollTimer = setInterval(_pollTick, POLL_INTERVAL_MS);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
  pollErrors = 0;
}

async function _pollTick() {
  if (!currentRunId) return;
  try {
    // Fetch both the active run and the full sessions list in parallel
    const [run, sessionsData] = await Promise.all([
      apiGet(`/api/runs/${currentRunId}`),
      apiGet("/api/runs"),
    ]);

    pollErrors = 0;

    // Update session list (sidebar dots reflect live status)
    allSessions = sessionsData.runs || [];
    renderSessionList(allSessions);

    // Update main panel only if this is still the displayed run
    if (run.run_id === currentRunId) {
      renderRun(run);
    }

    // Stop polling when the run reaches a terminal state
    if (run.status === "completed" || run.status === "failed") {
      stopPolling();
    }
  } catch (_err) {
    pollErrors += 1;
    if (pollErrors >= POLL_MAX_ERRORS) {
      setRunStatus("missing", "Backend not responding — check that `eurekaclaw ui` is running.");
    }
    // Keep polling — transient errors auto-recover
  }
}

async function refreshRun(runId) {
  // One-shot fetch without touching the poll timer
  try {
    const run = await apiGet(`/api/runs/${runId}`);
    if (run.run_id === currentRunId) {
      renderRun(run);
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
      // Resume polling if the run is still live
      if (latest.status === "running" || latest.status === "queued") {
        startPolling(latest.run_id);
      }
    } else {
      renderRun(null);
    }
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
    // Show inline validation message without marking any run as "failed"
    runMetaEl.textContent = validationError;
    runMetaEl.style.color = "var(--warn)";
    setTimeout(() => { runMetaEl.style.color = ""; }, 4000);
    return;
  }

  launchSessionBtn.disabled = true;
  runMetaEl.style.color = "";
  setRunStatus("running", "Creating session...");
  try {
    const run = await apiPost("/api/runs", normalizeInputSpec());
    // Keep allSessions in sync immediately (no waiting for next poll)
    allSessions = [run, ...allSessions.filter((s) => s.run_id !== run.run_id)];
    currentRunId = run.run_id;
    currentLogPage = 1;
    renderSessionList(allSessions);
    renderRun(run);
    showView("workspace");
    startPolling(run.run_id);
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
  if (!(target instanceof HTMLElement)) {
    return;
  }
  const skillName = target.getAttribute("data-remove-skill");
  if (skillName) {
    toggleSkill(skillName);
  }
});

skillListEl.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }
  const button = target.closest("[data-skill-name]");
  if (!(button instanceof HTMLElement)) {
    return;
  }
  toggleSkill(button.dataset.skillName || "");
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
  stopPolling();
  currentRunId = null;
  currentLogPage = 1;
  renderRun(null);
  renderSessionList(allSessions);
  showView("workspace");
  inputPromptEl.focus();
});

sessionListEl.addEventListener("click", (event) => {
  const item = event.target.closest(".session-item");
  if (!item) return;
  const runId = item.dataset.runId;
  if (!runId || runId === currentRunId) return;

  stopPolling();
  currentRunId = runId;
  currentLogPage = 1;
  renderSessionList(allSessions);
  showView("workspace");
  refreshRun(runId);

  // Resume live polling only if the session is still active
  const session = allSessions.find((s) => s.run_id === runId);
  if (session && (session.status === "running" || session.status === "queued")) {
    startPolling(runId);
  }
});

closeArtifactDrawerBtn.addEventListener("click", closeArtifactDrawer);
artifactDrawerBackdropEl.addEventListener("click", closeArtifactDrawer);
window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    closeArtifactDrawer();
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
  currentWizardStep = 0;
  renderWizardStep(0);
  flashTransitionTo("onboarding");
});

renderWizardStep(currentWizardStep);
showView("onboarding");
loadCapabilities();
loadConfig();
loadMostRecentRun();
loadSkills();
updateConfigVisibility();
renderAuthGuidance();
setAuthGuidanceOpen(false);
