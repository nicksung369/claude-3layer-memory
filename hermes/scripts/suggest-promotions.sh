#!/usr/bin/env bash
# suggest-promotions.sh — Hermes Agent edition
#
# Reads ~/.hermes/memories/medium-term.md, extracts recurring phrases / intents,
# and appends candidates to ~/.hermes/memories/_promotions.md for human or
# agent review.
#
# This script NEVER writes to MEMORY.md directly — MEMORY.md has a hard 2,200
# character budget enforced by Hermes. Overwriting it breaks the agent. The
# user or the agent reviews _promotions.md and decides what to lift in.
#
# Cron (every 2 weeks, 1st+15th 4am):
#   0 4 1,15 * * ~/.hermes/scripts/3layer/suggest-promotions.sh
#
# Environment overrides:
#   HERMES_HOME      Default: ~/.hermes
#   HERMES_MEMORIES  Default: $HERMES_HOME/memories
#   MIN_FREQ         Minimum occurrence to suggest (default: 3)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_MEMORIES="${HERMES_MEMORIES:-${HERMES_HOME}/memories}"
MIN_FREQ="${MIN_FREQ:-3}"

MED="${HERMES_MEMORIES}/medium-term.md"
QUEUE="${HERMES_MEMORIES}/_promotions.md"
MEMORY_CAP=2200

if [ ! -f "${MED}" ]; then
    echo "[promote] ${MED} not found — run digest-sessions.sh first" >&2
    exit 1
fi

# Seed queue file if missing
if [ ! -f "${QUEUE}" ]; then
    cat > "${QUEUE}" <<'EOF'
# Promotion Candidates → MEMORY.md

> Human or agent reviews this file. Nothing here is auto-lifted into
> `MEMORY.md`. When an entry proves durable, copy it into `MEMORY.md`
> manually, respecting the 2,200-character budget.

EOF
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

{
    echo ""
    echo "---"
    echo ""
    echo "## Review Batch — $(date -u +'%Y-%m-%d %H:%M UTC')"
    echo ""

    # Current MEMORY.md headroom
    MEMORY_FILE="${HERMES_MEMORIES}/MEMORY.md"
    if [ -f "${MEMORY_FILE}" ]; then
        USED=$(wc -c < "${MEMORY_FILE}" | tr -d ' ')
    else
        USED=0
    fi
    HEADROOM=$((MEMORY_CAP - USED))
    echo "- **MEMORY.md usage:** ${USED} / ${MEMORY_CAP} chars (headroom: ${HEADROOM})"
    if [ "${HEADROOM}" -lt 200 ]; then
        echo "- ⚠️  Headroom < 200 chars — consider consolidating existing entries before promoting."
    fi
    echo ""

    # Recurring intents: lines under "Top User Intents" in medium-term,
    # extract tokens that appear ≥ MIN_FREQ times.
    echo "### Recurring Intents (freq ≥ ${MIN_FREQ})"
    echo ""
    awk '
        /^## Top User Intents/ { capture=1; next }
        /^## / && capture     { capture=0 }
        capture && /^- /      { sub(/^- /,""); print }
    ' "${MED}" \
      | tr '[:upper:]' '[:lower:]' \
      | tr -cs 'a-z0-9' '\n' \
      | awk 'length($0) >= 4' \
      | grep -Ev '^(that|with|from|this|have|what|when|where|which|will|would|could|should|about|into|then|than|because|please|thanks?|okay|just|like|some|here|there|also|been|being|does|doing|done|make|made|really|still|they|them|their|your|yours|myself|ourselves)$' \
      | sort | uniq -c | sort -rn \
      | awk -v m="${MIN_FREQ}" '$1 >= m { printf "- `%s` — %d times\n", $2, $1 }' \
      | head -20

    echo ""
    echo "### Frequent Tools"
    echo ""
    awk '
        /^## Tools Invoked/ { capture=1; next }
        /^## / && capture   { capture=0 }
        capture && /^- /    { print }
    ' "${MED}" | head -10

    echo ""
    echo "### Suggested MEMORY.md snippets"
    echo ""
    echo "_Copy any of the above into \`MEMORY.md\` yourself. Keep the total_"
    echo "_under ${MEMORY_CAP} chars; Hermes will truncate beyond that._"
} >> "${QUEUE}"

echo "[promote] appended review batch to ${QUEUE}"
