#!/usr/bin/env bash
# promote-to-medium.sh
# Cron: every 48 hours (e.g. Mon+Thu 3am)
# Extracts important content from short-term.md and appends to medium-term.md
# Pure text extraction — no AI dependency
#
# Usage: ~/.claude/scripts/memory/promote-to-medium.sh

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
GLOBAL_MEMORY_DIR="${CLAUDE_DIR}/memory/global"
SHORT_TERM_FILE="${GLOBAL_MEMORY_DIR}/short-term.md"
MEDIUM_TERM_FILE="${GLOBAL_MEMORY_DIR}/medium-term.md"
ARCHIVE_DIR="${GLOBAL_MEMORY_DIR}/archive"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
DATE_TAG=$(date '+%Y-%m-%d')

mkdir -p "${GLOBAL_MEMORY_DIR}" "${ARCHIVE_DIR}"

# Check if short-term has actual content
if [ ! -f "${SHORT_TERM_FILE}" ]; then
    echo "[Memory] No short-term.md found, skipping promotion"
    exit 0
fi

SHORT_CONTENT=$(cat "${SHORT_TERM_FILE}")
if echo "${SHORT_CONTENT}" | grep -q "No sessions in the past"; then
    echo "[Memory] Short-term memory is empty, skipping promotion"
    exit 0
fi

# Count lines of actual content (excluding headers/metadata)
CONTENT_LINES=$(echo "${SHORT_CONTENT}" | grep -v '^#\|^>\|^$\|^\*No\|^---' | wc -l)
if [ "${CONTENT_LINES}" -lt 5 ]; then
    echo "[Memory] Short-term content too sparse (${CONTENT_LINES} lines), skipping"
    exit 0
fi

# --- Extract key content from short-term ---

SUMMARY="## ${DATE_TAG} Digest

### Session Summaries
"

# Extract task lines (filter out IDE noise and command metadata)
TASKS=$(grep -E '^- ' "${SHORT_TERM_FILE}" 2>/dev/null | grep -v 'ide_opened_file\|local-command\|command-name\|command-message\|command-args\|local-command-stdout\|local-command-caveat' | head -30 || true)
if [ -n "${TASKS}" ]; then
    SUMMARY="${SUMMARY}${TASKS}"
else
    SUMMARY="${SUMMARY}- (no extractable tasks found)"
fi

# Extract files modified
FILES=$(grep -E '^- /' "${SHORT_TERM_FILE}" 2>/dev/null | sort -u | head -20 || true)
if [ -n "${FILES}" ]; then
    SUMMARY="${SUMMARY}

### Files Modified
${FILES}"
fi

# Extract project/worktree info
PROJECTS=$(grep -E '^\*\*Project:\*\*' "${SHORT_TERM_FILE}" 2>/dev/null | sort -u | head -10 || true)
if [ -n "${PROJECTS}" ]; then
    SUMMARY="${SUMMARY}

### Projects Active
${PROJECTS}"
fi

# Extract tools used
TOOLS=$(grep -E '^### Tools Used' -A1 "${SHORT_TERM_FILE}" 2>/dev/null | grep -v '^###\|^--$' | sort -u | head -5 || true)
if [ -n "${TOOLS}" ]; then
    SUMMARY="${SUMMARY}

### Tools Used
${TOOLS}"
fi

# --- Append to medium-term ---

if [ ! -f "${MEDIUM_TERM_FILE}" ] || grep -q "No entries yet" "${MEDIUM_TERM_FILE}" 2>/dev/null; then
    {
        echo "# Medium-Term Memory (2-Week Digest)"
        echo ""
        echo "> Last updated: ${TIMESTAMP}"
        echo ""
        echo "${SUMMARY}"
    } > "${MEDIUM_TERM_FILE}"
else
    # Update timestamp in header
    sed -i.bak "s/^> Last updated:.*/> Last updated: ${TIMESTAMP}/" "${MEDIUM_TERM_FILE}" && rm -f "${MEDIUM_TERM_FILE}.bak"

    # Append new digest
    {
        echo ""
        echo "---"
        echo ""
        echo "${SUMMARY}"
    } >> "${MEDIUM_TERM_FILE}"
fi

# --- Prune if too large ---
MEDIUM_LINES=$(wc -l < "${MEDIUM_TERM_FILE}")
if [ "${MEDIUM_LINES}" -gt 300 ]; then
    echo "[Memory] Medium-term exceeds 300 lines, archiving old content..."
    cp "${MEDIUM_TERM_FILE}" "${ARCHIVE_DIR}/medium-term-${DATE_TAG}.md"

    # Keep header + last 200 lines
    {
        head -4 "${MEDIUM_TERM_FILE}"
        echo ""
        echo "> Older entries archived to ${ARCHIVE_DIR}/medium-term-${DATE_TAG}.md"
        echo ""
        tail -200 "${MEDIUM_TERM_FILE}"
    } > "${MEDIUM_TERM_FILE}.tmp"
    mv "${MEDIUM_TERM_FILE}.tmp" "${MEDIUM_TERM_FILE}"
fi

echo "[Memory] Promoted short-term -> medium-term (${DATE_TAG})"
