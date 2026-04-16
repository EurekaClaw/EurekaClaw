# Paper QA Gate — UI Design Spec

## Overview

Add a full-panel Paper Review experience to the frontend when the `paper_qa_gate` activates. Replaces the current modal overlay with an immersive split view: PDF/LaTeX preview on the left, streaming QA chat on the right, with a resizable divider. Preserves the blue/white theme and integrates with the existing gate system.

## Problem

The current `PaperQAGate` in `GateOverlay.tsx` is a simple modal with a textarea and rebuttal/rewrite toggle. It does not:
- Show the paper content (user must separately navigate to PaperPanel)
- Support multi-turn QA conversation
- Display tool usage (arXiv search, section reading) during agent responses
- Show rewrite progress
- Track paper versions across rewrites

## Goals

1. Full-panel takeover replacing workspace content when paper_qa_gate is active
2. Resizable split view: PDF/LaTeX tabs (left) + QA chat (right), default 55/45
3. Streaming QA with visible tool steps (Claude Code-style progress indicators)
4. Rewrite progress overlay on paper side while chat remains scrollable
5. Paper versioning indicator and download buttons
6. Feature parity with CLI (accept, multi-turn QA, rewrite loop)
7. Preserve blue/white theme, Space Grotesk typography, existing gate patterns
8. No changes to existing gates (survey, direction, theory review)

## Non-Goals

- Changing the CLI implementation (already complete)
- Modifying other gate overlays
- Adding new backend endpoints beyond what's needed for streaming

## Architecture

### Component Structure

```
App.tsx
  └── WorkspaceTabs / WorkspaceSplit
        ├── (normal tabs: Paper, Proof, Logs, Live)  ← hidden when gate active
        └── PaperReviewPanel (new)                    ← shown when paper_qa_gate active
              ├── PaperViewer (left side)
              │     ├── TabBar (PDF | LaTeX + download buttons)
              │     ├── PdfView (iframe embed)
              │     ├── LatexView (syntax-highlighted source)
              │     ├── RewriteOverlay (progress spinner + steps)
              │     └── VersionBar (bottom: paper version indicator)
              ├── ResizableDivider
              └── QAChat (right side)
                    ├── ChatHeader (title + message count / status badge)
                    ├── MessageList (scrollable)
                    │     ├── UserMessage (blue bubble, right-aligned)
                    │     ├── AgentMessage (white card, left-aligned)
                    │     │     └── ToolSteps (collapsed badges above answer)
                    │     └── SystemMessage (centered amber pill for rewrite triggers)
                    ├── ChatInput (textarea + send button)
                    └── ActionBar (Accept Paper | Rewrite Paper)
```

### New Files

| File | Purpose |
|------|---------|
| `frontend/src/components/workspace/PaperReviewPanel.tsx` | Main split-view container with resizable divider |
| `frontend/src/components/workspace/paper-review/PaperViewer.tsx` | Left panel: PDF/LaTeX tabs, download, version bar |
| `frontend/src/components/workspace/paper-review/QAChat.tsx` | Right panel: chat messages, input, action buttons |
| `frontend/src/components/workspace/paper-review/RewriteOverlay.tsx` | Progress overlay during theory+writer re-run |
| `frontend/src/components/workspace/paper-review/ChatMessage.tsx` | Individual message component (user/agent/system variants) |
| `frontend/src/components/workspace/paper-review/ToolSteps.tsx` | Collapsed tool usage badges with status indicators |
| `frontend/src/styles/paper-review.css` | Styles for all paper review components |

### Modified Files

| File | Change |
|------|--------|
| `frontend/src/components/workspace/GateOverlay.tsx` | Remove PaperQAGate case — no longer rendered as modal |
| `frontend/src/App.tsx` or `WorkspaceTabs.tsx` | Conditionally render PaperReviewPanel when paper_qa_gate is active |
| `frontend/src/hooks/usePolling.ts` | Add auto-tab switch when paper_qa_gate activates |
| `frontend/src/types/run.ts` | Add `paper_qa_history` to Artifacts type |
| `eurekaclaw/ui/server.py` | Add endpoint for QA message submission + streaming; serve QA history |

## Component Details

### PaperReviewPanel

Container with CSS flexbox layout and a draggable divider.

**State:**
- `splitRatio: number` — default 55, persisted in localStorage
- `activeTab: 'pdf' | 'latex'` — default 'pdf'
- `isRewriting: boolean` — true during theory+writer re-execution
- `messages: ChatMessage[]` — QA conversation history
- `paperVersion: number` — current paper version

**Activation logic:**
```typescript
const paperQATask = run?.pipeline?.find(t => t.name === 'paper_qa_gate');
const isReviewActive = paperQATask?.status === 'awaiting_gate';
```

When `isReviewActive` is true, the normal workspace tabs are replaced with `PaperReviewPanel`.

### PaperViewer (Left Panel)

**Tab bar:**
- Two tabs: "PDF" (default) and "LaTeX"
- Download buttons on the right: "⬇ .tex" and "⬇ .pdf" (compact pill style)
- Uses existing artifact download endpoints

**PDF tab:**
- `<iframe>` pointing to `/api/runs/{run_id}/artifacts/paper.pdf`
- If PDF not yet compiled, show "Compile PDF" button that calls `/api/runs/{run_id}/compile-pdf`
- Scrollable within the iframe

**LaTeX tab:**
- Syntax-highlighted LaTeX source from `run.result.latex_paper`
- Monospace font (IBM Plex Mono), line numbers optional
- Copy-to-clipboard button in top-right corner

**Version bar (bottom):**
- Shows "Paper v{n}" with line count
- During rewrite: "v{n} → v{n+1} generating..."
- Green "Compiled" badge when PDF is available

### RewriteOverlay

Positioned absolute over the PaperViewer.

**Visual:**
- Semi-transparent backdrop (`rgba(255,253,249,0.85)`) with `backdrop-filter: blur(2px)`
- Centered content: spinner, title, description, step progress
- Step progress shows Theory Agent (spinning/done) and Writer Agent (waiting/spinning/done)

**Behavior:**
- Appears when user clicks "Rewrite Paper" and backend confirms
- Polling detects when theory/writer tasks change status
- Disappears when writer completes: overlay fades out, paper content refreshes
- On failure: overlay shows error message with "Keep current paper" button

### QAChat (Right Panel)

**ChatHeader:**
- Title: "Paper Q&A"
- Right side: message count badge (normal) or amber "Rewriting..." badge (during rewrite)

**MessageList:**
- Scrollable container, auto-scrolls to bottom on new messages
- Three message types:
  1. **UserMessage**: right-aligned, blue background (#0f6ab8), white text, rounded bubble
  2. **AgentMessage**: left-aligned, white background with border, dark text
     - Preceded by **ToolSteps** component when agent used tools
  3. **SystemMessage**: centered, amber pill, used for rewrite trigger notifications

**ToolSteps:**
- Collapsed by default: row of small badges above the answer
- Each badge: green dot (completed) or blue pulsing dot (in-progress) + tool name + brief args
- Clickable to expand and show full tool result (optional, can defer)

**ChatInput:**
- Textarea with "Ask about the paper..." placeholder
- Send button (blue, right side)
- Enter to send, Shift+Enter for newline
- Disabled during rewrite (grayed out, "Waiting for rewrite to complete..." placeholder)

**ActionBar (below input):**
- Two buttons:
  - "✓ Accept Paper" — ghost style, calls `/api/runs/{run_id}/gate/paper_qa` with `action: "no"`
  - "↻ Rewrite Paper" — primary-soft style, prompts for revision instructions then calls with `action: "rewrite"`
- Accept ends the gate, pipeline continues
- Rewrite triggers the rewrite flow

### Resizable Divider

- 5px wide vertical bar between left and right panels
- Cursor changes to `col-resize` on hover
- Drag to resize, clamped between 30% and 70%
- Split ratio persisted in `localStorage` under key `eurekaclaw-review-split`

## API Changes

### New: POST `/api/runs/{run_id}/paper-qa/ask`

Submits a QA question for the PaperQAAgent to answer. The handler on the backend calls `PaperQAAgent.ask()` and streams the response.

**Request:**
```json
{
  "question": "Is the bound tight?",
  "history": [
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ]
}
```

**Response:**
```json
{
  "answer": "The bound O(n²) follows from...",
  "tool_steps": [
    {"tool": "arxiv_search", "input": "spectral gap tight bound", "status": "done"},
    {"tool": "latex_section_read", "input": "Theorem 2", "status": "done"}
  ]
}
```

### New: GET `/api/runs/{run_id}/paper-qa/history`

Returns the QA conversation history from the JSONL file.

**Response:**
```json
{
  "messages": [
    {"role": "user", "content": "...", "ts": "...", "version": 1},
    {"role": "assistant", "content": "...", "ts": "...", "version": 1}
  ]
}
```

### Modified: POST `/api/runs/{run_id}/gate/paper_qa`

Existing endpoint. Three actions:
- `action: "no"` — accept paper, gate completes
- `action: "rebuttal"` — (kept for backward compat, but frontend now uses `/paper-qa/ask` directly)
- `action: "rewrite"` — triggers theory+writer re-run with `question` as revision prompt

## Data Flow

```
paper_qa_gate status → awaiting_gate
    │
    ▼
Polling detects → PaperReviewPanel renders
    │
    ├── PaperViewer loads PDF/LaTeX from artifacts
    │
    └── QAChat loads history from /paper-qa/history
         │
         ├── User types question → POST /paper-qa/ask
         │     → AgentMessage with ToolSteps rendered
         │     → History auto-saved server-side
         │
         ├── User clicks "Accept Paper"
         │     → POST /gate/paper_qa {action: "no"}
         │     → Gate completes → panel closes → normal workspace
         │
         └── User clicks "Rewrite Paper"
               → Input area expands: placeholder changes to "Describe what to fix..."
               → POST /gate/paper_qa {action: "rewrite", question: "..."}
               → RewriteOverlay appears
               → Polling detects theory/writer task changes
               → Writer completes → overlay fades → paper refreshes
               → Gate re-arms → user can review again
```

## Styling

All new styles go in `frontend/src/styles/paper-review.css`, imported from `index.css`.

**Design tokens used (from existing theme):**
- `--primary: #0f6ab8` — user messages, active tabs, send button
- `--primary-soft: #dceafb` — hover states, subtle highlights
- `--surface-strong: #fffdf9` — agent message background, paper viewer
- `--surface-cool: #f4f1ec` — input background, tool step badges
- `--text: #1d2736` — primary text
- `--muted: #5f6b7a` — secondary text, timestamps
- `--line: #e2ddd5` — borders, dividers
- `--ok: #547765` — completed tool step dots
- `--warn: #9b6b30` — rewriting status, system messages
- Font: Space Grotesk (body), IBM Plex Mono (LaTeX source)

**Component-specific styles:**

```css
/* Chat bubbles */
.qa-msg-user { background: var(--primary); color: #fff; border-radius: 14px 14px 4px 14px; }
.qa-msg-agent { background: var(--surface-strong); border: 1px solid var(--line); border-radius: 14px 14px 14px 4px; }
.qa-msg-system { background: #fdf3e4; border: 1px solid #f0dfc0; color: var(--warn); border-radius: 10px; }

/* Tool step badges */
.tool-step { background: var(--surface-cool); border-radius: 8px; font-size: 0.68rem; }
.tool-step-dot-done { background: var(--ok); }
.tool-step-dot-active { background: var(--primary); animation: pulse 1.2s infinite; }

/* Rewrite overlay */
.rewrite-overlay { background: rgba(255,253,249,0.85); backdrop-filter: blur(2px); }

/* Resizable divider */
.review-divider { width: 5px; background: var(--line); cursor: col-resize; }
.review-divider:hover { background: var(--primary-soft); }
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| QA Agent fails on a question | Show error in chat as agent message with red accent, user can ask again |
| PDF compilation fails | Show "Compile failed" in PDF tab with retry button, LaTeX tab still works |
| Rewrite fails (theory or writer) | Overlay shows error + "Keep current paper" button, tasks restored to COMPLETED |
| Network error during QA | Toast notification, message shows retry button |
| Browser refresh during review | History loaded from `/paper-qa/history`, panel re-renders in correct state |

## Testing Strategy

- Unit tests for ResizableDivider drag logic
- Unit tests for ChatMessage rendering (user/agent/system variants)
- Unit tests for ToolSteps collapsed/expanded states
- Integration test: gate activation → panel render → accept flow
- Integration test: QA ask → response display → tool steps
- Integration test: rewrite flow → overlay → completion → refresh
