/**
 * Session Start Hook Patch — Tiered Memory Loader
 *
 * Add this snippet to your existing session-start hook to load
 * three-tier global memory (long-term → medium-term → short-term)
 * into Claude's context at the beginning of each session.
 *
 * If you don't have an existing session-start hook, you can use
 * session-start-standalone.js as a complete, ready-to-use hook.
 *
 * Integration:
 *   1. Open your session-start hook (e.g. ~/.claude/scripts/hooks/session-start.js)
 *   2. Add the loadTieredMemory() function below
 *   3. Call it in your main() and append results to additionalContextParts
 */

const path = require('path');
const fs = require('fs');

/**
 * Load three-tier global memory files.
 * Returns an array of context strings to inject into the session.
 *
 * @param {string} claudeDir - Path to ~/.claude
 * @returns {string[]} Array of context parts to append to additionalContextParts
 */
function loadTieredMemory(claudeDir) {
  const globalMemoryDir = path.join(claudeDir, 'memory', 'global');
  const contextParts = [];

  const memoryTiers = [
    { file: 'long-term.md', label: 'Long-term memory (permanent knowledge)', maxLines: 150 },
    { file: 'medium-term.md', label: 'Medium-term memory (2-week digest)', maxLines: 100 },
    { file: 'short-term.md', label: 'Short-term memory (48h rolling)', maxLines: 200 },
  ];

  for (const tier of memoryTiers) {
    const tierPath = path.join(globalMemoryDir, tier.file);
    let content;
    try {
      content = fs.readFileSync(tierPath, 'utf8');
    } catch {
      continue; // File doesn't exist yet
    }

    if (!content || content.includes('No entries yet') || content.includes('No sessions')) {
      continue;
    }

    // Truncate to maxLines to avoid blowing up context
    const lines = content.split('\n');
    const truncated = lines.length > tier.maxLines
      ? lines.slice(0, tier.maxLines).join('\n') + `\n\n... (truncated, ${lines.length - tier.maxLines} more lines in ${tier.file})`
      : content;

    contextParts.push(`${tier.label}:\n${truncated}`);
  }

  return contextParts;
}

module.exports = { loadTieredMemory };

/*
 * USAGE EXAMPLE — add to your existing session-start hook's main():
 *
 *   const { loadTieredMemory } = require('./session-start-patch');
 *   const claudeDir = path.join(process.env.HOME, '.claude');
 *   const memoryParts = loadTieredMemory(claudeDir);
 *   additionalContextParts.push(...memoryParts);
 */
