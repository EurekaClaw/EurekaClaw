# Session Header Redesign — Calm, Humanist Layout

**Date:** 2026-04-16
**Branch:** `shiyuan/paper-qa-gate`
**Scope:** Frontend only (`frontend/src/components/session/`, `frontend/src/components/controls/`, `frontend/src/styles/`)

## Problem

The top half of a running session's detail pane communicates the same piece of information (*"we are currently in the theory/proof stage"*) four different ways, stacked vertically:

1. `SessionTopBar` — right-side `status-pill` says **Running**
2. `session-status-row` — meta-text says **Running: Theory**
3. `StageTrack` — the 📐 **Proof** node is highlighted
4. `ProofCtrl` running state — live label **Proving the theorem**

This redundancy makes the area feel noisy. The session question title is also hard-truncated at 520px with no way to reveal the full text, so long prompts like *"Prove the sum of two i.i.d. U[0,1] random variables mod 1 is …"* are permanently cut off.

## Design Principles

1. **One source of truth per fact.** The active pipeline stage is communicated exactly once (by the StageTrack's glowing node).
2. **Breathing room over chrome.** Fewer borders, softer separators, calmer colors — Apple-style white/blue aesthetic is preserved.
3. **Progressive disclosure via hover.** Truncated text reveals itself smoothly in place, not via a jumpy tooltip overlay.
4. **Visual hierarchy.** Question (identity) > pipeline (progress) > action (what the user can do).

## Target Layout

### Section A — Session header (identity line)

```
 Prove the sum of two i.i.d. U[0,1] random variables mod 1 is distributed…   ✎
 ───────────────────────────────────────────────────────────────────────────
 ● Proof · 42s                                  176K in · 79K out · 255K
```

- **Title line**
  - Default: single line with CSS ellipsis
  - Hover: CSS transition on `max-height` / `white-space` lifts the clamp, revealing the full question in place. Neighbors shift gently via height transition.
  - Rename pencil icon appears on hover of the identity group (already implemented).
- **Status pill is removed.** The pulsing blue dot + current stage label + elapsed timer replaces it.
- **Meta line below the divider**:
  - Left: `● Proof · 42s` (live dot + humanized active outer stage + elapsed seconds)
  - Right: `176K in · 79K out · 255K` (muted; existing `token-strip` simplified)

### Section B — Pipeline + active action (one unified card)

```
┌──────────────────────────────────────────────────────────────────┐
│    📚 ───── 💡 ───── 📐 ───── 🧪 ───── ✍️                          │
│  Reading   Ideas   Proof   Testing  Writing                       │
│                                                                    │
│  Proving the theorem                          ⏸  Take a break    │
│  Progress is safe — pause will stop at the next checkpoint.      │
└──────────────────────────────────────────────────────────────────┘
```

- `session-status-row` is **deleted** (its token strip now lives in Section A; its redundant `Running: Theory` text is gone).
- `ProofCtrl`'s running state keeps the live label and hint, loses the stage-name duplication (the emoji node already says it).
- Card keeps its current subtle border + backdrop blur, just tightened vertically.

### Bonus — Sidebar session items

- Current: `-webkit-line-clamp: 2` hard-truncates the query text.
- New: default keeps the clamp (compact list). On `:hover`, CSS transition lifts the clamp (`max-height` animates from ~2.8em to ~20em, `-webkit-line-clamp: unset`), revealing the full question in place. Neighbors reflow smoothly.

## Non-Goals

- No change to the lower workspace (AgentTrack, WorkspaceTabs, PaperPanel).
- No change to completed / paused / failed session visuals beyond what falls out of removing the duplicate status pill.
- No change to color palette — still blue/white.

## Files Touched

| File | Change |
|------|--------|
| `frontend/src/components/session/SessionTopBar.tsx` | Drop `status-pill`; merge meta-text + token strip into single identity footer line; use live dot + active stage + elapsed as the status summary |
| `frontend/src/components/controls/ProofCtrl.tsx` | Drop `runningInfo.label` that duplicates the stage name — keep verb phrases ("Proving the theorem"), let the StageTrack node carry the stage identity |
| `frontend/src/components/session/SessionList.tsx` | No JSX change; hover-expand is pure CSS |
| `frontend/src/styles/index.css` | Add hover-expand styles for `.session-topbar-name` and `.session-item-name`; tighten spacing between topbar + proof-ctrl; drop `.session-status-row` rules; restyle token strip as muted footer text |
| `frontend/src/lib/statusHelpers.ts` | Adjust `liveStatusDetail` (or inline a smaller helper) to emit compact `Proof · 42s` form — only used by the new meta line |

## Acceptance Criteria

1. Opening a running session shows the question title once, the active stage once, the elapsed time once — no duplication.
2. Hovering the title smoothly expands it to full multiline text in place (no tooltip chrome, no layout jank).
3. Hovering a sidebar item smoothly expands its clamped text to the full question.
4. The blue/white Apple aesthetic is preserved: soft radii, muted borders, no new loud colors.
5. Completed / paused / failed sessions still render correctly (no leftover references to removed elements).
6. Token counts remain accurate and visible; they just occupy less vertical space.

## Open Questions / Edge Cases

- **Very long titles:** the hover-expanded height is capped (e.g., `max-height: 8em`) so a paragraph-length prompt still fits; further overflow uses a subtle inner scroll.
- **Failed / completed sessions:** the meta line omits the elapsed timer; shows `Completed` or `Failed: <reason>` in the same slot.
- **Queued state:** meta line reads `Queued — waiting to start…`.
