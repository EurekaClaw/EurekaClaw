# ── EurekaClaw Dockerfile ─────────────────────────────────────────────────────
#
# Multi-stage build:
#   Stage 1 (frontend-builder): Install Node.js deps + build React static assets
#   Stage 2 (runtime):          Python 3.11 + Node.js 18 + all dependencies
#
# Usage:
#   # Build (current platform only)
#   docker build -t eurekaclaw/eurekaclaw .
#
#   # GPU build (NVIDIA)
#   docker build --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-runtime-ubuntu22.04 \
#     -t eurekaclaw/eurekaclaw:gpu .
#
#   # Multi-platform build + push (amd64 + arm64)
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t eurekaclaw/eurekaclaw:latest --push .
#
#   # Run UI (default)
#   docker run --rm -it -p 8080:8080 -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw
#
#   # Run CLI command
#   docker run --rm -it -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw prove "your theorem"
#
#   # Interactive shell
#   docker run --rm -it -e ANTHROPIC_API_KEY=sk-ant-... eurekaclaw bash
#
#   # With .env file + persistent data
#   docker run --rm -it -p 8080:8080 --env-file .env \
#     -v ~/.eurekaclaw:/root/.eurekaclaw eurekaclaw
#
# ──────────────────────────────────────────────────────────────────────────────

# ── Build arg: base image (swap for GPU support) ─────────────────────────────
ARG BASE_IMAGE=python:3.11-slim

# ── Stage 1: Build frontend static assets ────────────────────────────────────
FROM node:18-slim AS frontend-builder

WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci --ignore-scripts 2>/dev/null || npm install

COPY frontend/ ./
COPY eurekaclaw/ui/ /build/eurekaclaw/ui/
RUN npm run build

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM ${BASE_IMAGE} AS runtime

LABEL maintainer="EurekaClaw Contributors"
LABEL description="EurekaClaw — Multi-agent AI research assistant"

# Prevent interactive prompts during apt-get (e.g. tzdata on Ubuntu 22.04)
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# ── System dependencies ──────────────────────────────────────────────────────
# Install Python 3.11 (if base is not python:3.11-slim), Node.js 18, and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git build-essential \
        # For opencv / image processing (docling)
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install Python 3.11 if not already present (needed for CUDA base images)
RUN if ! command -v python3.11 >/dev/null 2>&1 && ! python3 --version 2>&1 | grep -q "3.11"; then \
        apt-get update && apt-get install -y --no-install-recommends \
            software-properties-common \
        && add-apt-repository -y ppa:deadsnakes/ppa \
        && apt-get update && apt-get install -y --no-install-recommends \
            python3.11 python3.11-venv python3.11-dev \
        && rm -rf /var/lib/apt/lists/* \
        && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
        && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1; \
    fi

# Ensure pip is available
RUN python3 -m ensurepip --upgrade 2>/dev/null || true \
    && python3 -m pip install --no-cache-dir --upgrade pip

# Install Node.js 18 (needed for dev mode / frontend rebuilds)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Install uv for fast Python package management ────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && ln -sf /root/.local/bin/uv /usr/local/bin/uv

# ── Application setup ────────────────────────────────────────────────────────
WORKDIR /app

# 1. Copy source and install all dependencies in editable mode
#    (pyproject.toml + README.md + eurekaclaw/ needed together for hatchling build)
COPY pyproject.toml README.md ./
COPY eurekaclaw/ ./eurekaclaw/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --python python3.11 -e ".[all]"

# 2. Copy remaining files (Makefile, frontend, docs, etc.)
COPY . .

# 3. Copy pre-built frontend assets from stage 1
COPY --from=frontend-builder /build/eurekaclaw/ui/static/ /app/eurekaclaw/ui/static/

# 4. Install frontend dependencies (for dev mode / rebuilds)
RUN cd frontend && npm ci --ignore-scripts 2>/dev/null || (cd frontend && npm install)

# 5. Install seed skills
RUN eurekaclaw install-skills 2>/dev/null || true

# ── Runtime configuration ────────────────────────────────────────────────────
EXPOSE 8080
# Persistent data directory
VOLUME ["/root/.eurekaclaw"]

# ── Entrypoint ───────────────────────────────────────────────────────────────
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["ui"]
