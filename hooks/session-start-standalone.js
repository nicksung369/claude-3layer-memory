#!/usr/bin/env node
/**
 * Standalone SessionStart Hook — Tiered Memory Loader
 *
 * A minimal, self-contained session-start hook that loads three-tier
 * global memory into Claude Code's context. Use this if you don't
 * have an existing session-start hook.
 *
 * Installation:
 *   1. Copy to ~/.claude/scripts/hooks/session-start.js
 *   2. Add to ~/.claude/settings.json:
 *      {
 *        "hooks": {
 *          "SessionStart": [{
 *            "type": "command",
 *            "command": "node ~/.claude/scripts/hooks/session-start.js"
 *          }]
 *        }
 *      }
 */

const path = require('path');
const fs = require('fs');

const CLAUDE_DIR = path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude');
const GLOBAL_MEMORY_DIR = path.join(CLAUDE_DIR, 'memory', 'global');

const MEMORY_TIERS = [
  { file: 'long-term.md', label: 'Long-term memory (permanent knowledge)', maxLines: 150 },
  { file: 'medium-term.md', label: 'Medium-term memory (2-week digest)', maxLines: 100 },
  { file: 'short-term.md', label: 'Short-term memory (48h rolling)', maxLines: 200 },
];

function readFileSafe(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

function loadTieredMemory() {
  const parts = [];

  for (const tier of MEMORY_TIERS) {
    const tierPath = path.join(GLOBAL_MEMORY_DIR, tier.file);
    const content = readFileSafe(tierPath);

    if (!content || content.includes('No entries yet') || content.includes('No sessions')) {
      continue;
    }

    const lines = content.split('\n');
    const truncated = lines.length > tier.maxLines
      ? lines.slice(0, tier.maxLines).join('\n') + `\n\n... (truncated, ${lines.length - tier.maxLines} more lines)`
      : content;

    parts.push(`${tier.label}:\n${truncated}`);
  }

  return parts;
}

function loadPreviousSession() {
  const sessionsDir = path.join(CLAUDE_DIR, 'session-data');
  if (!fs.existsSync(sessionsDir)) return null;

  // Find most recent session file
  const files = fs.readdirSync(sessionsDir)
    .filter(f => f.endsWith('-session.tmp'))
    .map(f => ({
      name: f,
      path: path.join(sessionsDir, f),
      mtime: fs.statSync(path.join(sessionsDir, f)).mtimeMs,
    }))
    .sort((a, b) => b.mtime - a.mtime);

  if (files.length === 0) return null;

  const cwd = process.cwd();
  // Prefer session matching current worktree
  for (const file of files) {
    const content = readFileSafe(file.path);
    if (!content) continue;
    const worktreeMatch = content.match(/\*\*Worktree:\*\*\s*(.+)$/m);
    if (worktreeMatch && worktreeMatch[1].trim() === cwd) {
      return content;
    }
  }

  // Fallback: most recent
  return readFileSafe(files[0].path);
}

async function main() {
  const contextParts = [];

  // Load tiered memory
  contextParts.push(...loadTieredMemory());

  // Load previous session summary
  const prevSession = loadPreviousSession();
  if (prevSession && !prevSession.includes('[Session context goes here]')) {
    contextParts.push(`Previous session summary:\n${prevSession}`);
  }

  // Output for Claude Code
  const payload = JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: contextParts.join('\n\n'),
    },
  });

  process.stdout.write(payload);
}

main().catch(err => {
  console.error('[SessionStart] Error:', err.message);
  process.exitCode = 0;
});
