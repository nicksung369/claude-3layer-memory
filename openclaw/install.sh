#!/usr/bin/env bash
# openclaw-3layer-memory installer
# Sets up three-layer memory automation for OpenClaw agents
#
# Usage:
#   Inside container:   ./install.sh [--with-cron]
#   From host (Docker): ./install.sh --docker <container_name> [--with-cron]
#   Uninstall:          ./install.sh --uninstall [--docker <container_name>]
#
# Options:
#   --with-cron              Install cron jobs automatically
#   --docker <container>     Run inside a Docker container via docker exec
#   --workspace <path>       Override workspace path (default: /root/.openclaw/workspace)
#   --uninstall              Remove memory scripts (preserves data)

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
WITH_CRON=false
UNINSTALL=false
DOCKER_CONTAINER=""
WORKSPACE=""
INSTALL_DIR="/opt/openclaw-memory"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-cron)   WITH_CRON=true; shift ;;
        --uninstall)   UNINSTALL=true; shift ;;
        --docker)      DOCKER_CONTAINER="$2"; shift 2 ;;
        --workspace)   WORKSPACE="$2"; shift 2 ;;
        *)             err "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Helper: run command locally or in Docker ---
run_cmd() {
    if [ -n "${DOCKER_CONTAINER}" ]; then
        docker exec "${DOCKER_CONTAINER}" bash -c "$1"
    else
        bash -c "$1"
    fi
}

# --- Helper: copy file into target (local or Docker) ---
copy_file() {
    local src="$1" dest="$2"
    if [ -n "${DOCKER_CONTAINER}" ]; then
        docker cp "$src" "${DOCKER_CONTAINER}:${dest}"
    else
        cp "$src" "$dest"
    fi
}

# --- Auto-detect workspace ---
detect_workspace() {
    if [ -n "${WORKSPACE}" ]; then
        return
    fi

    # Try common OpenClaw workspace locations
    for candidate in \
        "/root/.openclaw/workspace" \
        "${HOME}/.openclaw/workspace" \
        "/opt/openclaw/data/workspace"; do
        if run_cmd "[ -d '${candidate}' ]" 2>/dev/null; then
            WORKSPACE="${candidate}"
            ok "Detected workspace: ${WORKSPACE}"
            return
        fi
    done

    # Check if openclaw is installed at all
    if run_cmd "command -v openclaw" >/dev/null 2>&1; then
        WORKSPACE="/root/.openclaw/workspace"
        warn "Workspace not found, using default: ${WORKSPACE}"
    else
        err "OpenClaw not detected. Is it installed?"
        err "Try: --workspace <path> to specify manually"
        exit 1
    fi
}

# --- Uninstall ---
if [ "$UNINSTALL" = true ]; then
    info "Uninstalling openclaw-3layer-memory..."

    # Remove cron entries
    if run_cmd "crontab -l 2>/dev/null | grep -q 'openclaw-memory'" 2>/dev/null; then
        run_cmd "crontab -l 2>/dev/null | grep -v 'openclaw-memory' | crontab -"
        ok "Removed cron jobs"
    fi

    # Remove scripts
    if run_cmd "[ -d '${INSTALL_DIR}' ]" 2>/dev/null; then
        run_cmd "rm -rf '${INSTALL_DIR}'"
        ok "Removed scripts from ${INSTALL_DIR}"
    fi

    warn "Memory data preserved in workspace"
    warn "To delete: rm -f <workspace>/memory/medium-term.md"
    ok "Uninstall complete"
    exit 0
fi

# --- Install ---
echo ""
info "Installing openclaw-3layer-memory..."
echo ""

# 1. Detect workspace
detect_workspace

MEMORY_DIR="${WORKSPACE}/memory"
ARCHIVE_DIR="${MEMORY_DIR}/archive"

# 2. Create directories
info "Creating directories..."
run_cmd "mkdir -p '${INSTALL_DIR}/scripts' '${MEMORY_DIR}' '${ARCHIVE_DIR}'"
ok "Directories created"

# 3. Copy scripts
info "Installing memory scripts..."
for script in aggregate-short-term.sh promote-to-medium.sh promote-to-long.sh; do
    copy_file "${SELF_DIR}/scripts/${script}" "${INSTALL_DIR}/scripts/${script}"
    run_cmd "chmod +x '${INSTALL_DIR}/scripts/${script}'"
done
ok "Scripts installed to ${INSTALL_DIR}/scripts/"

# 4. Create medium-term template if not present
if run_cmd "[ ! -f '${MEMORY_DIR}/medium-term.md' ]" 2>/dev/null; then
    copy_file "${SELF_DIR}/templates/medium-term.md" "${MEMORY_DIR}/medium-term.md"
    ok "Created medium-term.md template"
else
    ok "medium-term.md already exists, skipping"
fi

# 5. Install cron jobs
SCRIPT_PREFIX="OPENCLAW_WORKSPACE=${WORKSPACE} ${INSTALL_DIR}/scripts"
LOG_FILE="${MEMORY_DIR}/cron.log"

if [ "$WITH_CRON" = true ]; then
    info "Installing cron jobs..."

    # Ensure cron is available (do NOT silently apt-get — user/container decides)
    if ! run_cmd "command -v crontab" >/dev/null 2>&1; then
        err "crontab not found in target environment."
        err "Install cron yourself, then re-run with --with-cron:"
        err "  Debian/Ubuntu:  apt-get install cron"
        err "  Alpine:         apk add dcron"
        err "  macOS:          cron is preinstalled"
        exit 1
    fi

    CRON_AGGREGATE="0 */6 * * * ${SCRIPT_PREFIX}/aggregate-short-term.sh >> ${LOG_FILE} 2>&1"
    CRON_MEDIUM="0 3 * * 1,4 ${SCRIPT_PREFIX}/promote-to-medium.sh >> ${LOG_FILE} 2>&1"
    CRON_LONG="0 4 1,15 * * ${SCRIPT_PREFIX}/promote-to-long.sh >> ${LOG_FILE} 2>&1"

    CRON_INSTALL_CMD="
        EXISTING=\$(crontab -l 2>/dev/null | grep -v 'openclaw-memory' || true)
        {
            echo \"\${EXISTING}\"
            echo '# openclaw-memory: cleanup old daily memories every 6h'
            echo '${CRON_AGGREGATE}'
            echo '# openclaw-memory: promote to medium-term (Mon+Thu 3am)'
            echo '${CRON_MEDIUM}'
            echo '# openclaw-memory: promote to long-term (1st+15th 4am)'
            echo '${CRON_LONG}'
        } | crontab -
    "

    run_cmd "${CRON_INSTALL_CMD}"

    # Start cron daemon if in Docker
    if [ -n "${DOCKER_CONTAINER}" ]; then
        run_cmd "service cron start 2>/dev/null || cron 2>/dev/null || true"
    fi

    ok "Cron jobs installed"
else
    echo ""
    warn "Cron jobs NOT installed. To add manually (crontab -e):"
    echo ""
    echo "  # Cleanup old daily memories every 6h"
    echo "  0 */6 * * * ${SCRIPT_PREFIX}/aggregate-short-term.sh >> ${LOG_FILE} 2>&1"
    echo ""
    echo "  # Promote to medium-term (Mon+Thu 3am)"
    echo "  0 3 * * 1,4 ${SCRIPT_PREFIX}/promote-to-medium.sh >> ${LOG_FILE} 2>&1"
    echo ""
    echo "  # Promote to long-term (1st+15th 4am)"
    echo "  0 4 1,15 * * ${SCRIPT_PREFIX}/promote-to-long.sh >> ${LOG_FILE} 2>&1"
    echo ""
    echo "  Or re-run: ./install.sh --with-cron"
fi

# 6. Summary
echo ""
echo "=========================================="
ok "Installation complete!"
echo "=========================================="
echo ""
echo "  How it works with OpenClaw:"
echo ""
echo "  Your agent already writes memory/YYYY-MM-DD.md daily."
echo "  This skill adds automated aggregation on top:"
echo ""
echo "  ┌──────────────┐  every 6h   ┌──────────────┐"
echo "  │ memory/       │ ──────────> │  Cleanup old  │"
echo "  │ YYYY-MM-DD.md │  (prune)    │  (>48h files) │"
echo "  └──────────────┘             └──────┬───────┘"
echo "                                      │ every 48h"
echo "                                      v"
echo "  ┌──────────────┐             ┌──────────────┐"
echo "  │ Agent auto-   │ <────────  │ medium-term.md│"
echo "  │ reads on start│             │ (2-week digest)│"
echo "  └──────────────┘             └──────┬───────┘"
echo "                                      │ every 2 weeks"
echo "                                      v"
echo "                               ┌──────────────┐"
echo "                               │  MEMORY.md    │"
echo "                               │  (permanent)  │"
echo "                               └──────────────┘"
echo ""
echo "  Workspace: ${WORKSPACE}"
echo "  Scripts:   ${INSTALL_DIR}/scripts/"
echo "  Logs:      ${LOG_FILE}"
echo ""

if [ -n "${DOCKER_CONTAINER}" ]; then
    echo "  NOTE: Cron inside Docker requires the cron daemon to be running."
    echo "  Add to your Dockerfile or entrypoint:"
    echo "    service cron start"
    echo ""
fi
