#!/usr/bin/env bash
# promote-to-long.sh
# Cron: every 2 weeks (1st+15th of month, 4am)
# Extracts permanent knowledge from medium-term.md and appends to long-term.md
# Then archives and resets medium-term.md for a fresh cycle
# Pure text extraction — no AI dependency
#
# Usage: ~/.claude/scripts/memory/promote-to-long.sh

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
GLOBAL_MEMORY_DIR="${CLAUDE_DIR}/memory/global"
MEDIUM_TERM_FILE="${GLOBAL_MEMORY_DIR}/medium-term.md"
LONG_TERM_FILE="${GLOBAL_MEMORY_DIR}/long-term.md"
ARCHIVE_DIR="${GLOBAL_MEMORY_DIR}/archive"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
DATE_TAG=$(date '+%Y-%m-%d')

mkdir -p "${GLOBAL_MEMORY_DIR}" "${ARCHIVE_DIR}"

# Check if medium-term has actual content
if [ ! -f "${MEDIUM_TERM_FILE}" ]; then
    echo "[Memory] No medium-term.md found, skipping promotion"
    exit 0
fi

MEDIUM_CONTENT=$(cat "${MEDIUM_TERM_FILE}")
if echo "${MEDIUM_CONTENT}" | grep -q "No entries yet"; then
    echo "[Memory] Medium-term memory is empty, skipping promotion"
    exit 0
fi

CONTENT_LINES=$(echo "${MEDIUM_CONTENT}" | grep -v '^#\|^>\|^$\|^\*No\|^---' | wc -l)
if [ "${CONTENT_LINES}" -lt 5 ]; then
    echo "[Memory] Medium-term content too sparse (${CONTENT_LINES} lines), skipping"
    exit 0
fi

# --- Extract key content via keyword matching ---

SUMMARY="## Promoted ${DATE_TAG}

### Decisions & Key Items
"

# Extract lines that look like decisions or important items
ITEMS=$(grep -E '^- .*(decision|config|setup|install|deploy|architecture|server|VPS|API|key|credential|preference|pattern|migration|database|docker|container|service|hook|cron|memory|auth)' "${MEDIUM_TERM_FILE}" 2>/dev/null | sort -u | head -20 || true)
if [ -n "${ITEMS}" ]; then
    SUMMARY="${SUMMARY}${ITEMS}"
else
    # Fallback: grab all bullet points
    ITEMS=$(grep -E '^- ' "${MEDIUM_TERM_FILE}" 2>/dev/null | grep -v 'No entries\|auto-extracted\|bullet points\|no extractable' | sort -u | head -20 || true)
    if [ -n "${ITEMS}" ]; then
        SUMMARY="${SUMMARY}${ITEMS}"
    else
        SUMMARY="${SUMMARY}- (no extractable items found)"
    fi
fi

# Extract project info
PROJECTS=$(grep -E '^\*\*Project:\*\*' "${MEDIUM_TERM_FILE}" 2>/dev/null | sort -u | head -10 || true)
if [ -n "${PROJECTS}" ]; then
    SUMMARY="${SUMMARY}

### Projects
${PROJECTS}"
fi

# --- Append to long-term ---

if [ ! -f "${LONG_TERM_FILE}" ] || grep -q "No entries yet" "${LONG_TERM_FILE}" 2>/dev/null; then
    {
        echo "# Long-Term Memory (Permanent)"
        echo ""
        echo "> Permanent knowledge promoted from medium-term memory."
        echo "> Last updated: ${TIMESTAMP}"
        echo ""
        echo "${SUMMARY}"
    } > "${LONG_TERM_FILE}"
else
    # Update timestamp
    sed -i.bak "s/^> Last updated:.*/> Last updated: ${TIMESTAMP}/" "${LONG_TERM_FILE}" && rm -f "${LONG_TERM_FILE}.bak"

    # Append
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
    echo "> Previous content promoted to long-term and archived."
    echo ""
    echo "*Fresh cycle started. Next entries will come from short-term promotion.*"
} > "${MEDIUM_TERM_FILE}"

# --- Cap long-term file size ---
LONG_LINES=$(wc -l < "${LONG_TERM_FILE}")
if [ "${LONG_LINES}" -gt 500 ]; then
    echo "[Memory] Long-term exceeds 500 lines, archiving overflow..."
    cp "${LONG_TERM_FILE}" "${ARCHIVE_DIR}/long-term-overflow-${DATE_TAG}.md"

    {
        head -5 "${LONG_TERM_FILE}"
        echo ""
        echo "> Older entries archived to ${ARCHIVE_DIR}/long-term-overflow-${DATE_TAG}.md"
        echo ""
        tail -400 "${LONG_TERM_FILE}"
    } > "${LONG_TERM_FILE}.tmp"
    mv "${LONG_TERM_FILE}.tmp" "${LONG_TERM_FILE}"
fi

echo "[Memory] Promoted medium-term -> long-term (${DATE_TAG})"
echo "[Memory] Medium-term archived to ${ARCHIVE_DIR}/medium-term-${DATE_TAG}.md"
