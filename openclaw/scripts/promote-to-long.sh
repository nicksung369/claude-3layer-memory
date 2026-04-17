#!/usr/bin/env bash
# promote-to-long.sh (OpenClaw edition)
# Cron: every 2 weeks (1st+15th of month, 4am)
# Extracts permanent knowledge from medium-term.md -> MEMORY.md
# Then archives and resets medium-term.md for a fresh cycle
# Pure text extraction — no AI dependency
#
# Usage:
#   Inside container:  /opt/openclaw-memory/scripts/promote-to-long.sh
#   From host:         docker exec <container> /opt/openclaw-memory/scripts/promote-to-long.sh
#
# Environment:
#   OPENCLAW_WORKSPACE  Override workspace path (default: /root/.openclaw/workspace)

set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-/root/.openclaw/workspace}"
MEMORY_DIR="${WORKSPACE}/memory"
MEDIUM_TERM_FILE="${MEMORY_DIR}/medium-term.md"
LONG_TERM_FILE="${WORKSPACE}/MEMORY.md"
ARCHIVE_DIR="${MEMORY_DIR}/archive"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
DATE_TAG=$(date '+%Y-%m-%d')

mkdir -p "${MEMORY_DIR}" "${ARCHIVE_DIR}"

# Check if medium-term has actual content
if [ ! -f "${MEDIUM_TERM_FILE}" ]; then
    echo "[Memory] No medium-term.md found, skipping promotion"
    exit 0
fi

MEDIUM_CONTENT=$(cat "${MEDIUM_TERM_FILE}")
if echo "${MEDIUM_CONTENT}" | grep -q "No entries yet\|Fresh cycle"; then
    echo "[Memory] Medium-term memory is empty, skipping promotion"
    exit 0
fi

CONTENT_LINES=$(echo "${MEDIUM_CONTENT}" | grep -v '^#\|^>\|^$\|^\*\|^---' | wc -l)
if [ "${CONTENT_LINES}" -lt 5 ]; then
    echo "[Memory] Medium-term content too sparse (${CONTENT_LINES} lines), skipping"
    exit 0
fi

# --- Extract key content via keyword matching ---

SUMMARY="## Promoted ${DATE_TAG}

### Decisions & Key Items
"

# Extract lines that look like decisions or important items
ITEMS=$(grep -iE '^- .*(decision|config|setup|install|deploy|architecture|server|VPS|API|key|credential|preference|pattern|migration|database|docker|container|service|hook|cron|memory|auth|fix|resolved|created|launched|upgrade)' "${MEDIUM_TERM_FILE}" 2>/dev/null | sort -u | head -20 || true)
if [ -n "${ITEMS}" ]; then
    SUMMARY="${SUMMARY}${ITEMS}"
else
    # Fallback: grab all bullet points
    ITEMS=$(grep -E '^- ' "${MEDIUM_TERM_FILE}" 2>/dev/null | grep -vi 'no entries\|no extractable\|heartbeat\|idle' | sort -u | head -20 || true)
    if [ -n "${ITEMS}" ]; then
        SUMMARY="${SUMMARY}${ITEMS}"
    else
        SUMMARY="${SUMMARY}- (no extractable items found)"
    fi
fi

# --- Append to MEMORY.md ---

if [ ! -f "${LONG_TERM_FILE}" ]; then
    {
        echo "# Long-Term Memory"
        echo ""
        echo "> Permanent knowledge promoted from medium-term memory."
        echo "> Last updated: ${TIMESTAMP}"
        echo ""
        echo "${SUMMARY}"
    } > "${LONG_TERM_FILE}"
elif grep -q "No entries yet" "${LONG_TERM_FILE}" 2>/dev/null; then
    {
        echo "# Long-Term Memory"
        echo ""
        echo "> Permanent knowledge promoted from medium-term memory."
        echo "> Last updated: ${TIMESTAMP}"
        echo ""
        echo "${SUMMARY}"
    } > "${LONG_TERM_FILE}"
else
    # Append to existing MEMORY.md
    # Update timestamp if the header line exists
    if grep -q '^> Last updated:' "${LONG_TERM_FILE}" 2>/dev/null; then
        sed -i.bak "s/^> Last updated:.*/> Last updated: ${TIMESTAMP}/" "${LONG_TERM_FILE}" && rm -f "${LONG_TERM_FILE}.bak"
    fi

    {
        echo ""
        echo "---"
        echo ""
        echo "${SUMMARY}"
    } >> "${LONG_TERM_FILE}"
fi

# --- Archive and reset medium-term ---

cp "${MEDIUM_TERM_FILE}" "${ARCHIVE_DIR}/medium-term-${DATE_TAG}.md"

{
    echo "# Medium-Term Memory (2-Week Digest)"
    echo ""
    echo "> Last updated: ${TIMESTAMP}"
    echo "> Previous content promoted to MEMORY.md and archived."
    echo ""
    echo "*Fresh cycle started. Next entries will come from short-term promotion.*"
} > "${MEDIUM_TERM_FILE}"

# --- Cap MEMORY.md file size ---
LONG_LINES=$(wc -l < "${LONG_TERM_FILE}")
if [ "${LONG_LINES}" -gt 500 ]; then
    echo "[Memory] MEMORY.md exceeds 500 lines, archiving overflow..."
    cp "${LONG_TERM_FILE}" "${ARCHIVE_DIR}/MEMORY-overflow-${DATE_TAG}.md"

    {
        head -5 "${LONG_TERM_FILE}"
        echo ""
        echo "> Older entries archived to memory/archive/MEMORY-overflow-${DATE_TAG}.md"
        echo ""
        tail -400 "${LONG_TERM_FILE}"
    } > "${LONG_TERM_FILE}.tmp"
    mv "${LONG_TERM_FILE}.tmp" "${LONG_TERM_FILE}"
fi

echo "[Memory] Promoted medium-term -> MEMORY.md (${DATE_TAG})"
echo "[Memory] Medium-term archived to memory/archive/medium-term-${DATE_TAG}.md"
