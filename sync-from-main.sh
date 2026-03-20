#!/usr/bin/env bash
# sync-from-main.sh
#
# Safely pulls non-UI changes from origin/main into the current branch.
# UI files (frontend/, eurekaclaw/ui/) are always kept at their current
# version — main's changes to these files are silently ignored.
#
# Usage:
#   chmod +x sync-from-main.sh
#   ./sync-from-main.sh

set -euo pipefail

UI_FILES=(
  "frontend/app.js"
  "frontend/index.html"
  "frontend/styles.css"
  "eurekaclaw/ui/static/app.js"
  "eurekaclaw/ui/static/index.html"
  "eurekaclaw/ui/static/styles.css"
  "eurekaclaw/ui/server.py"
)

echo "==> Fetching origin/main..."
git fetch origin main

echo "==> Merging origin/main (no-commit)..."
if ! git merge origin/main --no-commit --no-ff 2>&1; then
  # If there are non-UI conflicts, show them and exit for manual resolution
  CONFLICTS=$(git diff --name-only --diff-filter=U)
  UI_CONFLICTS=""
  OTHER_CONFLICTS=""
  for f in $CONFLICTS; do
    IS_UI=false
    for ui in "${UI_FILES[@]}"; do
      if [ "$f" = "$ui" ]; then IS_UI=true; break; fi
    done
    if $IS_UI; then UI_CONFLICTS="$UI_CONFLICTS $f"; else OTHER_CONFLICTS="$OTHER_CONFLICTS $f"; fi
  done

  if [ -n "$UI_CONFLICTS" ]; then
    echo "   [auto-resolving UI conflicts with our version]:$UI_CONFLICTS"
    git checkout HEAD --$UI_CONFLICTS
    git add$UI_CONFLICTS
  fi

  if [ -n "$OTHER_CONFLICTS" ]; then
    echo ""
    echo "!! Non-UI conflicts need manual resolution:"
    for f in $OTHER_CONFLICTS; do echo "   - $f"; done
    echo ""
    echo "   Resolve them, then run:"
    echo "     git add <resolved files>"
    echo "     git commit"
    exit 1
  fi
fi

echo "==> Restoring UI files from chenggong (ignoring main's UI changes)..."
git checkout HEAD -- "${UI_FILES[@]}"
git add "${UI_FILES[@]}"

echo "==> Committing merge..."
git commit --no-edit -m "chore: sync from origin/main (UI files preserved)"

echo ""
echo "Done! All non-UI changes from origin/main are in. UI files untouched."
