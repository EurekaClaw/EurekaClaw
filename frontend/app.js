const views = document.querySelectorAll(".view");
const navItems = document.querySelectorAll("[data-view-target]");

const inputModeEl = document.getElementById("input-mode");
const inputDomainEl = document.getElementById("input-domain");
const inputPromptEl = document.getElementById("input-prompt");
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
const sidebarModeEl = document.getElementById("sidebar-mode");
const sidebarStageEl = document.getElementById("sidebar-stage");
const sidebarArtifactsEl = document.getElementById("sidebar-artifacts");
const artifactDrawerEl = document.getElementById("artifact-drawer");
const artifactDrawerBackdropEl = document.getElementById("artifact-drawer-backdrop");
const artifactDrawerTitleEl = document.getElementById("artifact-drawer-title");
const artifactDrawerBodyEl = document.getElementById("artifact-drawer-body");
const closeArtifactDrawerBtn = document.getElementById("close-artifact-drawer-btn");

const wizardStage = document.getElementById("wizard-stage");
const wizardContext = document.getElementById("wizard-context");
const wizardProgressBar = document.getElementById("wizard-progress-bar");
const wizardStepLabel = document.getElementById("wizard-step-label");
const prevStepBtn = document.getElementById("prev-step-btn");
const nextStepBtn = document.getElementById("next-step-btn");

let currentWizardStep = 0;
let currentRunId = null;
let pollTimer = null;
let latestArtifacts = null;
let availableSkills = [];
let selectedSkills = [];
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

navItems.forEach((item) => {
  item.addEventListener("click", () => showView(item.dataset.viewTarget));
});

const wizardSteps = [
  {
    title: "Welcome",
    copy:
      "Turn EurekaClaw from a repository into a working research system. The setup should feel guided, not documentation-driven.",
    context:
      "This step sets expectations. Users should understand what EurekaClaw does, how long setup takes, and which parts are required versus optional.",
    bullets: [
      "Explain that the core system can run before optional tools are installed.",
      "Make local-first and controllability part of the onboarding tone.",
      "Offer clear next-step framing instead of dropping users into raw config."
    ],
    cards: [
      ["Core runtime", "Python + dependencies + model access"],
      ["Optional depth", "Lean4, LaTeX, Docker, external APIs"]
    ]
  },
  {
    title: "Environment Detection",
    copy:
      "Inspect what is already available on this machine before asking the user to configure anything manually.",
    context:
      "The backend now exposes real capability checks. This step should eventually surface live Python, Lean4, LaTeX, Docker, skills directory, and model access status directly in the wizard.",
    bullets: [
      "Detect Python version and package availability.",
      "Detect Lean4, pdflatex, Docker, and writable run directories.",
      "Surface results as pass, optional, or action-needed states."
    ],
    cards: [
      ["Runtime", "Live capability data available via /api/capabilities"],
      ["Optional tools", "Lean4, LaTeX, Docker are inspected individually"]
    ]
  },
  {
    title: "Provider Connection",
    copy:
      "Choose how EurekaClaw connects to models without hand-editing environment files on day one.",
    context:
      "The systems page now edits live config values that are persisted back to .env, so onboarding can evolve into a real setup wizard rather than a mock flow.",
    bullets: [
      "Offer provider presets rather than a blank config screen.",
      "Show exactly which fields are required for each mode.",
      "Validate before users move on."
    ],
    cards: [
      ["Anthropic API", "Fastest default path"],
      ["OAuth / ccproxy", "For Claude Pro or Max workflows"],
      ["OpenAI-compatible", "For vLLM, OpenRouter, or custom endpoints"]
    ]
  },
  {
    title: "Base Configuration",
    copy:
      "Translate the most important .env and runtime settings into an understandable control surface.",
    context:
      "This is where users manage primary model, fast model, output format, and iteration counts. The systems page already reflects these values from the backend.",
    bullets: [
      "Expose model and fast-model choices.",
      "Let users choose markdown or LaTeX output.",
      "Explain implications of iteration count and run directories."
    ],
    cards: [
      ["Config API", "Live read and write support is enabled"],
      ["Persistence", "Saved values are written back to .env"]
    ]
  },
  {
    title: "Optional Capabilities",
    copy:
      "Advanced tools should feel like upgrades, not blockers.",
    context:
      "Capability checks now distinguish between available, optional, and missing system features. That makes degraded mode visible and trustworthy.",
    bullets: [
      "Group optional capabilities by benefit, not by package name.",
      "Show users what each capability unlocks.",
      "Support degraded mode when optional tools are unavailable."
    ],
    cards: [
      ["Formal verification", "Lean4"],
      ["PDF generation", "TeX Live / MacTeX"],
      ["Sandboxed code", "Docker"],
      ["Research APIs", "Search, S2, Wolfram"]
    ]
  },
  {
    title: "Skills Installation",
    copy:
      "Built-in seed skills should be a one-click enhancement to the system's reasoning quality.",
    context:
      "The underlying project already supports `eurekaclaw install-skills`. The UI now has enough backend context to surface skills directory readiness and can grow into a true installer flow next.",
    bullets: [
      "Offer install and reinstall actions for seed skills.",
      "List skill families in human terms: survey, ideation, proof, experiment, writing.",
      "Show where skills live and whether custom skills already exist."
    ],
    cards: [
      ["Theory skills", "Induction, contradiction, compactness"],
      ["Survey skills", "Literature decomposition"],
      ["Writing skills", "Paper structure"]
    ]
  },
  {
    title: "Health Check & Next Steps",
    copy:
      "End with a capability snapshot and clear launch paths so users feel ready to begin.",
    context:
      "The workspace can already launch real sessions through the backend. This final step should summarize what is configured and route users straight into a run.",
    bullets: [
      "Run a minimal connectivity and config validation check.",
      "Show what features are available now versus later.",
      "Offer direct actions: prove, explore, inspect system."
    ],
    cards: [
      ["Core run", "The workspace can start real EurekaClaw sessions"],
      ["Live polling", "Pipeline, artifacts, and outputs are fetched from the backend"]
    ]
  }
];

function renderWizardStep(index) {
  const step = wizardSteps[index];
  const progress = ((index + 1) / wizardSteps.length) * 100;

  wizardStage.innerHTML = `
    <div>
      <p class="eyebrow">Installation Flow</p>
      <h4>${step.title}</h4>
    </div>
    <p class="wizard-copy">${step.copy}</p>
    <ul class="wizard-list">
      ${step.bullets.map((bullet) => `<li>${bullet}</li>`).join("")}
    </ul>
    <div class="wizard-grid">
      ${step.cards
        .map(
          ([title, body]) => `
            <div class="wizard-card">
              <strong>${title}</strong>
              <p>${body}</p>
            </div>
          `
        )
        .join("")}
    </div>
  `;

  wizardContext.innerHTML = `
    <p>${step.context}</p>
    <p>
      The setup UI should always answer three questions: what is required, what
      is optional, and what becomes possible after this step.
    </p>
  `;

  wizardProgressBar.style.width = `${progress}%`;
  wizardStepLabel.textContent = `Step ${index + 1} of ${wizardSteps.length}`;
  prevStepBtn.disabled = index === 0;
  nextStepBtn.textContent = index === wizardSteps.length - 1 ? "Finish" : "Next";
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function normalizePathForDisplay(value) {
  if (!value || typeof value !== "string") {
    return value;
  }
  const homePrefixes = [
    "/Users/",
    "/home/"
  ];
  if (value.endsWith("/.eurekaclaw")) {
    for (const prefix of homePrefixes) {
      if (value.startsWith(prefix)) {
        return "~/.eurekaclaw";
      }
    }
  }
  return value;
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
  if (detail) {
    runMetaEl.textContent = detail;
  }
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

  sidebarArtifactsEl.textContent = String(entries.length);

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

function updateSidebar(run, tasks) {
  sidebarModeEl.textContent = run?.input_spec?.mode ? titleCase(run.input_spec.mode) : "Not started";
  const activeTask = (tasks || []).find((task) => task.status === "in_progress");
  sidebarStageEl.textContent = activeTask ? titleCase(activeTask.name) : titleCase(run?.status || "idle");
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
    authGuidanceToggleEl.querySelector(".auth-guidance-toggle-label").textContent = title;
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
    authGuidanceToggleEl.querySelector(".auth-guidance-toggle-label").textContent = title;
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
  authGuidanceToggleEl.querySelector(".auth-guidance-toggle-label").textContent = title;
}

function normalizeInputSpec() {
  const modeLabel = inputModeEl.value;
  const domain = inputDomainEl.value.trim();
  const prompt = inputPromptEl.value.trim();
  const selectedSkillContext = selectedSkills.length
    ? `User-selected skills: ${selectedSkills.join(", ")}`
    : "";

  if (modeLabel === "Reference-driven") {
    return {
      mode: "reference",
      domain,
      query: prompt || `Find gaps in ${domain}`,
      paper_ids: [],
      additional_context: selectedSkillContext,
      selected_skills: selectedSkills
    };
  }

  if (modeLabel === "Open exploration") {
    return {
      mode: "exploration",
      domain,
      query: prompt || `Survey the frontier of ${domain}`,
      additional_context: selectedSkillContext,
      selected_skills: selectedSkills
    };
  }

  return {
    mode: "detailed",
    domain,
    query: prompt,
    conjecture: prompt,
    additional_context: selectedSkillContext,
    selected_skills: selectedSkills
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
        field.value = key === "eurekaclaw_dir" ? normalizePathForDisplay(value ?? "") : (value ?? "");
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
  updateSidebar(run, tasks);
  if (run) {
    setRunStatus(run.status, `Run ${run.run_id.slice(0, 8)} is ${run.status}.`);
  } else {
    setRunStatus("idle", "The UI is connected. Launch a session to start the pipeline.");
  }
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
          <div class="artifact-kv-row"><strong>Problem type</strong><span>${escapeHtml(artifact.problem_type || "—")}</span></div>
          <div class="artifact-kv-row"><strong>Template</strong><span>${escapeHtml(artifact.proof_template || "—")}</span></div>
          <div class="artifact-kv-row"><strong>Formal statement</strong><span>${escapeHtml(artifact.formal_statement || "—")}</span></div>
        </div>
      </section>
      <section class="artifact-section">
        <h4>Analysis & Skeleton</h4>
        <div class="artifact-kv">
          <div class="artifact-kv-row"><strong>Memory theorems</strong><span>${escapeHtml(String((artifact.memory_theorems || []).length))}</span></div>
          <div class="artifact-kv-row"><strong>Analysis notes</strong><span>${escapeHtml((artifact.analysis_notes || "—").slice(0, 320))}</span></div>
          <div class="artifact-kv-row"><strong>Proof skeleton</strong><span>${escapeHtml((artifact.proof_skeleton || "—").slice(0, 320))}</span></div>
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

async function refreshRun(runId) {
  try {
    const run = await apiGet(`/api/runs/${runId}`);
    currentRunId = run.run_id;
    renderRun(run);
    if (run.status === "completed" || run.status === "failed") {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  } catch (error) {
    setRunStatus("missing", `Unable to refresh the run: ${error.message}`);
  }
}

async function loadMostRecentRun() {
  try {
    const data = await apiGet("/api/runs");
    const latest = data.runs[0];
    if (latest) {
      currentRunId = latest.run_id;
      currentLogPage = 1;
      renderRun(latest);
    } else {
      renderRun(null);
    }
  } catch (error) {
    setRunStatus("missing", `Unable to load runs: ${error.message}`);
  }
}

launchSessionBtn.addEventListener("click", async () => {
  launchSessionBtn.disabled = true;
  setRunStatus("running", "Creating a new EurekaClaw session...");
  try {
    const run = await apiPost("/api/runs", normalizeInputSpec());
    currentRunId = run.run_id;
    currentLogPage = 1;
    renderRun(run);
    showView("workspace");

    if (pollTimer) {
      clearInterval(pollTimer);
    }
    pollTimer = setInterval(() => refreshRun(currentRunId), 3000);
  } catch (error) {
    setRunStatus("failed", `Could not start session: ${error.message}`);
  } finally {
    launchSessionBtn.disabled = false;
  }
});

loadExampleBtn.addEventListener("click", () => {
  inputModeEl.value = "Detailed proof";
  inputDomainEl.value = "Machine learning theory";
  inputPromptEl.value =
    "Prove a generalization bound for sparse transformer attention under low-rank kernel assumptions.";
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
    refreshRun(currentRunId);
  }
  if (action === "next") {
    currentLogPage += 1;
    refreshRun(currentRunId);
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
  showView("workspace");
});

renderWizardStep(currentWizardStep);
showView("workspace");
loadCapabilities();
loadConfig();
loadMostRecentRun();
loadSkills();
updateConfigVisibility();
renderAuthGuidance();
setAuthGuidanceOpen(false);
