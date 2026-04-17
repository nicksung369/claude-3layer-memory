# openclaw-3layer-memory

Three-layer memory automation for [OpenClaw](https://openclaw.dev) agents. Adds a **medium-term** memory layer and automated promotion to the existing daily memory + MEMORY.md system.

## How OpenClaw Memory Already Works

OpenClaw agents read these files on session startup (defined in AGENTS.md):

```
SOUL.md                    → Agent identity (always)
USER.md                    → User metadata (always)
memory/YYYY-MM-DD.md       → Today + yesterday (short-term)
MEMORY.md                  → Permanent knowledge (main session only)
```

**The gap:** There's no automated way to:
- Clean up old daily memory files
- Extract and aggregate recurring patterns into a digest
- Promote important items to MEMORY.md over time

This skill fills that gap.

## Architecture

```
┌──────────────┐  every 6h   ┌──────────────┐
│ memory/       │ ──────────> │  Cleanup old  │
│ YYYY-MM-DD.md │  (prune)    │  (>48h files) │
└──────────────┘             └──────┬───────┘
                                    │ every 48h (text extraction)
                                    v
                             ┌──────────────┐
                             │ medium-term.md│
                             │ (2-week digest)│
                             └──────┬───────┘
                                    │ every 2 weeks (keyword extraction)
                                    v
                             ┌──────────────┐
                             │  MEMORY.md    │
                             │  (permanent)  │
                             └──────────────┘
```

| Layer | Window | Updates | File |
|-------|--------|---------|------|
| **Short-term** | 48h | Agent writes daily | `memory/YYYY-MM-DD.md` (existing) |
| **Medium-term** | 2 weeks | Every 48h (cron) | `memory/medium-term.md` (new) |
| **Long-term** | Permanent | Every 2 weeks (cron) | `MEMORY.md` (existing, appended) |

### Zero Dependencies

No AI API calls. All extraction is done via `grep`, `sed`, and `sort`. Just bash + cron.

## Installation

### Quick Start (inside container)

```bash
git clone https://github.com/nicksung369/claude-3layer-memory.git
cd claude-3layer-memory/openclaw
./install.sh --with-cron
```

### Docker (from host machine)

```bash
# Install into a Docker container
./install.sh --docker <container_name> --with-cron
```

### Custom workspace path

```bash
./install.sh --workspace /opt/openclaw/data/workspace --with-cron
```

### SSH to remote host

```bash
# Copy files to remote host first, then run
scp -r openclaw/ root@<host>:/tmp/openclaw-memory/
ssh root@<host> "cd /tmp/openclaw-memory && ./install.sh --with-cron"
```

### Manual (without cron)

```bash
./install.sh
# Prints cron commands for manual setup
```

### Web Viewer (optional)

The main repo's viewer works against OpenClaw workspaces out of the box. Point it
at `<workspace>/memory`:

```bash
python3 ../viewer/server.py --dir /root/.openclaw/workspace/memory
# open http://127.0.0.1:37777
```

Inside a Docker container, bind the viewer to the container's loopback and
forward the port to your host's loopback — **never** bind to `0.0.0.0`
unless you truly want the workspace memory exposed to every host on the
network:

```bash
# Publish container's 37777 only to the host's loopback
docker run -p 127.0.0.1:37777:37777 ... openclaw
# Inside the container, the viewer still binds to 127.0.0.1 (default)
docker exec <container> python3 /path/to/viewer/server.py
```

If the container's process namespace makes loopback-inside-loopback awkward,
bind to a link-local address like `--host 127.0.0.2` instead of `0.0.0.0`.

## What Gets Installed

```
/opt/openclaw-memory/
└── scripts/
    ├── aggregate-short-term.sh    # Prune old daily files (>48h → archive)
    ├── promote-to-medium.sh       # Daily files → medium-term.md
    └── promote-to-long.sh         # medium-term.md → MEMORY.md

<workspace>/memory/
├── YYYY-MM-DD.md                  # Daily memories (agent writes these)
├── medium-term.md                 # 2-week digest (NEW - this skill adds it)
├── archive/                       # Archived old files
└── cron.log                       # Automation logs
```

## Cron Schedule

| Schedule | Script | Action |
|----------|--------|--------|
| `0 */6 * * *` | `aggregate-short-term.sh` | Archive daily files older than 48h |
| `0 3 * * 1,4` | `promote-to-medium.sh` | Extract daily → medium-term.md |
| `0 4 1,15 * *` | `promote-to-long.sh` | Extract medium → MEMORY.md |

## Making Agents Read medium-term.md

The agent already reads `memory/YYYY-MM-DD.md` on startup. To also load `medium-term.md`, add this line to your AGENTS.md startup sequence:

```markdown
## Session Startup

Before doing anything else:

1. Read `SOUL.md`
2. Read `USER.md`
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. Read `memory/medium-term.md` if it exists — 2-week digest     ← ADD THIS
5. **If in MAIN SESSION**: Also read `MEMORY.md`
```

Or add it to the agent's SOUL.md under a "Memory" section if you prefer.

## Docker Considerations

Cron inside Docker requires the cron daemon. Add to your Dockerfile:

```dockerfile
RUN apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*
```

And start it in your entrypoint:

```bash
service cron start
exec openclaw gateway --port ${OPENCLAW_GATEWAY_PORT}
```

## Uninstall

```bash
# Inside container
./install.sh --uninstall

# From host
./install.sh --uninstall --docker lobster-dev
```

Removes scripts and cron jobs but preserves memory data.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_WORKSPACE` | `/root/.openclaw/workspace` | Agent workspace path |
| `CUTOFF_HOURS` | `48` | Short-term retention window (hours) |

---

# openclaw-3layer-memory (中文)

为 [OpenClaw](https://openclaw.dev) 智能体打造的三层记忆自动化工具。在现有的"每日记忆 + MEMORY.md"基础上，增加**中期记忆层**和自动晋级机制。

## OpenClaw 现有的记忆机制

OpenClaw 智能体启动时自动读取（定义在 AGENTS.md）：

```
SOUL.md                    → 智能体身份（每次必读）
USER.md                    → 用户信息（每次必读）
memory/YYYY-MM-DD.md       → 当天+昨天（短期记忆）
MEMORY.md                  → 永久知识（仅主会话）
```

**缺失的部分：** 没有自动化机制来：
- 清理过期的每日记忆文件
- 提取和聚合重复出现的模式
- 将重要内容逐步晋级到 MEMORY.md

这个工具填补了这个空缺。

## 架构

```
┌──────────────┐  每6小时    ┌──────────────┐
│ memory/       │ ──────────> │   清理旧文件   │
│ YYYY-MM-DD.md │  (归档)     │  (>48h归档)   │
└──────────────┘             └──────┬───────┘
                                    │ 每48小时 (文本提取)
                                    v
                             ┌──────────────┐
                             │ medium-term.md│
                             │  (2周摘要)     │
                             └──────┬───────┘
                                    │ 每2周 (关键词提取)
                                    v
                             ┌──────────────┐
                             │  MEMORY.md    │
                             │  (永久保存)    │
                             └──────────────┘
```

| 层级 | 时间窗口 | 更新频率 | 文件 |
|------|----------|----------|------|
| **短期** | 48小时 | 智能体每日写入 | `memory/YYYY-MM-DD.md`（已有） |
| **中期** | 2周 | 每48小时 (cron) | `memory/medium-term.md`（新增） |
| **长期** | 永久 | 每2周 (cron) | `MEMORY.md`（已有，追加写入） |

### 零依赖

不需要任何 AI API 调用。所有提取通过 `grep`、`sed`、`sort` 完成。只需 bash + cron。

## 安装

### 快速开始（容器内）

```bash
git clone https://github.com/nicksung369/claude-3layer-memory.git
cd claude-3layer-memory/openclaw
./install.sh --with-cron
```

### Docker（从宿主机）

```bash
# 安装到 Docker 容器
./install.sh --docker <容器名> --with-cron
```

### 自定义工作空间路径

```bash
./install.sh --workspace /opt/openclaw/data/workspace --with-cron
```

### SSH 到远程主机

```bash
# 先把文件拷过去，再安装
scp -r openclaw/ root@<host>:/tmp/openclaw-memory/
ssh root@<host> "cd /tmp/openclaw-memory && ./install.sh --with-cron"
```

## 让智能体读取 medium-term.md

在 AGENTS.md 的启动序列中加一行：

```markdown
## Session Startup

1. Read `SOUL.md`
2. Read `USER.md`
3. Read `memory/YYYY-MM-DD.md` (today + yesterday)
4. Read `memory/medium-term.md` if it exists          ← 加这行
5. **If in MAIN SESSION**: Also read `MEMORY.md`
```

## Docker 注意事项

Docker 容器内需要 cron 守护进程。在 Dockerfile 中添加：

```dockerfile
RUN apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*
```

在 entrypoint 中启动：

```bash
service cron start
exec openclaw gateway --port ${OPENCLAW_GATEWAY_PORT}
```

## 卸载

```bash
# 容器内
./install.sh --uninstall

# 从宿主机
./install.sh --uninstall --docker lobster-dev
```

移除脚本和 cron 任务，但保留记忆数据。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENCLAW_WORKSPACE` | `/root/.openclaw/workspace` | 智能体工作空间路径 |
| `CUTOFF_HOURS` | `48` | 短期记忆保留时间（小时） |
