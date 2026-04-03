# claude-3layer-memory

Three-layer memory system for [Claude Code](https://claude.ai/code) that gives your AI assistant **short-term**, **medium-term**, and **long-term** memory across sessions.

> No more "goldfish memory" — Claude remembers what you worked on yesterday, last week, and last month.

## The Problem

Every time you open a new Claude Code session, it starts fresh with no memory of previous conversations. You end up repeating context, re-explaining decisions, and losing continuity across sessions.

## The Solution

```
┌──────────────┐  every 6h   ┌──────────────┐
│ Session Data  │ ──────────> │  Short-Term   │
│ (*.tmp files) │             │  (48h rolling)│
└──────────────┘             └──────┬───────┘
                                    │ every 48h (text extraction)
                                    v
                             ┌──────────────┐
                             │ Medium-Term   │
                             │ (2-week digest)│
                             └──────┬───────┘
                                    │ every 2 weeks (keyword extraction)
                                    v
                             ┌──────────────┐
                             │  Long-Term    │
                             │ (permanent)   │
                             └──────────────┘
```

### Three Layers

| Layer | Window | Updates | Contains |
|-------|--------|---------|----------|
| **Short-term** | 48 hours | Every 6h (cron) | Raw session summaries from all projects |
| **Medium-term** | 2 weeks | Every 48h (cron) | Extracted tasks, files modified, active projects |
| **Long-term** | Permanent | Every 2 weeks (cron) | Key decisions, infrastructure, patterns |

### Zero Dependencies

No AI API calls needed. All promotion is done via pure text/keyword extraction (`grep`, `sed`). Just bash + cron.

## Installation

### Quick Start

```bash
git clone https://github.com/nicksungallen/claude-3layer-memory.git
cd claude-3layer-memory
./install.sh --with-cron
```

### Manual Install

```bash
# Without cron (prints cron commands for you to add manually)
./install.sh
```

### Hook Setup

To load memories on session start, you need a SessionStart hook. Two options:

**Option A: Standalone hook** (if you don't have an existing session-start hook):
```bash
cp hooks/session-start-standalone.js ~/.claude/scripts/hooks/session-start.js
```

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "node ~/.claude/scripts/hooks/session-start.js"
    }]
  }
}
```

**Option B: Patch existing hook** (if you already have a session-start hook):
```js
const { loadTieredMemory } = require('./session-start-patch');
const claudeDir = path.join(process.env.HOME, '.claude');
const memoryParts = loadTieredMemory(claudeDir);
additionalContextParts.push(...memoryParts);
```

## How It Works

### Session Data Collection

Claude Code's Stop hook writes session summaries to `~/.claude/session-data/`. Each file contains:
- User messages (tasks requested)
- Tools used
- Files modified
- Project and worktree metadata

> **Note:** Session data collection requires a Stop hook. If you're using [ECC (Everything Claude Code)](https://github.com/anthropics/ecc), this is already set up.

### Cron Schedule

| Schedule | Script | Action |
|----------|--------|--------|
| `0 */6 * * *` | `aggregate-short-term.sh` | Collect last 48h of sessions |
| `0 3 * * 1,4` | `promote-to-medium.sh` | Extract short -> medium |
| `0 4 1,15 * *` | `promote-to-long.sh` | Extract medium -> long |

### Memory Loading

On each new session, the SessionStart hook loads memories in order:
1. **Long-term** (up to 150 lines) — permanent knowledge
2. **Medium-term** (up to 100 lines) — recent 2-week digest
3. **Short-term** (up to 200 lines) — last 48h raw summaries

### Archiving

When files exceed size limits, old content is automatically archived to `~/.claude/memory/global/archive/` before pruning.

## File Structure

```
~/.claude/
├── memory/global/
│   ├── short-term.md              # 48h rolling memory
│   ├── medium-term.md             # 2-week digest
│   ├── long-term.md               # Permanent knowledge
│   ├── archive/                   # Archived old entries
│   └── cron.log                   # Automation logs
└── scripts/memory/
    ├── aggregate-short-term.sh    # Session -> short-term
    ├── promote-to-medium.sh       # Short -> medium
    └── promote-to-long.sh         # Medium -> long
```

## Uninstall

```bash
./install.sh --uninstall
```

This removes scripts and cron jobs but preserves your memory data. To fully clean up:

```bash
rm -rf ~/.claude/memory/global
```

## Requirements

- bash, cron
- Claude Code CLI (for the SessionStart hook)

## License

MIT

---

# claude-3layer-memory (中文)

为 [Claude Code](https://claude.ai/code) 打造的三层记忆系统，让你的 AI 编程助手拥有**短期**、**中期**和**长期**记忆。

> 告别"金鱼记忆" —— Claude 能记住你昨天、上周、上个月做过什么。

## 痛点

每次打开新的 Claude Code 会话，它都从零开始，完全不记得之前的对话。你不得不反复重述上下文、重新解释决策，跨会话的工作连续性完全丢失。

## 方案

```
┌──────────────┐  每6小时    ┌──────────────┐
│ 会话数据       │ ──────────> │   短期记忆     │
│ (*.tmp 文件)  │             │ (48小时滚动)   │
└──────────────┘             └──────┬───────┘
                                    │ 每48小时 (文本提取)
                                    v
                             ┌──────────────┐
                             │   中期记忆     │
                             │ (2周摘要)      │
                             └──────┬───────┘
                                    │ 每2周 (关键词提取)
                                    v
                             ┌──────────────┐
                             │   长期记忆     │
                             │  (永久保存)    │
                             └──────────────┘
```

### 三层架构

| 层级 | 时间窗口 | 更新频率 | 内容 |
|------|----------|----------|------|
| **短期** | 48小时 | 每6小时 (cron) | 所有项目的原始会话摘要 |
| **中期** | 2周 | 每48小时 (cron) | 提取的任务、修改的文件、活跃项目 |
| **长期** | 永久 | 每2周 (cron) | 关键决策、基础设施、工作模式 |

### 零依赖

不需要任何 AI API 调用。所有层级提升都通过纯文本/关键词提取完成（`grep`、`sed`）。只需 bash + cron。

## 安装

### 快速开始

```bash
git clone https://github.com/nicksungallen/claude-3layer-memory.git
cd claude-3layer-memory
./install.sh --with-cron
```

### 手动安装

```bash
# 不安装 cron（会打印 cron 命令供你手动添加）
./install.sh
```

### Hook 设置

要在会话启动时加载记忆，需要配置 SessionStart hook。两种方式：

**方式 A：独立 hook**（如果你还没有 session-start hook）：
```bash
cp hooks/session-start-standalone.js ~/.claude/scripts/hooks/session-start.js
```

添加到 `~/.claude/settings.json`：
```json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "node ~/.claude/scripts/hooks/session-start.js"
    }]
  }
}
```

**方式 B：补丁已有 hook**（如果你已经有 session-start hook）：
```js
const { loadTieredMemory } = require('./session-start-patch');
const claudeDir = path.join(process.env.HOME, '.claude');
const memoryParts = loadTieredMemory(claudeDir);
additionalContextParts.push(...memoryParts);
```

## 工作原理

### 会话数据采集

Claude Code 的 Stop hook 在每次会话结束时将摘要写入 `~/.claude/session-data/`，包含：
- 用户消息（请求的任务）
- 使用的工具
- 修改的文件
- 项目和工作目录元数据

> **注意：** 会话数据采集需要 Stop hook。如果你使用的是 [ECC (Everything Claude Code)](https://github.com/anthropics/ecc)，这已经内置了。

### Cron 调度

| 调度 | 脚本 | 动作 |
|------|------|------|
| `0 */6 * * *` | `aggregate-short-term.sh` | 聚合最近48小时的会话 |
| `0 3 * * 1,4` | `promote-to-medium.sh` | 短期 -> 中期提取 |
| `0 4 1,15 * *` | `promote-to-long.sh` | 中期 -> 长期提取 |

### 记忆加载

每次新会话启动时，SessionStart hook 按顺序加载：
1. **长期记忆**（最多150行）—— 永久知识
2. **中期记忆**（最多100行）—— 最近2周摘要
3. **短期记忆**（最多200行）—— 最近48小时原始摘要

### 归档

当文件超过大小限制时，旧内容会自动归档到 `~/.claude/memory/global/archive/`。

## 文件结构

```
~/.claude/
├── memory/global/
│   ├── short-term.md              # 48小时滚动记忆
│   ├── medium-term.md             # 2周摘要
│   ├── long-term.md               # 永久知识
│   ├── archive/                   # 归档的旧记录
│   └── cron.log                   # 自动化日志
└── scripts/memory/
    ├── aggregate-short-term.sh    # 会话 -> 短期
    ├── promote-to-medium.sh       # 短期 -> 中期
    └── promote-to-long.sh         # 中期 -> 长期
```

## 卸载

```bash
./install.sh --uninstall
```

这会移除脚本和 cron 任务，但保留记忆数据。完全清理：

```bash
rm -rf ~/.claude/memory/global
```

## 依赖

- bash, cron
- Claude Code CLI（用于 SessionStart hook）

## 许可证

MIT
