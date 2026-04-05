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
#   make uv-install       → uv venv + uv pip install -e "." + npm install (faster)
#
# Docker:
#   make docker           → build Docker image (CPU, current platform)
#   make docker-gpu       → build Docker image (NVIDIA GPU, current platform)
#   make docker-push      → build + push multi-platform CPU image (amd64 + arm64)
#   make docker-push-gpu  → build + push multi-platform GPU image (amd64 + arm64)
#   make docker-run       → run UI in Docker at http://localhost:8080
#   make docker-run-gpu   → run UI in Docker with GPU at http://localhost:8080
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: start open dev build typecheck install uv-install \
        docker docker-gpu docker-push docker-push-gpu docker-run docker-run-gpu

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
	python -m pip install -e "."
	cd frontend && npm install

# ── First-time setup with uv (faster) ────────────────────────────────────────
uv-install:
	uv venv --python 3.11 --clear .venv
	. .venv/bin/activate && uv pip install -e "."
	cd frontend && npm install

# ── Docker ────────────────────────────────────────────────────────────────────
docker:
	docker build -t eurekaclaw/eurekaclaw:latest .

docker-gpu:
	docker build --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-runtime-ubuntu22.04 \
		-t eurekaclaw/eurekaclaw:gpu .

docker-push:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t eurekaclaw/eurekaclaw:latest --push .

docker-push-gpu:
	docker buildx build --platform linux/amd64,linux/arm64 \
		--build-arg BASE_IMAGE=nvidia/cuda:12.4.1-runtime-ubuntu22.04 \
		-t eurekaclaw/eurekaclaw:gpu --push .

docker-run:
	docker run --rm -it -p 8080:8080 --env-file .env \
		-v ~/.eurekaclaw:/root/.eurekaclaw eurekaclaw/eurekaclaw:latest

docker-run-gpu:
	docker run --rm -it -p 8080:8080 --env-file .env --gpus all \
		-v ~/.eurekaclaw:/root/.eurekaclaw eurekaclaw/eurekaclaw:gpu
