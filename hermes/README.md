# hermes-3layer-memory

Three-layer memory automation for [Hermes Agent](https://github.com/NousResearch/hermes-agent) — the self-improving open-source agent from Nous Research.

> **Why this exists.** Hermes already has an excellent agent-curated `MEMORY.md` with a hard 2,200-character budget and a SQLite-backed session store with FTS5 search. What it doesn't have is a **time-based** tiering pipeline. This skill adds one without fighting Hermes's budget-based self-curation.

## The Design Contract

```
┌──────────────────────┐  every 48h  ┌─────────────────────┐
│ state.db (SQLite)    │ ──────────> │ medium-term.md       │
│  sessions + messages │  (digest)   │ (14-day rolling)     │
│  + messages_fts      │             └──────────┬──────────┘
└──────────────────────┘                        │ every 2 weeks
            ^                                   v
            │ (Hermes writes)          ┌─────────────────────┐
            │                          │ _promotions.md       │
            │                          │ (review queue)       │
            │                          └──────────┬──────────┘
            │                                     │ human/agent review
            │                                     v
            │                          ┌─────────────────────┐
            └──────────────────────────┤ MEMORY.md (≤2200c)  │
                                       │ + USER.md (≤1375c)  │
                                       │ (agent-curated — we │
                                       │  NEVER write here)  │
                                       └─────────────────────┘
```

### What this skill does

| Layer | File | Who writes |
|-------|------|-----------|
| **Short-term** | `~/.hermes/state.db` | Hermes itself (existing) |
| **Medium-term** | `~/.hermes/memories/medium-term.md` | `digest-sessions.sh` (new) |
| **Promotion queue** | `~/.hermes/memories/_promotions.md` | `suggest-promotions.sh` (new) |
| **Long-term** | `~/.hermes/memories/MEMORY.md` | Hermes — we never touch it |

### What this skill does NOT do

- **Never writes to `MEMORY.md` or `USER.md`.** Those have strict character budgets. Overwriting them breaks Hermes. We produce a review queue; the user or the agent lifts entries in manually.
- **Never calls any AI API.** All digestion is SQL aggregation + `awk` / `grep` / `uniq -c`.
- **Never modifies the agent's session DB.** We only read from `state.db`.

## Installation

Requires Hermes Agent installed (`~/.hermes/` exists) and the `sqlite3` CLI.

```bash
git clone https://github.com/nicksung369/claude-3layer-memory.git
cd claude-3layer-memory/hermes
./install.sh --with-cron
```

Custom Hermes home:

```bash
./install.sh --hermes-home /opt/hermes --with-cron
```

### Manual verification

```bash
~/.hermes/scripts/3layer/digest-sessions.sh
cat ~/.hermes/memories/medium-term.md

~/.hermes/scripts/3layer/suggest-promotions.sh
cat ~/.hermes/memories/_promotions.md
```

### Web viewer (optional)

The main repo's viewer works against the Hermes `memories/` dir:

```bash
python3 ../viewer/server.py --dir ~/.hermes/memories
# open http://127.0.0.1:37777
```

## Cron Schedule

| Script | Schedule | Purpose |
|--------|----------|---------|
| `digest-sessions.sh` | `0 3 * * 1,4` (Mon+Thu 3am) | Dump last 14 days of sessions to `medium-term.md` |
| `suggest-promotions.sh` | `0 4 1,15 * *` (1st+15th 4am) | Append recurring intents to `_promotions.md` |

## Uninstall

```bash
./install.sh --uninstall
```

Removes the scripts and the cron entries. Preserves `medium-term.md`, `_promotions.md`, `MEMORY.md`, `USER.md`, and `state.db`.

## Implementation Notes

- **Schema introspection** — `digest-sessions.sh` detects which timestamp column exists (`updated_at` / `created_at` / `ts`) and adapts. If Hermes renames tables, the script fails with a clear error instead of silently producing garbage.
- **Budget awareness** — `suggest-promotions.sh` reports current `MEMORY.md` char usage and flags low headroom (<200 chars) before producing candidates.
- **Stop-word filter** — English stop words are dropped before ranking recurring intents so "with / from / this / that" don't dominate.
- **`MIN_FREQ` knob** — override via env: `MIN_FREQ=5 suggest-promotions.sh` for noisier installs.

## Compared to the other editions

| | Claude Code | OpenClaw | **Hermes** |
|---|------------|----------|------------|
| Short-term source | session `.tmp` files | daily `YYYY-MM-DD.md` | `state.db` (SQLite) |
| Medium-term file | `medium-term.md` | `medium-term.md` | `medium-term.md` |
| Long-term file | `long-term.md` | `MEMORY.md` (append) | `_promotions.md` (review) |
| Writes to agent's curated file? | yes | yes (append) | **no** — budget-capped |
| Dependencies | bash | bash | bash + `sqlite3` CLI |

## License

MIT — same as the parent repo.
