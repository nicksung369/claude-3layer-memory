#!/usr/bin/env bash
# claude-3layer-memory installer
# Sets up three-layer memory (short/medium/long-term) for Claude Code
#
# Usage: ./install.sh [--with-cron] [--uninstall]
#
# Options:
#   --with-cron    Install cron jobs automatically
#   --uninstall    Remove all memory components

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
MEMORY_DIR="${CLAUDE_DIR}/memory/global"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts/memory"
ARCHIVE_DIR="${MEMORY_DIR}/archive"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

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
WITH_CRON=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-cron)  WITH_CRON=true; shift ;;
    --uninstall)  UNINSTALL=true; shift ;;
    *)            err "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Uninstall ---
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling claude-3layer-memory..."

  # Remove cron entries
  if crontab -l 2>/dev/null | grep -q 'claude.*memory'; then
    crontab -l 2>/dev/null | grep -v 'claude.*memory' | crontab -
    ok "Removed cron jobs"
  fi

  # Remove scripts (but not memory data)
  if [ -d "${SCRIPTS_DIR}" ]; then
    rm -rf "${SCRIPTS_DIR}"
    ok "Removed memory scripts from ${SCRIPTS_DIR}"
  fi

  warn "Memory data preserved at ${MEMORY_DIR}"
  warn "To delete memory data: rm -rf ${MEMORY_DIR}"
  warn "Hook patches in session-start.js must be removed manually"
  ok "Uninstall complete"
  exit 0
fi

# --- Install ---
info "Installing claude-3layer-memory..."
echo ""

# 1. Create directories
info "Creating directories..."
mkdir -p "${MEMORY_DIR}" "${ARCHIVE_DIR}" "${SCRIPTS_DIR}"
ok "Directories created"

# 2. Copy memory scripts
info "Installing memory scripts..."
for script in aggregate-short-term.sh promote-to-medium.sh promote-to-long.sh; do
  cp "${SELF_DIR}/scripts/${script}" "${SCRIPTS_DIR}/${script}"
  chmod +x "${SCRIPTS_DIR}/${script}"
done
ok "Memory scripts installed to ${SCRIPTS_DIR}"

# 3. Create template files (only if not already present)
for tier in short-term medium-term long-term; do
  target="${MEMORY_DIR}/${tier}.md"
  if [ ! -f "${target}" ] || grep -q "No entries yet" "${target}" 2>/dev/null; then
    cp "${SELF_DIR}/templates/${tier}.md" "${target}"
    ok "Created ${tier}.md"
  else
    ok "${tier}.md already has content, skipping"
  fi
done

# 4. Install cron jobs
if [ "$WITH_CRON" = true ]; then
  info "Installing cron jobs..."

  CRON_AGGREGATE="0 */6 * * * ${SCRIPTS_DIR}/aggregate-short-term.sh >> ${MEMORY_DIR}/cron.log 2>&1"
  CRON_MEDIUM="0 3 * * 1,4 ${SCRIPTS_DIR}/promote-to-medium.sh >> ${MEMORY_DIR}/cron.log 2>&1"
  CRON_LONG="0 4 1,15 * * ${SCRIPTS_DIR}/promote-to-long.sh >> ${MEMORY_DIR}/cron.log 2>&1"

  # Add cron entries (avoid duplicates)
  EXISTING_CRON=$(crontab -l 2>/dev/null || true)

  {
    echo "${EXISTING_CRON}" | grep -v 'claude.*memory' || true
    echo "# claude-3layer-memory: aggregate short-term every 6h"
    echo "${CRON_AGGREGATE}"
    echo "# claude-3layer-memory: promote to medium every 48h (Mon+Thu 3am)"
    echo "${CRON_MEDIUM}"
    echo "# claude-3layer-memory: promote to long-term every 2 weeks (1st+15th 4am)"
    echo "${CRON_LONG}"
  } | crontab -

  ok "Cron jobs installed"
else
  echo ""
  warn "Cron jobs NOT installed. To install manually, add these to crontab -e:"
  echo ""
  echo "  # Aggregate sessions into short-term memory (every 6 hours)"
  echo "  0 */6 * * * ${SCRIPTS_DIR}/aggregate-short-term.sh >> ${MEMORY_DIR}/cron.log 2>&1"
  echo ""
  echo "  # Promote short-term to medium-term (Mon+Thu 3am)"
  echo "  0 3 * * 1,4 ${SCRIPTS_DIR}/promote-to-medium.sh >> ${MEMORY_DIR}/cron.log 2>&1"
  echo ""
  echo "  # Promote medium-term to long-term (1st+15th 4am)"
  echo "  0 4 1,15 * * ${SCRIPTS_DIR}/promote-to-long.sh >> ${MEMORY_DIR}/cron.log 2>&1"
  echo ""
  echo "  Or re-run: ./install.sh --with-cron"
fi

# 5. Hook patch instructions
echo ""
info "SESSION HOOK SETUP"
echo ""
echo "  To load memory on session start, add this to your"
echo "  session-start hook (e.g. ~/.claude/scripts/hooks/session-start.js):"
echo ""
echo "  See hooks/session-start-patch.js for the code snippet."
echo ""
echo "  If you're using ECC (Everything Claude Code), this is already"
echo "  integrated. Otherwise, copy the patch into your existing hook."

# 6. Summary
echo ""
echo "=========================================="
ok "Installation complete!"
echo "=========================================="
echo ""
echo "  Architecture:"
echo "  ┌──────────────┐  every 6h   ┌──────────────┐"
echo "  │ Session Data  │ ──────────> │  Short-Term   │"
echo "  │ (*.tmp files) │             │  (48h rolling)│"
echo "  └──────────────┘             └──────┬───────┘"
echo "                                      │ every 48h"
echo "                                      v"
echo "                               ┌──────────────┐"
echo "                               │ Medium-Term   │"
echo "                               │ (2-week digest)│"
echo "                               └──────┬───────┘"
echo "                                      │ every 2 weeks"
echo "                                      v"
echo "                               ┌──────────────┐"
echo "                               │  Long-Term    │"
echo "                               │ (permanent)   │"
echo "                               └──────────────┘"
echo ""
echo "  Scripts: ${SCRIPTS_DIR}/"
echo "  Data:    ${MEMORY_DIR}/"
echo "  Logs:    ${MEMORY_DIR}/cron.log"
echo ""
