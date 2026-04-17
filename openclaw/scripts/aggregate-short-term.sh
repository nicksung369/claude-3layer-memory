#!/usr/bin/env bash
# aggregate-short-term.sh (OpenClaw edition)
# Cron: every 6 hours
# Cleans up memory/ directory: removes files older than 48h, keeps recent ones
#
# In OpenClaw, each agent writes memory/YYYY-MM-DD.md daily.
# This script prunes stale entries so the agent only loads recent context.
#
# Usage:
#   Inside container:  /opt/openclaw-memory/scripts/aggregate-short-term.sh
#   From host:         docker exec <container> /opt/openclaw-memory/scripts/aggregate-short-term.sh
#
# Environment:
#   OPENCLAW_WORKSPACE  Override workspace path (default: /root/.openclaw/workspace)
#   CUTOFF_HOURS        Override retention window (default: 48)

set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-/root/.openclaw/workspace}"
MEMORY_DIR="${WORKSPACE}/memory"
CUTOFF_HOURS="${CUTOFF_HOURS:-48}"
ARCHIVE_DIR="${MEMORY_DIR}/archive"

mkdir -p "${MEMORY_DIR}" "${ARCHIVE_DIR}"

# Calculate cutoff date
if date --version >/dev/null 2>&1; then
    # GNU date
    CUTOFF_DATE=$(date -d "-${CUTOFF_HOURS} hours" '+%Y-%m-%d')
else
    # BSD/macOS date
    CUTOFF_DATE=$(date -v-${CUTOFF_HOURS}H '+%Y-%m-%d')
fi

ARCHIVED=0
KEPT=0

# Iterate over daily memory files
for file in "${MEMORY_DIR}"/????-??-??.md; do
    [ -f "$file" ] || continue

    filename=$(basename "$file" .md)

    # Compare date strings (YYYY-MM-DD sorts lexicographically)
    if [[ "${filename}" < "${CUTOFF_DATE}" ]]; then
        mv "$file" "${ARCHIVE_DIR}/"
        ARCHIVED=$((ARCHIVED + 1))
    else
        KEPT=$((KEPT + 1))
    fi
done

# Cap archive size: keep only last 30 files
ARCHIVE_COUNT=$(find "${ARCHIVE_DIR}" -name '????-??-??.md' 2>/dev/null | wc -l)
if [ "${ARCHIVE_COUNT}" -gt 30 ]; then
    find "${ARCHIVE_DIR}" -name '????-??-??.md' | sort | head -n "$((ARCHIVE_COUNT - 30))" | xargs rm -f
fi

echo "[Memory] Short-term cleanup: kept=${KEPT}, archived=${ARCHIVED}, cutoff=${CUTOFF_DATE}"
