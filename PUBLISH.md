# Publishing Checklist

Everything needed to take this repo from "on disk" to "discoverable on GitHub." Work top to bottom — each section takes 5-20 minutes.

> 💡 **This file is for the maintainer only.** Remove or keep it in the repo — either is fine.

---

## 0. Confirm your GitHub handle

README, `openclaw/README.md`, and `hermes/README.md` already point to `nicksung369/claude-3layer-memory`.
If you fork or rename the repo later, replace `nicksung369` in the markdown docs once:

```bash
cd /path/to/claude-3layer-memory
HANDLE=nicksung369                # current repo owner; edit only if you fork/rename
grep -rl 'nicksung369' --include='*.md' . \
  | xargs sed -i.bak "s|nicksung369|${HANDLE}|g"
find . -name '*.bak' -delete
grep -rn 'nicksung369' --include='*.md' . || echo "✓ all owner references replaced"
```

Also confirm the git remote matches:

```bash
git remote set-url origin https://github.com/${HANDLE}/claude-3layer-memory.git
git remote -v
```

---

## 1. Commit and push

Suggested 3-commit split (history stays readable):

```bash
# Commit 1: the web viewer
git add viewer/
git commit -m "feat: add localhost:37777 web viewer

Single-file stdlib-only HTTP server that lists every tier (short/medium/
long + auto-memory) with search, type filtering, and 3s live refresh.
Includes demo dataset, screenshot, GIF, launchd plist, systemd unit, and
opt-in controls to trigger aggregate/promote scripts from the UI."

# Commit 2: the hermes edition
git add hermes/
git commit -m "feat(hermes): 3-layer memory edition for Hermes Agent

Adapts the tiering pattern to Hermes's SQLite session store + 2200-char
MEMORY.md budget. digest-sessions.sh reads state.db; suggest-promotions.sh
produces a review queue. Never writes MEMORY.md directly — respects
Hermes's agent-curated budget contract."

# Commit 3: everything else (install.sh --with-all, --status, README hero,
# openclaw fix, PUBLISH.md)
git add .
git commit -m "feat: --with-all, --status, hero README, openclaw fixes

- install.sh: --with-all (cron + viewer shortcut), --status (health check)
- README: hero pitch + demo GIF + quick start at the top
- openclaw/install.sh: remove unsafe apt-get cron auto-install, add viewer hook
- PUBLISH.md: post-push discoverability checklist"

git push -u origin main
```

---

## 2. Set GitHub Topics (5 minutes)

Topics control which **search pages** your repo shows up on. Run once after push:

```bash
gh repo edit ${HANDLE}/claude-3layer-memory \
  --add-topic claude-code \
  --add-topic claude \
  --add-topic hermes \
  --add-topic hermes-agent \
  --add-topic openclaw \
  --add-topic memory \
  --add-topic persistent-memory \
  --add-topic llm-memory \
  --add-topic ai-agents \
  --add-topic mcp
```

Check the result:

```bash
gh repo view ${HANDLE}/claude-3layer-memory --json repositoryTopics
```

**Priority topics** (these are the highest-traffic ones):
1. `claude-code` — Claude Code official topic
2. `hermes` — riding the 47k-star wave
3. `ai-agents` — broadest entry point

---

## 3. Upload Social Preview (2 minutes)

The card people see when your repo is shared on X / Slack / LinkedIn.

Ready PNG: [`viewer/social-preview.png`](viewer/social-preview.png) (1280×640 @2x, ~655KB)

**Steps:**

1. Open `https://github.com/${HANDLE}/claude-3layer-memory/settings`
2. Scroll to **Social preview** → **Edit**
3. Upload `viewer/social-preview.png`
4. Save

Verify by opening the repo in an incognito window and checking the `<meta property="og:image">` tag.

---

## 4. Submit to awesome-lists (10 minutes each, merge takes days-weeks)

Three lists where this project fits. For each: fork → edit → PR.

### 4a. awesome-claude-code

**Target:** https://github.com/hesreallyhim/awesome-claude-code

**Section to add under:** Likely "Memory" or "Tools" — check current README for the right spot.

**Entry to add:**

```markdown
- [claude-3layer-memory](https://github.com/nicksung369/claude-3layer-memory) — Persistent short/medium/long-term memory for Claude Code, OpenClaw, and Hermes. Bash + cron, zero AI cost, local web dashboard at localhost:37777.
```

**PR description:**

```
Adds claude-3layer-memory — a memory-tiering tool that works with Claude Code,
OpenClaw, and Hermes Agent.

- Three tiers (short/medium/long) promoted via cron + grep/sed — no vector DB, no API calls
- Optional web viewer at localhost:37777 with live refresh
- Three editions in one repo: Claude Code, OpenClaw, and Hermes-adapted
- MIT licensed, stdlib-only Python for the viewer, pure bash for the scripts

Happy to adjust the placement or description if you'd like a different spot.
```

### 4b. awesome-ai-agents

**Target:** https://github.com/e2b-dev/awesome-ai-agents (or similar — pick the highest-star one that's still maintained)

**Section:** "Tools" / "Developer Tools" / "Memory"

**Entry:** same markdown line as 4a.

### 4c. awesome-llm-apps / awesome-mcp-servers (pick one if applicable)

**Targets:**
- https://github.com/Shubhamsaboo/awesome-llm-apps
- https://github.com/punkpeye/awesome-mcp-servers (only if you add MCP server support later — skip for now)

---

## 5. Create a v0.1.0 release tag

```bash
git tag -a v0.1.0 -m "v0.1.0 — first public release

- Three-layer memory for Claude Code, OpenClaw, Hermes
- Web viewer (localhost:37777) with live refresh
- --with-all + --status install flags"

git push origin v0.1.0
```

Then on GitHub: Releases → Draft a new release → pick the tag → paste the same message.

Having a release tag lets other tools pin a version.

---

## 6. Optional — announce publicly

Once the above is done, you can announce. In rough order of return-on-effort:

### X / Twitter

A thread of 3-4 tweets. First tweet = demo GIF + one-line pitch + repo link.

```
I open-sourced a tool that gives Claude Code (and Hermes, and OpenClaw) persistent memory across sessions.

Short → medium → long-term, all in local markdown files. No vector DB. No API costs. Has a live dashboard at localhost:37777.

<repo link>
```

Attach `viewer/demo.gif` (already 2.7MB, fits in X's 15MB cap).

### Hacker News

Title: `Show HN: claude-3layer-memory – persistent memory for Claude, OpenClaw, Hermes`

Post body: ~300 words. Lead with the problem, mention "no embedding costs" and "3s live-refresh dashboard" as differentiators. Link to repo.

### Reddit

- r/LocalLLaMA — post with demo GIF
- r/ChatGPTCoding — only if traffic's slow, they're looser about tool posts

---

## Discoverability scoreboard

| Channel | Cost | Payoff | Time to pay off |
|---------|------|--------|-----------------|
| GitHub Topics | 5 min | Medium | Immediate |
| Social preview | 2 min | Medium (when shared) | Immediate |
| awesome-claude-code PR | 15 min + wait | High | 2-4 weeks |
| awesome-ai-agents PR | 15 min + wait | Medium-High | 2-6 weeks |
| X thread | 30 min | High if it catches | Days |
| HN Show HN | 45 min | Very high if it catches, zero if not | 1 day or never |
| v0.1.0 release tag | 2 min | Low alone, required for other channels | Immediate |

---

## Do not do

- **Don't** skip the handle replacement. 7 broken clone links in README = trust killer.
- **Don't** submit to 10 awesome-lists at once. 3 curated PRs > 10 spammy ones.
- **Don't** post to HN without a GIF or screenshot embedded. HN voters scan in < 5 seconds.
- **Don't** force-push after initial release. Once `v0.1.0` is tagged, that commit is someone's pin.
