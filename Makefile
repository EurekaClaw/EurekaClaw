# ── EurekaClaw — top-level shortcuts ────────────────────────────────────────
#
# Production (serves built assets via the Python backend):
#   make start            → build frontend → launch UI at http://localhost:8080
#   make open             → same, auto-opens browser tab
#
# Development (hot-reload frontend + Python backend):
#   make dev              → Vite on :5173 (proxies /api → :7860) + Python on :7860
#
# Frontend only:
#   make build            → tsc + vite build → eurekaclaw/ui/static/
#   make typecheck        → tsc --noEmit (no output files)
#
# Install:
#   make install          → pip install -e "." + npm install (frontend deps)
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: start open dev build typecheck install

# ── Production: build then serve ─────────────────────────────────────────────
start: build
	eurekaclaw ui

open: build
	eurekaclaw ui --open-browser

# ── Development: Python backend on :7860 + Vite dev server on :5173 ─────────
dev:
	cd frontend && npm run dev:all

# ── Frontend build ────────────────────────────────────────────────────────────
build:
	cd frontend && npm run build

typecheck:
	cd frontend && npm run typecheck

# ── First-time setup ──────────────────────────────────────────────────────────
install:
	pip install -e "."
	cd frontend && npm install
