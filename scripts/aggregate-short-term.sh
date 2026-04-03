#!/usr/bin/env bash
# aggregate-short-term.sh
# Cron: every 6 hours
# Aggregates all session-data files from the past 48 hours into short-term.md
#
# Usage: ~/.claude/scripts/memory/aggregate-short-term.sh

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SESSION_DATA_DIR="${CLAUDE_DIR}/session-data"
GLOBAL_MEMORY_DIR="${CLAUDE_DIR}/memory/global"
SHORT_TERM_FILE="${GLOBAL_MEMORY_DIR}/short-term.md"
CUTOFF_HOURS=48

# Ensure directories exist
mkdir -p "${GLOBAL_MEMORY_DIR}"

# Find all session files modified within the past 48 hours
# Exclude non-session files like compaction-log.txt
SESSION_FILES=()
while IFS= read -r -d '' file; do
    SESSION_FILES+=("$file")
done < <(find "${SESSION_DATA_DIR}" -name "*-session.tmp" -mmin "-$((CUTOFF_HOURS * 60))" -print0 2>/dev/null | sort -z)

# Also check project-level session-data directories
for project_dir in "${CLAUDE_DIR}/projects"/*/; do
    if [ -d "${project_dir}session-data" ]; then
        while IFS= read -r -d '' file; do
            SESSION_FILES+=("$file")
        done < <(find "${project_dir}session-data" -name "*-session.tmp" -mmin "-$((CUTOFF_HOURS * 60))" -print0 2>/dev/null | sort -z)
    fi
done

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
SESSION_COUNT=${#SESSION_FILES[@]}

# Build the short-term memory file
{
    echo "# Short-Term Memory (48h Rolling)"
    echo ""
    echo "> Last aggregated: ${TIMESTAMP}"
    echo "> Sessions found: ${SESSION_COUNT}"
    echo "> Window: past ${CUTOFF_HOURS} hours"
    echo ""

    if [ "${SESSION_COUNT}" -eq 0 ]; then
        echo "*No sessions in the past ${CUTOFF_HOURS} hours.*"
    else
        for file in "${SESSION_FILES[@]}"; do
            # Extract key info from session file
            basename_file=$(basename "$file")
            mod_time=$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$file" 2>/dev/null | cut -d'.' -f1)

            echo "---"
            echo ""
            echo "### ${basename_file} (${mod_time})"
            echo ""

            # Extract only the summary section (between ECC markers) for conciseness
            if grep -q 'ECC:SUMMARY:START' "$file" 2>/dev/null; then
                sed -n '/ECC:SUMMARY:START/,/ECC:SUMMARY:END/p' "$file" | grep -v 'ECC:SUMMARY'
            else
                # Fallback: include the header and first 30 lines of content
                head -30 "$file"
            fi

            echo ""

            # Also extract project/worktree metadata from header
            grep -E '^\*\*(Project|Branch|Worktree):\*\*' "$file" 2>/dev/null | head -3 || true

            echo ""
        done
    fi
} > "${SHORT_TERM_FILE}"

echo "[Memory] Aggregated ${SESSION_COUNT} sessions into ${SHORT_TERM_FILE}"
