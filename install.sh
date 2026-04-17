#!/usr/bin/env bash
# claude-3layer-memory installer
# Sets up three-layer memory (short/medium/long-term) for Claude Code
#
# Usage: ./install.sh [--with-cron] [--with-viewer] [--with-all] [--status] [--uninstall]
#
# Options:
#   --with-cron    Install cron jobs automatically
#   --with-viewer  Install the localhost:37777 web viewer (systemd/launchd)
#   --with-all     Shortcut: --with-cron + --with-viewer
#   --status       Print health check (cron / viewer / memory files) and exit
#   --uninstall    Remove all memory components

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
MEMORY_DIR="${CLAUDE_DIR}/memory/global"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts/memory"
ARCHIVE_DIR="${MEMORY_DIR}/archive"
VIEWER_DIR="${CLAUDE_DIR}/scripts/memory-viewer"
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
WITH_VIEWER=false
UNINSTALL=false
STATUS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-cron)    WITH_CRON=true; shift ;;
    --with-viewer)  WITH_VIEWER=true; shift ;;
    --with-all)     WITH_CRON=true; WITH_VIEWER=true; shift ;;
    --status)       STATUS=true; shift ;;
    --uninstall)    UNINSTALL=true; shift ;;
    *)              err "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Status / doctor ---
if [ "$STATUS" = true ]; then
  info "claude-3layer-memory — status check"
  echo ""

  # 1. Scripts
  if [ -f "${SCRIPTS_DIR}/aggregate-short-term.sh" ]; then
    ok "scripts:  installed at ${SCRIPTS_DIR}"
  else
    warn "scripts:  NOT installed — run ./install.sh"
  fi

  # 2. Memory tier files + freshness
  for tier in short-term medium-term long-term; do
    f="${MEMORY_DIR}/${tier}.md"
    if [ -f "$f" ]; then
      bytes=$(wc -c < "$f" | tr -d ' ')
      mtime=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1)
      ok "${tier}.md:  ${bytes}B  (last modified ${mtime})"
    else
      warn "${tier}.md:  missing"
    fi
  done

  # 3. Cron
  if crontab -l 2>/dev/null | grep -q 'claude.*memory'; then
    n=$(crontab -l 2>/dev/null | grep -c 'claude.*memory' || true)
    ok "cron:     ${n} entries active"
  else
    warn "cron:     no entries — run ./install.sh --with-cron"
  fi

  # 4. Viewer
  if [ -f "${VIEWER_DIR}/server.py" ]; then
    if curl -fsS -o /dev/null --max-time 1 http://127.0.0.1:37777/ 2>/dev/null; then
      ok "viewer:   installed AND responding on http://127.0.0.1:37777"
    else
      warn "viewer:   installed but not responding on 37777 (start autostart unit or run manually)"
    fi
  else
    warn "viewer:   NOT installed — run ./install.sh --with-viewer"
  fi

  # 5. SessionStart hook (best-effort detection in common settings files)
  hook_found=false
  for f in "${HOME}/.claude/settings.json" "${HOME}/.claude/settings.local.json"; do
    if [ -f "$f" ] && grep -q 'SessionStart' "$f" 2>/dev/null; then
      hook_found=true
      ok "hook:     SessionStart declared in $f"
      break
    fi
  done
  [ "$hook_found" = false ] && warn "hook:     SessionStart not detected in ~/.claude/settings*.json (see README)"

  echo ""
  exit 0
fi

# --- Uninstall ---
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling claude-3layer-memory..."

  # Remove cron entries
  if crontab -l 2>/dev/null | grep -q 'claude.*memory'; then
    crontab -l 2>/dev/null | grep -v 'claude.*memory' | crontab -
    ok "Removed cron jobs"
  fi

  # Remove viewer autostart units (platform-specific)
  UNAME="$(uname)"
  if [ "$UNAME" = "Darwin" ]; then
    PLIST_DST="${HOME}/Library/LaunchAgents/com.claude-3layer-memory.viewer.plist"
    if [ -f "${PLIST_DST}" ]; then
      launchctl unload "${PLIST_DST}" 2>/dev/null || true
      rm -f "${PLIST_DST}"
      ok "Removed launchd agent ${PLIST_DST}"
    fi
  elif [ "$UNAME" = "Linux" ]; then
    UNIT_DST="${HOME}/.config/systemd/user/claude-memory-viewer.service"
    if [ -f "${UNIT_DST}" ]; then
      systemctl --user disable --now claude-memory-viewer.service 2>/dev/null || true
      rm -f "${UNIT_DST}"
      systemctl --user daemon-reload 2>/dev/null || true
      ok "Removed systemd unit ${UNIT_DST}"
    fi
  fi

  # Remove viewer
  if [ -d "${VIEWER_DIR}" ]; then
    rm -rf "${VIEWER_DIR}"
    ok "Removed viewer at ${VIEWER_DIR}"
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

# 4b. Install viewer (optional)
if [ "$WITH_VIEWER" = true ]; then
  info "Installing memory viewer..."
  mkdir -p "${VIEWER_DIR}"
  cp "${SELF_DIR}/viewer/server.py" "${VIEWER_DIR}/server.py"
  chmod +x "${VIEWER_DIR}/server.py"
  ok "Viewer installed to ${VIEWER_DIR}"

  # Platform-specific autostart
  UNAME="$(uname)"
  if [ "$UNAME" = "Darwin" ]; then
    PLIST_SRC="${SELF_DIR}/viewer/launchd/com.claude-3layer-memory.viewer.plist"
    PLIST_DST="${HOME}/Library/LaunchAgents/com.claude-3layer-memory.viewer.plist"
    mkdir -p "${HOME}/Library/LaunchAgents"
    sed "s|__HOME__|${HOME}|g" "${PLIST_SRC}" > "${PLIST_DST}"
    ok "launchd agent written to ${PLIST_DST}"
    echo ""
    echo "  Load it now:"
    echo "    launchctl load  ${PLIST_DST}"
    echo "  Unload:"
    echo "    launchctl unload ${PLIST_DST}"
  elif [ "$UNAME" = "Linux" ]; then
    UNIT_SRC="${SELF_DIR}/viewer/systemd/claude-memory-viewer.service"
    UNIT_DIR="${HOME}/.config/systemd/user"
    UNIT_DST="${UNIT_DIR}/claude-memory-viewer.service"
    mkdir -p "${UNIT_DIR}"
    cp "${UNIT_SRC}" "${UNIT_DST}"
    ok "systemd --user unit written to ${UNIT_DST}"
    echo ""
    echo "  Enable and start:"
    echo "    systemctl --user daemon-reload"
    echo "    systemctl --user enable --now claude-memory-viewer.service"
    echo "  Status / logs:"
    echo "    systemctl --user status claude-memory-viewer"
    echo "    journalctl --user -u claude-memory-viewer -f"
  else
    warn "Unknown platform ${UNAME}; no autostart installed."
    echo "  Run manually: python3 ${VIEWER_DIR}/server.py"
  fi

  echo ""
  echo "  Open:    http://127.0.0.1:37777"
  echo ""
  echo "  Optional — expose the 'Run' controls in the UI (aggregate / promote):"
  echo "    python3 ${VIEWER_DIR}/server.py --enable-controls"
  echo "    (loopback-only; off by default for safety)"
else
  echo ""
  info "Skipping viewer. Install later with: ./install.sh --with-viewer"
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
