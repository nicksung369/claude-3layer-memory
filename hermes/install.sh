#!/usr/bin/env bash
# hermes-3layer-memory installer
# Adds time-based medium-term / promotion-queue layers on top of Hermes
# Agent's existing agent-curated MEMORY.md + SQLite session store.
#
# Usage:
#   ./install.sh [--with-cron] [--hermes-home <path>] [--uninstall]
#
# Options:
#   --with-cron              Install cron jobs automatically
#   --hermes-home <path>     Override Hermes home (default: ~/.hermes)
#   --uninstall              Remove scripts and cron (preserves data)

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME_DEFAULT="${HOME}/.hermes"
HERMES_HOME="${HERMES_HOME_DEFAULT}"
WITH_CRON=false
UNINSTALL=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-cron)    WITH_CRON=true; shift ;;
        --hermes-home)  HERMES_HOME="$2"; shift 2 ;;
        --uninstall)    UNINSTALL=true; shift ;;
        *)              err "Unknown option: $1"; exit 1 ;;
    esac
done

SCRIPTS_DIR="${HERMES_HOME}/scripts/3layer"
MEMORIES_DIR="${HERMES_HOME}/memories"
DB="${HERMES_HOME}/state.db"
LOG_FILE="${HERMES_HOME}/3layer.log"

if [ "${UNINSTALL}" = true ]; then
    info "Uninstalling hermes-3layer-memory..."
    if crontab -l 2>/dev/null | grep -q 'hermes-3layer'; then
        crontab -l 2>/dev/null | grep -v 'hermes-3layer' | crontab -
        ok "Removed cron jobs"
    fi
    if [ -d "${SCRIPTS_DIR}" ]; then
        rm -rf "${SCRIPTS_DIR}"
        ok "Removed scripts at ${SCRIPTS_DIR}"
    fi
    warn "Preserved: ${MEMORIES_DIR}/medium-term.md and ${MEMORIES_DIR}/_promotions.md"
    warn "MEMORY.md / USER.md untouched (agent-curated; we never wrote to them)"
    ok "Uninstall complete"
    exit 0
fi

info "Installing hermes-3layer-memory into ${HERMES_HOME}"
echo ""

# 1. Preflight
if [ ! -d "${HERMES_HOME}" ]; then
    err "${HERMES_HOME} does not exist. Is Hermes Agent installed?"
    err "  See: https://github.com/NousResearch/hermes-agent"
    err "  Or pass --hermes-home <path> to override."
    exit 1
fi
if [ ! -f "${DB}" ]; then
    warn "${DB} not found — scripts will be installed but digest will fail"
    warn "until Hermes has recorded at least one session."
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
    err "sqlite3 CLI not found. Install it:"
    err "  Debian/Ubuntu:  apt-get install sqlite3"
    err "  macOS:          sqlite3 is preinstalled"
    err "  Alpine:         apk add sqlite"
    exit 1
fi

# 2. Install scripts
info "Installing scripts to ${SCRIPTS_DIR}..."
mkdir -p "${SCRIPTS_DIR}" "${MEMORIES_DIR}"
for s in digest-sessions.sh suggest-promotions.sh; do
    cp "${SELF_DIR}/scripts/${s}" "${SCRIPTS_DIR}/${s}"
    chmod +x "${SCRIPTS_DIR}/${s}"
done
ok "Scripts installed"

# 3. Seed templates only when missing — never overwrite agent-authored content
if [ ! -f "${MEMORIES_DIR}/medium-term.md" ]; then
    cp "${SELF_DIR}/templates/medium-term.md" "${MEMORIES_DIR}/medium-term.md"
    ok "Seeded medium-term.md"
fi

# 4. Cron
if [ "${WITH_CRON}" = true ]; then
    if ! command -v crontab >/dev/null 2>&1; then
        err "crontab not found. Install cron yourself, then re-run with --with-cron."
        exit 1
    fi
    info "Installing cron jobs..."
    CRON_PREFIX="HERMES_HOME=${HERMES_HOME}"
    DIGEST="0 3 * * 1,4 ${CRON_PREFIX} ${SCRIPTS_DIR}/digest-sessions.sh >> ${LOG_FILE} 2>&1"
    PROMOTE="0 4 1,15 * * ${CRON_PREFIX} ${SCRIPTS_DIR}/suggest-promotions.sh >> ${LOG_FILE} 2>&1"

    EXISTING=$(crontab -l 2>/dev/null | grep -v 'hermes-3layer' || true)
    {
        echo "${EXISTING}"
        echo "# hermes-3layer: digest SQLite sessions into medium-term.md"
        echo "${DIGEST}"
        echo "# hermes-3layer: append promotion candidates for MEMORY.md review"
        echo "${PROMOTE}"
    } | crontab -
    ok "Cron installed"
else
    echo ""
    warn "Cron NOT installed. Add these manually (crontab -e):"
    echo ""
    echo "  # Digest recent Hermes sessions into medium-term.md (Mon+Thu 3am)"
    echo "  0 3 * * 1,4 HERMES_HOME=${HERMES_HOME} ${SCRIPTS_DIR}/digest-sessions.sh >> ${LOG_FILE} 2>&1"
    echo ""
    echo "  # Append promotion candidates for MEMORY.md review (1st+15th 4am)"
    echo "  0 4 1,15 * * HERMES_HOME=${HERMES_HOME} ${SCRIPTS_DIR}/suggest-promotions.sh >> ${LOG_FILE} 2>&1"
    echo ""
    echo "  Or re-run: ./install.sh --with-cron"
fi

# 5. Summary
echo ""
echo "=========================================="
ok "Installation complete!"
echo "=========================================="
echo ""
echo "  Architecture:"
echo ""
echo "  ┌──────────────────────┐  every 48h  ┌─────────────────────┐"
echo "  │ state.db (SQLite)    │ ──────────> │ medium-term.md       │"
echo "  │  sessions + messages │  (digest)   │ (14-day rolling)     │"
echo "  │  + messages_fts      │             └──────────┬──────────┘"
echo "  └──────────────────────┘                        │ every 2 weeks"
echo "              ^                                   v"
echo "              │ (Hermes writes)          ┌─────────────────────┐"
echo "              │                          │ _promotions.md       │"
echo "              │                          │ (review queue)       │"
echo "              │                          └──────────┬──────────┘"
echo "              │                                     │ human/agent review"
echo "              │                                     v"
echo "              │                          ┌─────────────────────┐"
echo "              └──────────────────────────┤ MEMORY.md (≤2200c)  │"
echo "                                         │ + USER.md (≤1375c)  │"
echo "                                         │ (agent-curated — we │"
echo "                                         │  never write here)  │"
echo "                                         └─────────────────────┘"
echo ""
echo "  Hermes home: ${HERMES_HOME}"
echo "  Scripts:     ${SCRIPTS_DIR}"
echo "  Logs:        ${LOG_FILE}"
echo ""
echo "  Run once now to verify:"
echo "    HERMES_HOME=${HERMES_HOME} ${SCRIPTS_DIR}/digest-sessions.sh"
echo ""
echo "  Optional web viewer (from repo root):"
echo "    python3 ../viewer/server.py --dir ${MEMORIES_DIR}"
echo ""
