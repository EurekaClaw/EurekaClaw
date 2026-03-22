#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.eurekaclaw-ui"

echo "==> Creating local virtual environment at ${VENV_DIR}"
python3 -m venv "${VENV_DIR}"

echo "==> Upgrading pip"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip

echo "==> Installing EurekaClaw UI dependencies"
"${VENV_DIR}/bin/pip" install -e "${ROOT_DIR}[openai,oauth]"

echo "==> Installing bundled seed skills"
"${VENV_DIR}/bin/eurekaclaw" install-skills || true

cat <<EOF

EurekaClaw UI is installed.

Start it with:
  ${VENV_DIR}/bin/eurekaclaw ui --open-browser

If you prefer to activate the environment first:
  source "${VENV_DIR}/bin/activate"
  eurekaclaw ui --open-browser

EOF
