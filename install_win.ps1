# EurekaClaw Windows Installer (PowerShell)
# ──────────────────────────────────────────────────────────────────────────────
# Usage:
#   powershell -ExecutionPolicy Bypass -File install_win.ps1
#   powershell -ExecutionPolicy Bypass -File install_win.ps1 -GitDir C:\eurekaclaw
#
# Or one-liner (once hosted):
#   powershell -c "irm https://eurekaclaw.ai/install.ps1 | iex"

param(
    [string]$GitDir   = "$env:USERPROFILE\eurekaclaw",
    [string]$Extras   = "all",
    [switch]$NoOnboard,
    [switch]$NoGitUpdate,
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── colours ───────────────────────────────────────────────────────────────────
function Write-Info    { param($msg) Write-Host "· $msg" -ForegroundColor DarkGray }
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Cyan }
function Write-Warn    { param($msg) Write-Host "! $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "✗ $msg" -ForegroundColor Red }
function Write-Section { param($msg) Write-Host "`n● $msg" -ForegroundColor Blue }

# ── help ──────────────────────────────────────────────────────────────────────
if ($Help) {
    Write-Host @"
EurekaClaw Windows Installer

Usage:
  powershell -ExecutionPolicy Bypass -File install_win.ps1 [options]

Options:
  -GitDir <path>    Checkout directory (default: ~\eurekaclaw)
  -Extras <groups>  pip extras to install, e.g. "all" (default)
  -NoOnboard        Skip post-install setup prompt
  -NoGitUpdate      Skip git pull for an existing checkout
  -DryRun           Print what would happen; make no changes
  -Verbose          Print full output from each step
  -Help             Show this help
"@
    exit 0
}

# ── banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  EurekaClaw Installer" -ForegroundColor Blue -NoNewline
Write-Host "  (Windows)" -ForegroundColor DarkGray
Write-Host "  Multi-agent theoretical research system" -ForegroundColor DarkGray
Write-Host ""

# ── dry-run helper ────────────────────────────────────────────────────────────
function Invoke-Step {
    param([string]$Title, [scriptblock]$Action)
    if ($DryRun) {
        Write-Info "[dry-run] $Title"
        return
    }
    if ($Verbose) { Write-Info $Title }
    try {
        & $Action
    } catch {
        Write-Err "$Title failed: $_"
        exit 1
    }
}

# ── show plan ─────────────────────────────────────────────────────────────────
Write-Section "Install plan"
Write-Host "  OS          : Windows"
Write-Host "  Method      : git"
Write-Host "  Checkout dir: $GitDir"
if ($Extras)     { Write-Host "  pip extras  : $Extras" }
if ($NoGitUpdate){ Write-Host "  git pull    : skipped" }
if ($DryRun)     { Write-Host "  Dry run     : yes (no changes will be made)" }
if ($NoOnboard)  { Write-Host "  Onboarding  : skipped" }

if ($DryRun) {
    Write-Host ""
    Write-Success "Dry run complete — no changes made."
    exit 0
}

# ── [1/3] Prepare environment ─────────────────────────────────────────────────
Write-Section "[1/3] Preparing environment"

# ── Python ────────────────────────────────────────────────────────────────────
$MIN_MAJOR = 3; $MIN_MINOR = 11
$PythonBin = $null

function Test-PythonVersion {
    param([string]$Bin)
    try {
        $ver = & $Bin -c "import sys; print(sys.version_info.major, sys.version_info.minor)" 2>$null
        if ($ver -match "^(\d+) (\d+)$") {
            $major = [int]$Matches[1]; $minor = [int]$Matches[2]
            return ($major -gt $MIN_MAJOR) -or ($major -eq $MIN_MAJOR -and $minor -ge $MIN_MINOR)
        }
    } catch {}
    return $false
}

$candidates = @("python", "python3", "python3.13", "python3.12", "python3.11")
foreach ($c in $candidates) {
    $resolved = Get-Command $c -ErrorAction SilentlyContinue
    if ($resolved -and (Test-PythonVersion $resolved.Source)) {
        $PythonBin = $resolved.Source
        break
    }
}

if ($PythonBin) {
    $pyver = & $PythonBin --version 2>&1
    Write-Success "Python found: $pyver ($PythonBin)"
} else {
    Write-Warn "Python $MIN_MAJOR.$MIN_MINOR+ not found."
    Write-Host ""
    Write-Host "  Install Python from https://python.org (check 'Add to PATH' during install),"
    Write-Host "  then re-run this script."
    Write-Host ""
    Write-Host "  Or with winget:"
    Write-Host "    winget install Python.Python.3.11"
    exit 1
}

# ── Git ───────────────────────────────────────────────────────────────────────
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitVer = & git --version
    Write-Success "Git found: $gitVer"
} else {
    Write-Warn "Git not found."
    Write-Host ""
    Write-Host "  Install Git from https://git-scm.com, then re-run this script."
    Write-Host "  Or with winget:"
    Write-Host "    winget install Git.Git"
    exit 1
}

# ── [2/3] Install EurekaClaw ──────────────────────────────────────────────────
Write-Section "[2/3] Installing EurekaClaw"

$RepoUrl = if ($env:EUREKACLAW_REPO_URL) { $env:EUREKACLAW_REPO_URL } `
           else { "https://github.com/EurekaClaw/EurekaClaw_dev_zero.git" }

# Clone or update
if (Test-Path (Join-Path $GitDir ".git")) {
    Write-Info "Existing checkout: $GitDir"
    if (-not $NoGitUpdate) {
        $status = & git -C $GitDir status --porcelain 2>$null
        if (-not $status) {
            Invoke-Step "Updating repository" {
                & git -C $GitDir pull --rebase
                if ($LASTEXITCODE -ne 0) { throw "git pull failed" }
            }
            Write-Success "Repository updated"
        } else {
            Write-Warn "Local changes detected in $GitDir — skipping git pull"
        }
    }
} else {
    $parentDir = Split-Path $GitDir -Parent
    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
    Invoke-Step "Cloning EurekaClaw" {
        & git clone $RepoUrl $GitDir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
    }
    Write-Success "Repository cloned to $GitDir"
}

# Virtual environment
$VenvDir  = Join-Path $GitDir ".venv"
$PipBin   = Join-Path $VenvDir "Scripts\pip.exe"
$ClawBin  = Join-Path $VenvDir "Scripts\eurekaclaw.exe"

if (-not (Test-Path $VenvDir)) {
    Invoke-Step "Creating virtual environment" {
        & $PythonBin -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) { throw "venv creation failed" }
    }
    Write-Success "Virtual environment created: $VenvDir"
} else {
    Write-Info "Virtual environment already exists: $VenvDir"
}

Invoke-Step "Upgrading pip" {
    & $PipBin install --quiet --upgrade pip
}

# pip install
$InstallTarget = if ($Extras) { "${GitDir}[$Extras]" } else { $GitDir }
Write-Info "Installing EurekaClaw$(if ($Extras) { " (extras: $Extras)" })"
Invoke-Step "Installing EurekaClaw" {
    & $PipBin install --quiet $InstallTarget
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
}
Write-Success "EurekaClaw installed into virtual environment"

# ── [3/3] Finalize ────────────────────────────────────────────────────────────
Write-Section "[3/3] Finalizing"

# Add venv Scripts to user PATH permanently
$ScriptsDir = Join-Path $VenvDir "Scripts"
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$ScriptsDir*") {
    Invoke-Step "Adding $ScriptsDir to user PATH" {
        [Environment]::SetEnvironmentVariable("PATH", "$ScriptsDir;$userPath", "User")
    }
    Write-Success "Added to PATH: $ScriptsDir"
    Write-Warn "Restart your terminal for the PATH change to take effect."
} else {
    Write-Info "Already on PATH: $ScriptsDir"
}

# Install seed skills
if (Test-Path $ClawBin) {
    Invoke-Step "Installing seed skills" {
        & $ClawBin install-skills 2>$null
    }
    Write-Success "Seed skills installed to ~/.eurekaclaw/skills/"
} else {
    Write-Warn "eurekaclaw binary not found at $ClawBin — skipping seed skills"
}

# Next steps
if (-not $NoOnboard) {
    Write-Section "Next steps"
    Write-Host ""
    Write-Host "  1. Copy the example config and add your API key:"
    Write-Host ""
    Write-Host "       copy $GitDir\.env.example $GitDir\.env"
    Write-Host "       notepad $GitDir\.env"
    Write-Host ""
    Write-Host "     Or run the interactive wizard:"
    Write-Host ""
    Write-Host "       eurekaclaw onboard"
    Write-Host ""
    Write-Host "  2. Run your first proof:"
    Write-Host ""
    Write-Host "       eurekaclaw prove ""Your conjecture here"""
    Write-Host ""
    Write-Host "  Docs: https://docs.eurekaclaw.ai"
    Write-Host ""
}

# Version
$version = ""
try {
    $version = (& $PipBin show eurekaclaw 2>$null | Select-String "^Version:").ToString().Split(" ")[1]
} catch {}

Write-Host ""
if ($version) {
    Write-Success "EurekaClaw $version installed successfully!"
} else {
    Write-Success "EurekaClaw installed successfully!"
}
Write-Host "  Checkout      : $GitDir" -ForegroundColor DarkGray
Write-Host "  Binary        : $ClawBin" -ForegroundColor DarkGray
Write-Host "  Update command: cd $GitDir; git pull; $PipBin install ." -ForegroundColor DarkGray
Write-Host ""
