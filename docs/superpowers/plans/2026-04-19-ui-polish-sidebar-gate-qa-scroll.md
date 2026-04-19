# UI Polish: Sidebar Hover / Dead-Session Gate / QA Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three small UX annoyances reported by the user: (1) sidebar session items that unclamp the full question text on hover cause jarring layout jumps for long prompts, (2) a failed session whose pipeline is stuck at an `awaiting_gate` task traps the user behind an unsubmittable gate overlay, (3) the Paper-tab Q&A chat can grow past the viewport because the inner message list doesn't always honour its scroll container.

**Architecture:** Pure frontend polish. No new state, no API changes. CSS-only for (1) and (3); a single guard added to `GateOverlay` for (2).

**Tech Stack:** React 18 + TypeScript + Vite 5.4. No test changes required — fixes are visual/behavioral and covered by the existing manual-verification flow.

---

## Task 1: Sidebar session items — stop the hover unclamp jump

**Files:**
- Modify: `frontend/src/styles/index.css` (rule at `.session-item:hover .session-item-name`)
- Modify: `frontend/src/components/session/SessionList.tsx` (add native `title` on the name)

**Context:** Today `.session-item-name` is clamped to 2 lines by default, but `.session-item:hover` bumps `max-height` to 40em and sets `-webkit-line-clamp: unset`. For long prompts this causes the item to suddenly balloon to 10+ lines as the cursor crosses it, shoving neighbouring items out of the way. Replacement UX: keep the 2-line clamp always, and expose the full text via the browser's native `title` tooltip — zero layout impact, discoverable, accessible.

- [ ] **Step 1: Drop the hover-unclamp CSS rule**

Edit `frontend/src/styles/index.css` at the `.session-item:hover .session-item-name,` rule (around line 353). Delete the entire block:

```css
.session-item:hover .session-item-name,
.session-item:hover .session-item-prompt {
  -webkit-line-clamp: unset;
  max-height: 40em;
  word-break: break-word;
}
```

Leave the default `.session-item-name, .session-item-prompt` rule (with `-webkit-line-clamp: 2; max-height: 2.8em`) untouched.

- [ ] **Step 2: Add native tooltip on the name element**

Edit `frontend/src/components/session/SessionList.tsx` at the name render (currently `<div className="session-item-name">{escapeHtml(humanize(displayName))}</div>`). Change to include the full (un-humanized) text as a `title`:

```tsx
<div className="session-item-name" title={displayName}>
  {escapeHtml(humanize(displayName))}
</div>
```

`displayName` already falls back through `s.name || s.input_spec?.query || s.input_spec?.domain || 'Untitled session'`, so the tooltip shows the most specific available text.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/styles/index.css frontend/src/components/session/SessionList.tsx
git commit -m "sidebar: drop hover-unclamp jump, show full name via native title tooltip"
```

---

## Task 2: GateOverlay — hide on terminal (failed/completed) sessions

**Files:**
- Modify: `frontend/src/components/workspace/GateOverlay.tsx` (early-return guard in the exported `GateOverlay`)

**Context:** The current `GateOverlay` only checks whether any gate task is `awaiting_gate`; it does not consider the run's own status. If the orchestrator crashed while a gate task was awaiting input, the pipeline entry keeps its `awaiting_gate` status on disk even though no-one is listening to `submit_*`. The user then clicks into the session, sees the gate, tries to answer, and the POST hangs / errors without releasing the modal. Fix: if `run.status` is terminal (`failed` or `completed`), the orchestrator is gone — do not render the gate. Running backend cleanup (separate concern) would also work, but this one-line frontend guard removes the trap immediately and correctly, and is a no-op for live sessions.

- [ ] **Step 1: Add the status guard at the top of `GateOverlay`**

Edit `frontend/src/components/workspace/GateOverlay.tsx`. In the exported `GateOverlay` function (currently at line 267), before the `const pipeline = run.pipeline ?? [];` line, add:

```tsx
export function GateOverlay({ run }: Props) {
  // If the orchestrator is gone, the gate has no-one to submit to — don't
  // trap the user behind a modal they can't clear. Pipeline state may still
  // show `awaiting_gate` on disk; the terminal run.status is the source of
  // truth about whether a live submitter exists.
  if (run.status === 'failed' || run.status === 'completed') return null;

  const pipeline = run.pipeline ?? [];
  // …rest unchanged…
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/components/workspace/GateOverlay.tsx
git commit -m "GateOverlay: suppress on terminal sessions so a dead gate can't trap the user"
```

---

## Task 3: QA chat — guarantee the internal scroll container bounds properly

**Files:**
- Modify: `frontend/src/styles/paper-review.css` (add `min-height: 0` to `.qa-chat`; add `word-break` to message bubbles)

**Context:** `.qa-messages` already has `flex: 1; overflow-y: auto; min-height: 0` — the right recipe for an internally-scrollable flex child. But its parent `.qa-chat` uses `flex: 1` without `min-height: 0`. In a nested flex layout (qa-chat sits inside a `display: flex` wrapper inside `.paper-review-panel`), the absence of `min-height: 0` on `.qa-chat` lets the flex-column allow its children to push past the allotted height — so long conversations grow the chat past its container, and the outer `.ws-panel`'s `overflow-y: auto` catches the overflow instead of `.qa-messages`. Adding `min-height: 0` to `.qa-chat` closes this hole. Additionally, very long unbreakable strings in message bubbles (e.g., URLs, raw LaTeX tokens) can widen a bubble past its `max-width` constraint; `word-break: break-word` prevents that horizontal growth without affecting normal prose.

- [ ] **Step 1: Add `min-height: 0` to `.qa-chat`**

Edit `frontend/src/styles/paper-review.css` at the `.qa-chat` rule (around line 213). The current rule:

```css
.qa-chat {
  display: flex;
  flex-direction: column;
  background: var(--surface-strong);
  min-width: 0;
  overflow: hidden;
  flex: 1;
  width: 100%;
  border-radius: 0 var(--radius-lg) var(--radius-lg) 0;
}
```

Add `min-height: 0;` immediately after `min-width: 0;`:

```css
.qa-chat {
  display: flex;
  flex-direction: column;
  background: var(--surface-strong);
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  flex: 1;
  width: 100%;
  border-radius: 0 var(--radius-lg) var(--radius-lg) 0;
}
```

- [ ] **Step 2: Add `word-break` to message bubbles**

In the same file, add `word-break: break-word;` to both `.qa-msg-user` (around line 305) and `.qa-msg-agent` (around line 316). Before:

```css
.qa-msg-user {
  background: var(--primary);
  ...
  max-width: 80%;
  font-size: 0.82rem;
  line-height: 1.55;
  box-shadow: ...;
}
```

After — insert `word-break: break-word;` right after `max-width`:

```css
.qa-msg-user {
  background: var(--primary);
  ...
  max-width: 80%;
  word-break: break-word;
  font-size: 0.82rem;
  line-height: 1.55;
  box-shadow: ...;
}
```

Same for `.qa-msg-agent`.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/styles/paper-review.css
git commit -m "qa-chat: bound the inner scroll container and wrap long tokens in bubbles"
```

---

## Task 4: Verify the build still passes

**Files:** none — runs existing tooling.

- [ ] **Step 1: Typecheck**

```bash
cd /Users/chenggong/Downloads/EurekaClaw/frontend && npm run typecheck
```
Expected: PASS (no type errors — all edits are CSS or add a plain string prop).

- [ ] **Step 2: Existing vitest suite still green**

```bash
cd /Users/chenggong/Downloads/EurekaClaw/frontend && npm run test
```
Expected: same green summary as before (no test changes).

- [ ] **Step 3: No commit needed**

Steps 1–2 are verification gates, not new code.

---

## Rollout summary

| # | Task | Commits |
|---|---|---|
| 1 | Sidebar hover unclamp → native title tooltip | 1 |
| 2 | GateOverlay suppression on terminal runs | 1 |
| 3 | QA chat inner-scroll containment + word-break | 1 |
| 4 | Typecheck + vitest verification | 0 |
| **Total** | | **3** |

One branch, three commits, frontend-only, no API changes, no feature flags.
