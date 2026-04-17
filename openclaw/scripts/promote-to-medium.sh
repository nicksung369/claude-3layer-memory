#!/usr/bin/env bash
# promote-to-medium.sh (OpenClaw edition)
# Cron: every 48 hours (e.g. Mon+Thu 3am)
# Extracts key content from recent memory/*.md files -> memory/medium-term.md
# Pure text extraction — no AI dependency
#
# Usage:
#   Inside container:  /opt/openclaw-memory/scripts/promote-to-medium.sh
#   From host:         docker exec <container> /opt/openclaw-memory/scripts/promote-to-medium.sh
#
# Environment:
#   OPENCLAW_WORKSPACE  Override workspace path (default: /root/.openclaw/workspace)

set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-/root/.openclaw/workspace}"
MEMORY_DIR="${WORKSPACE}/memory"
MEDIUM_TERM_FILE="${MEMORY_DIR}/medium-term.md"
ARCHIVE_DIR="${MEMORY_DIR}/archive"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
DATE_TAG=$(date '+%Y-%m-%d')

mkdir -p "${MEMORY_DIR}" "${ARCHIVE_DIR}"

# Collect all recent daily memory files (exclude medium-term.md itself)
DAILY_FILES=()
for file in "${MEMORY_DIR}"/????-??-??.md; do
    [ -f "$file" ] || continue
    DAILY_FILES+=("$file")
done

if [ "${#DAILY_FILES[@]}" -eq 0 ]; then
    echo "[Memory] No daily memory files found, skipping promotion"
    exit 0
fi

# Count total content lines across all daily files
TOTAL_LINES=0
for file in "${DAILY_FILES[@]}"; do
    lines=$(grep -v '^#\|^>\|^$\|^\*\|^---' "$file" 2>/dev/null | wc -l)
    TOTAL_LINES=$((TOTAL_LINES + lines))
done

if [ "${TOTAL_LINES}" -lt 3 ]; then
    echo "[Memory] Daily memories too sparse (${TOTAL_LINES} lines total), skipping"
    exit 0
fi

# --- Extract key content from daily memory files ---

SUMMARY="## ${DATE_TAG} Digest

### Tasks & Activities
"

# Extract task/activity lines (bullet points that look meaningful)
TASKS=""
for file in "${DAILY_FILES[@]}"; do
    extracted=$(grep -E '^- ' "$file" 2>/dev/null \
        | grep -vi 'heartbeat_ok\|no tasks\|nothing to report\|idle' \
        | head -20 || true)
    if [ -n "${extracted}" ]; then
        TASKS="${TASKS}${extracted}
"
    fi
done

if [ -n "${TASKS}" ]; then
    # Deduplicate
    TASKS=$(echo "${TASKS}" | sort -u | head -30)
    SUMMARY="${SUMMARY}${TASKS}"
else
    SUMMARY="${SUMMARY}- (no extractable tasks found)"
fi

# Extract key decisions / important notes
DECISIONS=""
for file in "${DAILY_FILES[@]}"; do
    extracted=$(grep -iE '(decision|config|deploy|setup|install|update|fix|bug|error|issue|resolved|completed|launched|created|migration)' "$file" 2>/dev/null \
        | grep -E '^- ' \
        | head -10 || true)
    if [ -n "${extracted}" ]; then
        DECISIONS="${DECISIONS}${extracted}
"
    fi
done

if [ -n "${DECISIONS}" ]; then
    DECISIONS=$(echo "${DECISIONS}" | sort -u | head -15)
    SUMMARY="${SUMMARY}

### Key Events
${DECISIONS}"
fi

# Extract any file/path references
FILES=""
for file in "${DAILY_FILES[@]}"; do
    extracted=$(grep -oE '/[a-zA-Z0-9_./-]+\.(js|py|sh|md|json|yaml|yml|ts|tsx)' "$file" 2>/dev/null \
        | sort -u | head -15 || true)
    if [ -n "${extracted}" ]; then
        FILES="${FILES}${extracted}
"
    fi
done

if [ -n "${FILES}" ]; then
    FILES=$(echo "${FILES}" | sort -u | head -15 | sed 's/^/- /')
    SUMMARY="${SUMMARY}

### Files Referenced
${FILES}"
fi

# --- Append to medium-term ---

if [ ! -f "${MEDIUM_TERM_FILE}" ] || grep -q "No entries yet\|Fresh cycle" "${MEDIUM_TERM_FILE}" 2>/dev/null; then
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

    {
        head -4 "${MEDIUM_TERM_FILE}"
        echo ""
        echo "> Older entries archived to archive/medium-term-${DATE_TAG}.md"
        echo ""
        tail -200 "${MEDIUM_TERM_FILE}"
    } > "${MEDIUM_TERM_FILE}.tmp"
    mv "${MEDIUM_TERM_FILE}.tmp" "${MEDIUM_TERM_FILE}"
fi

echo "[Memory] Promoted daily memories -> medium-term (${DATE_TAG})"
