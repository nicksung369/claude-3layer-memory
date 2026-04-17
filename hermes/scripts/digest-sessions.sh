#!/usr/bin/env bash
# digest-sessions.sh — Hermes Agent edition
#
# Reads recent rows from ~/.hermes/state.db and writes a rolling
# 2-week digest to ~/.hermes/memories/medium-term.md.
#
# This script NEVER writes to MEMORY.md or USER.md — those are agent-
# curated and have strict character budgets (2200/1375 chars). See
# suggest-promotions.sh for the promotion path that respects them.
#
# Cron (every 48h, Mon+Thu 3am):
#   0 3 * * 1,4 ~/.hermes/scripts/3layer/digest-sessions.sh
#
# Environment overrides:
#   HERMES_HOME      Default: ~/.hermes
#   HERMES_DB        Default: $HERMES_HOME/state.db
#   HERMES_MEMORIES  Default: $HERMES_HOME/memories
#   DIGEST_DAYS      Retention window in days (default: 14)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_DB="${HERMES_DB:-${HERMES_HOME}/state.db}"
HERMES_MEMORIES="${HERMES_MEMORIES:-${HERMES_HOME}/memories}"
DIGEST_DAYS="${DIGEST_DAYS:-14}"
OUT="${HERMES_MEMORIES}/medium-term.md"

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "[digest] sqlite3 CLI not found; install sqlite3 and retry" >&2
    exit 1
fi

if [ ! -f "${HERMES_DB}" ]; then
    echo "[digest] ${HERMES_DB} not found; is Hermes Agent installed?" >&2
    exit 1
fi

mkdir -p "${HERMES_MEMORIES}"

# Introspect schema — Hermes has evolved; don't hard-fail on column renames.
# We require at least a 'sessions' table with an updated_at-ish column and a
# 'messages' table with (session_id, role, content).
HAS_SESSIONS=$(sqlite3 "${HERMES_DB}" \
  "SELECT 1 FROM sqlite_master WHERE type='table' AND name='sessions' LIMIT 1;")
HAS_MESSAGES=$(sqlite3 "${HERMES_DB}" \
  "SELECT 1 FROM sqlite_master WHERE type='table' AND name='messages' LIMIT 1;")
if [ -z "${HAS_SESSIONS}" ] || [ -z "${HAS_MESSAGES}" ]; then
    echo "[digest] expected 'sessions' and 'messages' tables in ${HERMES_DB}" >&2
    echo "[digest] schema may have changed; inspect with: sqlite3 ${HERMES_DB} .schema" >&2
    exit 1
fi

# Pick a timestamp column that actually exists.
TS_COL=""
for cand in updated_at created_at ts; do
    if sqlite3 "${HERMES_DB}" "PRAGMA table_info(sessions);" | grep -q "|${cand}|"; then
        TS_COL="${cand}"
        break
    fi
done
if [ -z "${TS_COL}" ]; then
    echo "[digest] could not find a timestamp column on sessions table" >&2
    exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

{
    echo "# Medium-Term Memory (${DIGEST_DAYS}-Day Digest)"
    echo ""
    echo "> Source: Hermes \`state.db\` · Updated: $(date -u +'%Y-%m-%d %H:%M UTC')"
    echo "> Window: past ${DIGEST_DAYS} days · Curated by \`digest-sessions.sh\`"
    echo ""

    # Summary counts
    COUNTS=$(sqlite3 -separator '|' "${HERMES_DB}" "
        SELECT
          (SELECT COUNT(*) FROM sessions
             WHERE ${TS_COL} > datetime('now','-${DIGEST_DAYS} days')) AS sess,
          (SELECT COUNT(*) FROM messages m
             JOIN sessions s ON s.id = m.session_id
             WHERE s.${TS_COL} > datetime('now','-${DIGEST_DAYS} days')
               AND m.role = 'user') AS user_msgs;")
    SESS=$(echo "${COUNTS}" | cut -d'|' -f1)
    UMSGS=$(echo "${COUNTS}" | cut -d'|' -f2)
    echo "- Sessions: ${SESS}"
    echo "- User turns: ${UMSGS}"
    echo ""

    echo "## Recent Sessions"
    echo ""
    sqlite3 -separator $'\t' "${HERMES_DB}" "
        SELECT COALESCE(title, '(untitled)'), ${TS_COL}
        FROM sessions
        WHERE ${TS_COL} > datetime('now','-${DIGEST_DAYS} days')
        ORDER BY ${TS_COL} DESC
        LIMIT 25;" | while IFS=$'\t' read -r title ts; do
        echo "- **${title}** _(${ts})_"
    done
    echo ""

    echo "## Top User Intents (first 140 chars)"
    echo ""
    sqlite3 -separator $'\x1f' "${HERMES_DB}" "
        SELECT substr(replace(replace(content, char(10),' '), char(13),' '), 1, 140)
        FROM messages m
        JOIN sessions s ON s.id = m.session_id
        WHERE s.${TS_COL} > datetime('now','-${DIGEST_DAYS} days')
          AND m.role = 'user'
        ORDER BY m.id DESC
        LIMIT 30;" | while IFS= read -r line; do
        [ -n "${line}" ] && echo "- ${line}"
    done
    echo ""

    echo "## Tools Invoked (count)"
    echo ""
    sqlite3 -separator $'\t' "${HERMES_DB}" "
        SELECT tool_name, COUNT(*) AS n
        FROM messages m
        JOIN sessions s ON s.id = m.session_id
        WHERE s.${TS_COL} > datetime('now','-${DIGEST_DAYS} days')
          AND tool_name IS NOT NULL AND tool_name != ''
        GROUP BY tool_name
        ORDER BY n DESC
        LIMIT 15;" | while IFS=$'\t' read -r tool n; do
        echo "- \`${tool}\` — ${n}"
    done
    echo ""
} > "${TMP}"

mv "${TMP}" "${OUT}"
trap - EXIT
echo "[digest] wrote ${OUT} (sessions=${SESS}, user_turns=${UMSGS}, window=${DIGEST_DAYS}d)"
