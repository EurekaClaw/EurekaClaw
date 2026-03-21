#!/bin/bash
set -euo pipefail

# ── EurekaClaw Installer ──────────────────────────────────────────────────────
# macOS and Linux (including WSL).
#
# Usage:
#   curl -fsSL https://eurekaclaw.ai/install.sh | bash
#   curl -fsSL https://eurekaclaw.ai/install.sh | bash -s -- --install-method git
#
# Environment variable overrides mirror every --flag below.

# ── colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'
ACCENT='\033[38;2;100;180;255m'    # EurekaClaw blue
INFO='\033[38;2;136;146;176m'
SUCCESS='\033[38;2;0;229;204m'
WARN='\033[38;2;255;176;32m'
ERROR='\033[38;2;230;57;70m'
MUTED='\033[38;2;90;100;128m'
NC='\033[0m'

# ── defaults (overridable via env) ────────────────────────────────────────────
EUREKACLAW_REPO_URL="${EUREKACLAW_REPO_URL:-https://github.com/EurekaClaw/EurekaClaw_dev_zero.git}"
GIT_DIR_DEFAULT="${HOME}/eurekaclaw"

INSTALL_METHOD="${EUREKACLAW_INSTALL_METHOD:-git}"
GIT_DIR="${EUREKACLAW_GIT_DIR:-${GIT_DIR_DEFAULT}}"
GIT_UPDATE="${EUREKACLAW_GIT_UPDATE:-1}"
EXTRAS="${EUREKACLAW_EXTRAS:-all}"
NO_ONBOARD="${EUREKACLAW_NO_ONBOARD:-0}"
NO_PROMPT="${EUREKACLAW_NO_PROMPT:-0}"
DRY_RUN="${EUREKACLAW_DRY_RUN:-0}"
VERBOSE="${EUREKACLAW_VERBOSE:-0}"
HELP=0

ORIGINAL_PATH="${PATH:-}"
OS="unknown"
PYTHON_BIN=""
EUREKACLAW_BIN=""

# ── temp file cleanup ─────────────────────────────────────────────────────────
TMPFILES=()
cleanup_tmpfiles() {
    local f
    for f in "${TMPFILES[@]:-}"; do
        rm -rf "$f" 2>/dev/null || true
    done
}
trap cleanup_tmpfiles EXIT

mktempfile() {
    local f
    f="$(mktemp)"
    TMPFILES+=("$f")
    echo "$f"
}

# ── downloader ────────────────────────────────────────────────────────────────
DOWNLOADER=""

detect_downloader() {
    command -v curl &>/dev/null && { DOWNLOADER="curl"; return 0; }
    command -v wget &>/dev/null && { DOWNLOADER="wget"; return 0; }
    ui_error "curl or wget is required but neither was found"
    exit 1
}

download_file() {
    local url="$1" output="$2"
    if [[ -z "$DOWNLOADER" ]]; then detect_downloader; fi
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 -o "$output" "$url"
    else
        wget -q --https-only --secure-protocol=TLSv1_2 --tries=3 -O "$output" "$url"
    fi
}

# ── gum (optional interactive TUI) ───────────────────────────────────────────
GUM=""
GUM_VERSION="${EUREKACLAW_GUM_VERSION:-0.17.0}"
GUM_STATUS="skipped"
GUM_REASON=""

is_non_interactive_shell() {
    if [[ "${NO_PROMPT:-0}" == "1" ]]; then return 0; fi
    if [[ ! -t 0 || ! -t 1 ]];        then return 0; fi
    return 1
}

gum_is_tty() {
    if [[ -n "${NO_COLOR:-}"         ]]; then return 1; fi
    if [[ "${TERM:-dumb}" == "dumb"  ]]; then return 1; fi
    if [[ -t 2 || -t 1               ]]; then return 0; fi
    if [[ -r /dev/tty && -w /dev/tty ]]; then return 0; fi
    return 1
}

gum_detect_os()   {
    case "$(uname -s 2>/dev/null || true)" in
        Darwin) echo "Darwin" ;; Linux) echo "Linux" ;; *) echo "unsupported" ;;
    esac
}
gum_detect_arch() {
    case "$(uname -m 2>/dev/null || true)" in
        x86_64|amd64)  echo "x86_64" ;;
        arm64|aarch64) echo "arm64"  ;;
        *)             echo "unknown" ;;
    esac
}

verify_sha256() {
    local dir="$1"
    if   command -v sha256sum >/dev/null 2>&1; then
        (cd "$dir" && sha256sum --ignore-missing -c checksums.txt >/dev/null 2>&1)
    elif command -v shasum    >/dev/null 2>&1; then
        (cd "$dir" && shasum -a 256 --ignore-missing -c checksums.txt >/dev/null 2>&1)
    else
        return 1
    fi
}

bootstrap_gum_temp() {
    is_non_interactive_shell && { GUM_REASON="non-interactive"; return 1; }
    gum_is_tty              || { GUM_REASON="no tty";           return 1; }
    command -v tar >/dev/null 2>&1 || { GUM_REASON="tar missing"; return 1; }

    if command -v gum >/dev/null 2>&1; then
        GUM="gum"; GUM_STATUS="found"; GUM_REASON="already installed"; return 0
    fi

    local os arch
    os="$(gum_detect_os)"; arch="$(gum_detect_arch)"
    [[ "$os" == "unsupported" || "$arch" == "unknown" ]] && {
        GUM_REASON="unsupported os/arch (${os}/${arch})"; return 1
    }

    local asset base tmpdir gum_path
    asset="gum_${GUM_VERSION}_${os}_${arch}.tar.gz"
    base="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}"
    tmpdir="$(mktemp -d)"; TMPFILES+=("$tmpdir")

    download_file "${base}/${asset}"       "${tmpdir}/${asset}"       2>/dev/null || { GUM_REASON="download failed";    return 1; }
    download_file "${base}/checksums.txt"  "${tmpdir}/checksums.txt"  2>/dev/null || { GUM_REASON="checksum download failed"; return 1; }
    verify_sha256 "$tmpdir"                                                        || { GUM_REASON="checksum mismatch"; return 1; }
    tar -xzf "${tmpdir}/${asset}" -C "$tmpdir" >/dev/null 2>&1                    || { GUM_REASON="extract failed";    return 1; }

    gum_path="$(find "$tmpdir" -type f -name gum 2>/dev/null | head -n1 || true)"
    [[ -n "$gum_path" ]] || { GUM_REASON="binary missing after extract"; return 1; }
    chmod +x "$gum_path"
    GUM="$gum_path"; GUM_STATUS="installed"; GUM_REASON="temp, verified"
    return 0
}

# ── UI helpers ────────────────────────────────────────────────────────────────
ui_info() {
    if [[ -n "$GUM" ]]; then "$GUM" log --level info  "$*"
    else echo -e "${MUTED}·${NC} $*"; fi
}
ui_warn() {
    if [[ -n "$GUM" ]]; then "$GUM" log --level warn  "$*"
    else echo -e "${WARN}!${NC} $*"; fi
}
ui_error() {
    if [[ -n "$GUM" ]]; then "$GUM" log --level error "$*"
    else echo -e "${ERROR}✗${NC} $*"; fi
}
ui_success() {
    if [[ -n "$GUM" ]]; then
        local mark; mark="$("$GUM" style --foreground "#00e5cc" --bold "✓")"
        echo "${mark} $*"
    else
        echo -e "${SUCCESS}✓${NC} $*"
    fi
}
ui_section() {
    if [[ -n "$GUM" ]]; then
        "$GUM" style --bold --foreground "#64b4ff" --padding "1 0" "$*"
    else
        echo -e "\n${ACCENT}${BOLD}$*${NC}"
    fi
}

INSTALL_STAGE_CURRENT=0
INSTALL_STAGE_TOTAL=3

ui_stage() {
    INSTALL_STAGE_CURRENT=$((INSTALL_STAGE_CURRENT + 1))
    ui_section "[${INSTALL_STAGE_CURRENT}/${INSTALL_STAGE_TOTAL}] $*"
}

ui_celebrate() {
    if [[ -n "$GUM" ]]; then "$GUM" style --bold --foreground "#00e5cc" "$*"
    else echo -e "${SUCCESS}${BOLD}$*${NC}"; fi
}

ui_kv() {
    local key="$1" value="$2"
    if [[ -n "$GUM" ]]; then
        local kp vp
        kp="$("$GUM" style --foreground "#5a6480" --width 22 "$key")"
        vp="$("$GUM" style --bold "$value")"
        "$GUM" join --horizontal "$kp" "$vp"
    else
        echo -e "${MUTED}${key}:${NC} ${value}"
    fi
}

is_shell_function() { declare -F "${1:-}" >/dev/null 2>&1; }

run_with_spinner() {
    local title="$1"; shift
    if [[ -n "$GUM" ]] && gum_is_tty && ! is_shell_function "${1:-}"; then
        "$GUM" spin --spinner dot --title "$title" -- "$@" || "$@"
    else
        "$@"
    fi
}

run_quiet_step() {
    local title="$1"; shift
    if [[ "$VERBOSE" == "1" ]]; then
        run_with_spinner "$title" "$@"
        return $?
    fi
    local log
    log="$(mktempfile)"
    if [[ -n "$GUM" ]] && gum_is_tty && ! is_shell_function "${1:-}"; then
        local cmd_q log_q
        printf -v cmd_q '%q ' "$@"
        printf -v log_q '%q'  "$log"
        if run_with_spinner "$title" bash -c "${cmd_q}>${log_q} 2>&1"; then return 0; fi
    else
        if "$@" >"$log" 2>&1; then return 0; fi
    fi
    ui_error "${title} failed — re-run with --verbose for details"
    [[ -s "$log" ]] && tail -n 40 "$log" >&2 || true
    return 1
}

# ── arg parsing ───────────────────────────────────────────────────────────────
print_usage() {
    cat <<EOF
EurekaClaw installer — macOS + Linux

Usage:
  curl -fsSL https://eurekaclaw.ai/install.sh | bash
  curl -fsSL https://eurekaclaw.ai/install.sh | bash -s -- [options]

Options:
  --install-method, --method git    Install from a git checkout (default; only supported method)
  --git, --github                   Shortcut for --install-method git
  --git-dir, --dir <path>           Checkout directory (default: ~/eurekaclaw)
  --no-git-update                   Skip git pull for an existing checkout
  --extras <groups>                 pip extras to install, e.g. "all" (default), ""
  --no-onboard                      Skip post-install setup prompt
  --no-prompt                       Disable interactive prompts (CI / automation)
  --dry-run                         Print what would happen; make no changes
  --verbose                         Print full output from each step
  --help, -h                        Show this help

Environment variable equivalents:
  EUREKACLAW_INSTALL_METHOD   EUREKACLAW_GIT_DIR     EUREKACLAW_GIT_UPDATE
  EUREKACLAW_EXTRAS           EUREKACLAW_NO_ONBOARD  EUREKACLAW_NO_PROMPT
  EUREKACLAW_DRY_RUN          EUREKACLAW_VERBOSE     EUREKACLAW_REPO_URL

Examples:
  # default git install
  curl -fsSL https://eurekaclaw.ai/install.sh | bash

  # custom checkout dir, no onboarding
  curl -fsSL https://eurekaclaw.ai/install.sh | bash -s -- \\
      --git-dir ~/projects/eurekaclaw --no-onboard

  # CI / non-interactive
  EUREKACLAW_NO_PROMPT=1 EUREKACLAW_NO_ONBOARD=1 \\
      bash <(curl -fsSL https://eurekaclaw.ai/install.sh)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-method|--method) INSTALL_METHOD="$2"; shift 2 ;;
            --git|--github)            INSTALL_METHOD="git"; shift   ;;
            --git-dir|--dir)           GIT_DIR="$2";         shift 2 ;;
            --no-git-update)           GIT_UPDATE=0;         shift   ;;
            --extras)                  EXTRAS="$2";          shift 2 ;;
            --no-onboard)              NO_ONBOARD=1;         shift   ;;
            --no-prompt)               NO_PROMPT=1;          shift   ;;
            --dry-run)                 DRY_RUN=1;            shift   ;;
            --verbose)                 VERBOSE=1;            shift   ;;
            --help|-h)                 HELP=1;               shift   ;;
            *)                                               shift   ;;
        esac
    done
}

configure_verbose() {
    if [[ "$VERBOSE" != "1" ]]; then return 0; fi
    set -x
}

# ── OS detection ──────────────────────────────────────────────────────────────
detect_os_or_die() {
    if   [[ "$OSTYPE" == "darwin"*                    ]]; then OS="macos"
    elif [[ "$OSTYPE" == "linux-gnu"*                 ]]; then OS="linux"
    elif [[ -n "${WSL_DISTRO_NAME:-}"                 ]]; then OS="linux"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        # Windows (Git Bash / Cygwin) — point to the PowerShell installer
        ui_error "Windows is not yet supported by this bash installer."
        echo ""
        echo "  Coming soon:"
        echo "    powershell -c \"irm https://eurekaclaw.ai/install.ps1 | iex\""
        echo ""
        echo "  In the meantime, use WSL2:"
        echo "    https://docs.microsoft.com/en-us/windows/wsl/install"
        # TODO: implement install.ps1 for native Windows support
        exit 1
    fi

    if [[ "$OS" == "unknown" ]]; then
        ui_error "Unsupported operating system"
        echo "This installer supports macOS and Linux (including WSL)."
        exit 1
    fi

    ui_success "Detected OS: ${OS}"
}

# ── Homebrew (macOS only) ─────────────────────────────────────────────────────
resolve_brew_bin() {
    command -v brew 2>/dev/null                && return 0
    [[ -x "/opt/homebrew/bin/brew" ]] && { echo "/opt/homebrew/bin/brew"; return 0; }
    [[ -x "/usr/local/bin/brew"    ]] && { echo "/usr/local/bin/brew";    return 0; }
    return 1
}

activate_brew_for_session() {
    local bin; bin="$(resolve_brew_bin || true)"
    if [[ -z "$bin" ]]; then return 1; fi
    eval "$("$bin" shellenv)"
}

is_macos_admin_user() {
    [[ "$OS" != "macos" ]]      && return 0
    [[ "$(id -u)" -eq 0 ]]      && return 0
    id -Gn "$(id -un)" 2>/dev/null | grep -qw "admin"
}

install_homebrew() {
    if [[ "$OS" != "macos" ]]; then return 0; fi
    local bin; bin="$(resolve_brew_bin || true)"
    if [[ -n "$bin" ]]; then
        activate_brew_for_session || true
        ui_success "Homebrew already installed"
        return 0
    fi
    if ! is_macos_admin_user; then
        ui_error "Homebrew installation requires a macOS Administrator account."
        echo "Run the installer from an admin account or install Homebrew manually:"
        echo "  https://brew.sh"
        exit 1
    fi
    ui_info "Homebrew not found — installing"
    local tmp; tmp="$(mktempfile)"
    download_file "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$tmp"
    run_quiet_step "Installing Homebrew" /bin/bash "$tmp"
    activate_brew_for_session || true
    ui_success "Homebrew installed"
}

# ── Python ────────────────────────────────────────────────────────────────────
MIN_PYTHON_MAJOR=3
MIN_PYTHON_MINOR=11

python_version_ok() {
    local bin="$1"
    if [[ -z "$bin" || ! -x "$bin" ]]; then return 1; fi
    local major minor
    read -r major minor < <("$bin" -c \
        'import sys; print(sys.version_info.major, sys.version_info.minor)' 2>/dev/null || true)
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
    if [[ "$major" -gt "$MIN_PYTHON_MAJOR" ]]; then return 0; fi
    if [[ "$major" -eq "$MIN_PYTHON_MAJOR" && "$minor" -ge "$MIN_PYTHON_MINOR" ]]; then return 0; fi
    return 1
}

find_python() {
    local candidates=(
        python3 python3.13 python3.12 python3.11
        /opt/homebrew/bin/python3
        /opt/homebrew/opt/python@3.11/bin/python3
        /usr/local/bin/python3
        /usr/bin/python3
    )
    for bin in "${candidates[@]}"; do
        local resolved
        resolved="$(command -v "$bin" 2>/dev/null || true)"
        if [[ -n "$resolved" ]] && python_version_ok "$resolved"; then
            PYTHON_BIN="$resolved"
            return 0
        fi
    done
    return 1
}

is_root() { [[ "$(id -u)" -eq 0 ]]; }

require_sudo() {
    if [[ "$OS" != "linux" ]]; then return 0; fi
    if is_root;              then return 0; fi
    command -v sudo &>/dev/null || { ui_error "sudo is required but not found"; exit 1; }
    sudo -n true >/dev/null 2>&1 || { ui_info "Administrator privileges required; enter your password"; sudo -v; }
}

install_python_macos() {
    local brew_bin; brew_bin="$(resolve_brew_bin || true)"
    if [[ -z "$brew_bin" ]]; then
        ui_error "Homebrew is required to install Python on macOS"
        exit 1
    fi
    activate_brew_for_session || true
    run_quiet_step "Installing Python 3.11" "$brew_bin" install python@3.11
    activate_brew_for_session || true
    # Prepend Homebrew Python to PATH for this session
    local prefix; prefix="$("$brew_bin" --prefix python@3.11 2>/dev/null || true)"
    if [[ -d "${prefix}/bin" ]]; then export PATH="${prefix}/bin:${PATH}"; fi
    hash -r 2>/dev/null || true
}

install_python_linux() {
    require_sudo
    if command -v apt-get &>/dev/null; then
        if is_root; then
            run_quiet_step "Updating package index"    apt-get update -qq
            run_quiet_step "Installing Python 3.11"   apt-get install -y -qq python3.11 python3.11-venv python3-pip
        else
            run_quiet_step "Updating package index"    sudo apt-get update -qq
            run_quiet_step "Installing Python 3.11"   sudo apt-get install -y -qq python3.11 python3.11-venv python3-pip
        fi
    elif command -v dnf &>/dev/null; then
        if is_root; then run_quiet_step "Installing Python 3.11" dnf  install -y -q python3.11 python3-pip
        else              run_quiet_step "Installing Python 3.11" sudo dnf  install -y -q python3.11 python3-pip; fi
    elif command -v yum &>/dev/null; then
        if is_root; then run_quiet_step "Installing Python 3.11" yum  install -y -q python3.11 python3-pip
        else              run_quiet_step "Installing Python 3.11" sudo yum  install -y -q python3.11 python3-pip; fi
    elif command -v apk &>/dev/null; then
        if is_root; then run_quiet_step "Installing Python 3" apk  add --no-cache python3 py3-pip py3-virtualenv
        else              run_quiet_step "Installing Python 3" sudo apk add --no-cache python3 py3-pip py3-virtualenv; fi
    else
        ui_error "Could not detect a supported package manager (apt/dnf/yum/apk)"
        echo "Install Python 3.10+ manually: https://python.org"
        exit 1
    fi
}

check_python() {
    if find_python; then
        ui_success "Python found: $("$PYTHON_BIN" --version 2>&1) (${PYTHON_BIN})"
        return 0
    fi
    ui_info "Python ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR}+ not found — installing"
    return 1
}

install_python() {
    if [[ "$OS" == "macos" ]]; then install_python_macos; else install_python_linux; fi
    if ! find_python; then
        ui_error "Python ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR}+ installation failed or not on PATH"
        echo "Install manually from https://python.org and re-run the installer."
        exit 1
    fi
    ui_success "Python installed: $("$PYTHON_BIN" --version 2>&1)"
}

# ── git ───────────────────────────────────────────────────────────────────────
check_git() {
    command -v git &>/dev/null && { ui_success "Git found: $(git --version)"; return 0; }
    ui_info "Git not found — installing"
    return 1
}

install_git() {
    if [[ "$OS" == "macos" ]]; then
        local brew_bin; brew_bin="$(resolve_brew_bin || true)"
        [[ -z "$brew_bin" ]] && { ui_error "Homebrew required to install git on macOS"; exit 1; }
        run_quiet_step "Installing git" "$brew_bin" install git
    else
        require_sudo
        if   command -v apt-get &>/dev/null; then
            if is_root; then run_quiet_step "Installing git" apt-get install -y -qq git
            else              run_quiet_step "Installing git" sudo apt-get install -y -qq git; fi
        elif command -v dnf    &>/dev/null; then
            if is_root; then run_quiet_step "Installing git" dnf  install -y -q git
            else              run_quiet_step "Installing git" sudo dnf  install -y -q git; fi
        elif command -v yum    &>/dev/null; then
            if is_root; then run_quiet_step "Installing git" yum  install -y -q git
            else              run_quiet_step "Installing git" sudo yum  install -y -q git; fi
        elif command -v apk    &>/dev/null; then
            if is_root; then run_quiet_step "Installing git" apk  add --no-cache git
            else              run_quiet_step "Installing git" sudo apk add --no-cache git; fi
        else
            ui_error "Cannot install git automatically — install it manually and re-run."
            exit 1
        fi
    fi
    ui_success "git installed"
}

# ── PATH helpers ──────────────────────────────────────────────────────────────
ensure_user_local_bin_on_path() {
    local target="$HOME/.local/bin"
    mkdir -p "$target"
    export PATH="${target}:${PATH}"
    # shellcheck disable=SC2016
    local line='export PATH="$HOME/.local/bin:$PATH"'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] && ! grep -qF ".local/bin" "$rc" && echo "$line" >> "$rc" || true
    done
}

warn_path_missing() {
    local dir="$1"
    case ":${ORIGINAL_PATH}:" in *":${dir}:"*) return 0 ;; esac
    echo ""
    ui_warn "PATH does not include: ${dir}"
    echo "  Add to ~/.zshrc or ~/.bashrc and restart your terminal:"
    echo "    export PATH=\"${dir}:\$PATH\""
}

# ── git install ───────────────────────────────────────────────────────────────
install_eurekaclaw_from_git() {
    local repo_dir="$1"

    # ── clone or update ───────────────────────────────────────────────────────
    if [[ -d "${repo_dir}/.git" ]]; then
        ui_info "Existing checkout: ${repo_dir}"
        if [[ "$GIT_UPDATE" == "1" ]]; then
            if [[ -z "$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)" ]]; then
                run_quiet_step "Updating repository" git -C "$repo_dir" pull --rebase
                ui_success "Repository updated"
            else
                ui_warn "Local changes detected in ${repo_dir}; skipping git pull"
            fi
        fi
    else
        run_quiet_step "Cloning EurekaClaw" git clone "$EUREKACLAW_REPO_URL" "$repo_dir"
        ui_success "Repository cloned to ${repo_dir}"
    fi

    # ── virtual environment ───────────────────────────────────────────────────
    local venv_dir="${repo_dir}/.venv"
    if [[ ! -d "$venv_dir" ]]; then
        run_quiet_step "Creating virtual environment" "$PYTHON_BIN" -m venv "$venv_dir"
        ui_success "Virtual environment created: ${venv_dir}"
    else
        ui_info "Virtual environment already exists: ${venv_dir}"
    fi

    local pip_bin="${venv_dir}/bin/pip"
    run_quiet_step "Upgrading pip" "$pip_bin" install --quiet --upgrade pip

    # ── pip install ───────────────────────────────────────────────────────────
    local install_target="${repo_dir}"
    if [[ -n "$EXTRAS" ]]; then install_target="${repo_dir}[${EXTRAS}]"; fi

    ui_info "Installing EurekaClaw${EXTRAS:+ (extras: ${EXTRAS})}"
    run_quiet_step "Installing EurekaClaw" "$pip_bin" install --quiet "$install_target"
    ui_success "EurekaClaw installed into virtual environment"

    # ── shim ──────────────────────────────────────────────────────────────────
    ensure_user_local_bin_on_path

    local shim_path="$HOME/.local/bin/eurekaclaw"
    local eurekaclaw_bin="${venv_dir}/bin/eurekaclaw"

    cat > "$shim_path" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
exec "${eurekaclaw_bin}" "\$@"
SHIM
    chmod +x "$shim_path"
    ui_success "Shim installed: ${shim_path}"
}

# ── resolve installed binary ──────────────────────────────────────────────────
resolve_eurekaclaw_bin() {
    hash -r 2>/dev/null || true
    local resolved
    resolved="$(command -v eurekaclaw 2>/dev/null || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
        EUREKACLAW_BIN="$resolved"; return 0
    fi
    local local_bin="$HOME/.local/bin/eurekaclaw"
    if [[ -x "$local_bin" ]]; then
        EUREKACLAW_BIN="$local_bin"; return 0
    fi
    return 1
}

# ── post-install ──────────────────────────────────────────────────────────────
run_install_skills() {
    local claw="${EUREKACLAW_BIN:-}"
    if [[ -z "$claw" ]]; then claw="$(command -v eurekaclaw 2>/dev/null || true)"; fi
    if [[ -z "$claw" ]]; then
        ui_warn "eurekaclaw not on PATH — skipping seed skill installation"
        return 0
    fi
    run_quiet_step "Installing seed skills" "$claw" install-skills || true
    ui_success "Seed skills installed to ~/.eurekaclaw/skills/"
}

show_next_steps() {
    if [[ "$NO_ONBOARD" == "1" ]]; then return 0; fi

    ui_section "Next steps"
    echo "  1. Copy the example config and add your API key:"
    echo ""
    echo "       cp ${GIT_DIR}/.env.example ~/.eurekaclaw/.env"
    echo "       \$EDITOR ~/.eurekaclaw/.env"
    echo ""
    echo "  2. Run your first proof:"
    echo ""
    echo "       eurekaclaw prove \"Your conjecture here\""
    echo ""
    echo "  Docs: https://docs.eurekaclaw.ai"
    echo ""
}

# ── banner ────────────────────────────────────────────────────────────────────
print_banner() {
    if [[ -n "$GUM" ]]; then
        local title tagline
        title="$("$GUM"   style --foreground "#64b4ff" --bold    "🔬 EurekaClaw Installer")"
        tagline="$("$GUM" style --foreground "#8892b0"           "Multi-agent theoretical research system")"
        "$GUM" style --border rounded --border-foreground "#64b4ff" --padding "1 2" \
            "$(printf '%s\n%s' "$title" "$tagline")"
        echo ""
    else
        echo -e "${ACCENT}${BOLD}"
        echo "  🔬 EurekaClaw Installer"
        echo -e "${NC}${INFO}  Multi-agent theoretical research system${NC}"
        echo ""
    fi
}

show_install_plan() {
    ui_section "Install plan"
    ui_kv "OS"           "$OS"
    ui_kv "Method"       "$INSTALL_METHOD"
    ui_kv "Checkout dir" "$GIT_DIR"
    if [[ -n "$EXTRAS"         ]]; then ui_kv "pip extras"  "$EXTRAS";                    fi
    if [[ "$GIT_UPDATE" == "0" ]]; then ui_kv "git pull"    "skipped";                    fi
    if [[ "$DRY_RUN"    == "1" ]]; then ui_kv "Dry run"     "yes (no changes will be made)"; fi
    if [[ "$NO_ONBOARD" == "1" ]]; then ui_kv "Onboarding"  "skipped";                    fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    configure_verbose

    if [[ "$HELP" == "1" ]]; then print_usage; exit 0; fi


    # Validate install method — only git is supported now; others are stubbed.
    case "$INSTALL_METHOD" in
        git) ;;
        npm|pip)
            ui_error "--install-method '${INSTALL_METHOD}' is not yet available in this release."
            echo ""
            echo "  Only the git method is supported right now:"
            echo "    curl -fsSL https://eurekaclaw.ai/install.sh | bash"
            echo "    (--install-method git is the default)"
            echo ""
            echo "  npm and pip install methods are coming soon."
            exit 1
            ;;
        *)
            ui_error "Unknown --install-method: '${INSTALL_METHOD}'"
            echo "  Use: --install-method git"
            exit 2
            ;;
    esac

    bootstrap_gum_temp || true
    print_banner
    detect_os_or_die
    show_install_plan

    if [[ "$DRY_RUN" == "1" ]]; then echo ""; ui_success "Dry run complete — no changes made."; exit 0; fi

    # ── [1/3] Prepare environment ─────────────────────────────────────────────
    ui_stage "Preparing environment"

    install_homebrew
    check_python || install_python
    check_git    || install_git

    # ── [2/3] Install EurekaClaw ──────────────────────────────────────────────
    ui_stage "Installing EurekaClaw"

    mkdir -p "$(dirname "${GIT_DIR}")" 2>/dev/null || true
    install_eurekaclaw_from_git "$GIT_DIR"

    # ── [3/3] Finalize ────────────────────────────────────────────────────────
    ui_stage "Finalizing"

    resolve_eurekaclaw_bin || true
    warn_path_missing "$HOME/.local/bin"
    run_install_skills
    show_next_steps

    # Installed version (from package metadata)
    local version=""
    if [[ -n "$EUREKACLAW_BIN" ]]; then
        version="$("${GIT_DIR}/.venv/bin/pip" show eurekaclaw 2>/dev/null \
                    | grep "^Version:" | cut -d' ' -f2 || true)"
    fi

    echo ""
    if [[ -n "$version" ]]; then
        ui_celebrate "🔬 EurekaClaw ${version} installed successfully!"
    else
        ui_celebrate "🔬 EurekaClaw installed successfully!"
    fi

    ui_kv "Checkout"       "$GIT_DIR"
    ui_kv "Shim"           "$HOME/.local/bin/eurekaclaw"
    ui_kv "Update command" "cd ${GIT_DIR} && git pull && ${GIT_DIR}/.venv/bin/pip install ."
    echo ""
}

main "$@"
