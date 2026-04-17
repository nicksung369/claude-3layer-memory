#!/usr/bin/env python3
"""
claude-3layer-memory viewer
Single-file, stdlib-only HTTP server that shows every memory tier + auto-memory
as a searchable, auto-refreshing dashboard.

    python3 server.py            # default port 37777, scan default dirs
    python3 server.py --port 8080
    python3 server.py --dir ~/.claude/memory/global --dir ~/.claude/projects
"""
import argparse
import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HOME = Path(os.path.expanduser("~"))
DEFAULT_DIRS = [
    HOME / ".claude" / "memory" / "global",
    HOME / ".claude" / "projects",
]
DEFAULT_SCRIPTS_DIR = HOME / ".claude" / "scripts" / "memory"

# Fixed action → script map. No user-supplied paths reach subprocess.
ACTIONS = {
    "aggregate": "aggregate-short-term.sh",
    "medium":    "promote-to-medium.sh",
    "long":      "promote-to-long.sh",
}
ACTION_TIMEOUT_SEC = 60

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)


def parse_frontmatter(text):
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta, m.group(2)


def scan(dirs):
    memories = []
    for d in dirs:
        if not d.exists():
            continue
        for path in sorted(d.rglob("*.md")):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            meta, body = parse_frontmatter(text)
            rel = path.relative_to(d) if d in path.parents or path.parent == d else path.name
            memories.append({
                "path": str(path),
                "rel": str(rel),
                "root": str(d),
                "name": meta.get("name") or path.stem,
                "description": meta.get("description", ""),
                "type": meta.get("type", _infer_type(path)),
                "mtime": path.stat().st_mtime,
                "size": len(body),
                "preview": body.strip()[:280],
            })
    memories.sort(key=lambda m: m["mtime"], reverse=True)
    return memories


def _infer_type(path):
    stem = path.stem.lower()
    if stem in {"short-term", "medium-term", "long-term"}:
        return stem
    if stem == "memory":
        return "index"
    return "auto"


PAGE = r"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>Claude Memory Viewer</title>
<style>
  :root {
    --bg: #0f1115; --panel: #161922; --border: #262b36; --text: #e6e9ef;
    --muted: #8b93a7; --accent: #7aa2ff; --green: #5ecf8b; --yellow: #ffcf6a;
    --red: #ff7a90; --purple: #c78bff;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC",
    "Noto Sans CJK SC", sans-serif; }
  header { padding: 18px 24px; border-bottom: 1px solid var(--border);
    display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
  header h1 { margin: 0; font-size: 18px; font-weight: 600; letter-spacing: .3px; }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
    background: var(--green); margin-right: 6px; animation: pulse 2s infinite; }
  @keyframes pulse { 0%,100% { opacity: 1 } 50% { opacity: .35 } }
  .stats { color: var(--muted); font-size: 13px; }
  .search { flex: 1; min-width: 240px; }
  .search input { width: 100%; padding: 8px 12px; border-radius: 6px;
    border: 1px solid var(--border); background: var(--panel); color: var(--text);
    font-size: 14px; outline: none; }
  .search input:focus { border-color: var(--accent); }
  .controls { padding: 10px 24px; display: none; gap: 8px; flex-wrap: wrap;
    border-bottom: 1px solid var(--border); align-items: center; }
  .controls.on { display: flex; }
  .controls button { padding: 6px 12px; border-radius: 6px; border: 1px solid var(--border);
    background: var(--panel); color: var(--text); font-size: 13px; cursor: pointer; }
  .controls button:hover { border-color: var(--accent); }
  .controls button:disabled { opacity: .5; cursor: not-allowed; }
  .controls .label { color: var(--muted); font-size: 12px; margin-right: 4px; }
  .runlog { margin-left: auto; color: var(--muted); font-size: 12px;
    font-family: ui-monospace, monospace; max-width: 60%; overflow: hidden;
    text-overflow: ellipsis; white-space: nowrap; }
  .runlog.ok { color: var(--green); }
  .runlog.err { color: var(--red); }
  .tabs { padding: 12px 24px; display: flex; gap: 8px; flex-wrap: wrap;
    border-bottom: 1px solid var(--border); }
  .tab { padding: 6px 12px; border-radius: 999px; background: var(--panel);
    border: 1px solid var(--border); color: var(--muted); font-size: 13px;
    cursor: pointer; user-select: none; }
  .tab.active { color: var(--text); border-color: var(--accent); }
  .tab .count { color: var(--muted); margin-left: 6px; }
  main { padding: 18px 24px; display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 12px; }
  .card { background: var(--panel); border: 1px solid var(--border); border-radius: 10px;
    padding: 14px 16px; cursor: pointer; transition: border-color .15s, transform .15s; }
  .card:hover { border-color: var(--accent); transform: translateY(-1px); }
  .card .title { font-weight: 600; font-size: 14px; margin-bottom: 4px; }
  .card .desc { color: var(--muted); font-size: 13px; line-height: 1.45;
    display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
  .card .foot { margin-top: 10px; display: flex; gap: 8px; align-items: center;
    font-size: 11px; color: var(--muted); }
  .badge { padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 500; }
  .b-user    { background: rgba(122,162,255,.15); color: var(--accent); }
  .b-feedback{ background: rgba(255,207,106,.15); color: var(--yellow); }
  .b-project { background: rgba(94,207,139,.15); color: var(--green); }
  .b-reference { background: rgba(199,139,255,.15); color: var(--purple); }
  .b-short-term { background: rgba(255,122,144,.15); color: var(--red); }
  .b-medium-term { background: rgba(255,207,106,.15); color: var(--yellow); }
  .b-long-term { background: rgba(94,207,139,.15); color: var(--green); }
  .b-auto, .b-index { background: rgba(139,147,167,.18); color: var(--muted); }
  .modal { position: fixed; inset: 0; background: rgba(0,0,0,.55);
    display: none; align-items: flex-start; justify-content: center;
    padding: 60px 24px; overflow-y: auto; }
  .modal.open { display: flex; }
  .modal .body { background: var(--panel); border: 1px solid var(--border); border-radius: 12px;
    max-width: 880px; width: 100%; padding: 24px 28px; }
  .modal h2 { margin: 0 0 6px; font-size: 20px; }
  .modal .path { color: var(--muted); font-size: 12px; font-family: ui-monospace, monospace;
    margin-bottom: 16px; word-break: break-all; }
  .modal pre { background: var(--bg); border: 1px solid var(--border); padding: 14px;
    border-radius: 8px; white-space: pre-wrap; word-wrap: break-word; font-size: 13px;
    line-height: 1.55; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  .modal .close { float: right; background: none; border: 1px solid var(--border);
    border-radius: 6px; color: var(--text); padding: 4px 10px; cursor: pointer; }
  .empty { grid-column: 1/-1; text-align: center; color: var(--muted); padding: 60px 0; }
</style>
</head>
<body>
<header>
  <h1><span class="dot"></span>Claude Memory Viewer</h1>
  <div class="stats" id="stats">loading…</div>
  <div class="search"><input id="q" placeholder="搜索 / Search name · description · content" autofocus></div>
</header>
<div class="controls" id="controls">
  <span class="label">Run:</span>
  <button data-action="aggregate">aggregate-short-term</button>
  <button data-action="medium">promote → medium</button>
  <button data-action="long">promote → long</button>
  <span class="runlog" id="runlog"></span>
</div>
<div class="tabs" id="tabs"></div>
<main id="grid"></main>
<div class="modal" id="modal" onclick="if(event.target===this)close_()">
  <div class="body">
    <button class="close" onclick="close_()">ESC</button>
    <h2 id="m-title"></h2>
    <div class="path" id="m-path"></div>
    <pre id="m-body"></pre>
  </div>
</div>
<script>
let all = [], currentType = "all", q = "";

async function load() {
  const r = await fetch("/api/memories");
  const data = await r.json();
  all = data.memories;
  document.getElementById("stats").textContent =
    `${all.length} memories · updated ${timeAgo(data.latest_mtime)}`;
  renderTabs(); renderGrid();
}

function timeAgo(ts) {
  if (!ts) return "—";
  const s = Math.floor(Date.now()/1000 - ts);
  if (s < 60) return s + "s ago";
  if (s < 3600) return Math.floor(s/60) + "m ago";
  if (s < 86400) return Math.floor(s/3600) + "h ago";
  return Math.floor(s/86400) + "d ago";
}

function renderTabs() {
  const counts = {all: all.length};
  for (const m of all) counts[m.type] = (counts[m.type]||0)+1;
  const order = ["all","user","feedback","project","reference","short-term","medium-term","long-term","auto","index"];
  const tabs = document.getElementById("tabs");
  tabs.innerHTML = "";
  for (const t of order) {
    if (t !== "all" && !counts[t]) continue;
    const el = document.createElement("div");
    el.className = "tab" + (currentType===t?" active":"");
    el.innerHTML = t + ` <span class="count">${counts[t]||0}</span>`;
    el.onclick = () => { currentType = t; renderTabs(); renderGrid(); };
    tabs.appendChild(el);
  }
}

function renderGrid() {
  const grid = document.getElementById("grid");
  grid.innerHTML = "";
  const ql = q.toLowerCase();
  const rows = all.filter(m => {
    if (currentType !== "all" && m.type !== currentType) return false;
    if (!ql) return true;
    return (m.name + " " + m.description + " " + m.preview + " " + m.rel)
      .toLowerCase().includes(ql);
  });
  if (!rows.length) {
    grid.innerHTML = '<div class="empty">没有匹配的记忆</div>';
    return;
  }
  for (const m of rows) {
    const card = document.createElement("div");
    card.className = "card";
    card.onclick = () => open_(m);
    card.innerHTML =
      `<div class="title">${esc(m.name)}</div>` +
      `<div class="desc">${esc(m.description || m.preview)}</div>` +
      `<div class="foot"><span class="badge b-${esc(m.type)}">${esc(m.type)}</span>` +
      `<span>${timeAgo(m.mtime)}</span><span>·</span><span>${esc(m.rel)}</span></div>`;
    grid.appendChild(card);
  }
}

async function open_(m) {
  const r = await fetch("/api/memory?path=" + encodeURIComponent(m.path));
  const data = await r.json();
  document.getElementById("m-title").textContent = m.name;
  document.getElementById("m-path").textContent = m.path;
  document.getElementById("m-body").textContent = data.content;
  document.getElementById("modal").classList.add("open");
}
function close_() { document.getElementById("modal").classList.remove("open"); }

function esc(s) { return String(s).replace(/[&<>"']/g,
  c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }

document.getElementById("q").addEventListener("input", e => { q = e.target.value; renderGrid(); });
document.addEventListener("keydown", e => { if (e.key === "Escape") close_(); });

async function setupControls() {
  const r = await fetch("/api/config");
  const cfg = await r.json();
  if (!cfg.controls_enabled) return;
  const bar = document.getElementById("controls");
  bar.classList.add("on");
  bar.querySelectorAll("button").forEach(b => b.addEventListener("click", () => runAction(b)));
}
async function runAction(btn) {
  const action = btn.dataset.action;
  const log = document.getElementById("runlog");
  document.querySelectorAll("#controls button").forEach(b => b.disabled = true);
  log.className = "runlog"; log.textContent = `running ${action}…`;
  try {
    const r = await fetch("/api/run", {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({action})
    });
    const d = await r.json();
    if (r.ok && d.returncode === 0) {
      log.className = "runlog ok";
      log.textContent = `✓ ${action} (rc=0)  ${(d.stdout||'').split('\n').slice(-1)[0]}`;
    } else {
      log.className = "runlog err";
      log.textContent = `✗ ${action} rc=${d.returncode ?? '?'}  ${(d.stderr||d.error||'').split('\n')[0]}`;
    }
  } catch (e) {
    log.className = "runlog err";
    log.textContent = `✗ ${action}: ${e}`;
  } finally {
    document.querySelectorAll("#controls button").forEach(b => b.disabled = false);
    load();
  }
}

setupControls();
load();
setInterval(load, 3000);  // live refresh every 3s
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    dirs = []
    scripts_dir = DEFAULT_SCRIPTS_DIR
    controls_enabled = False

    def log_message(self, *args, **kw):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            body = PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if u.path == "/api/config":
            return self._json({
                "controls_enabled": self.controls_enabled,
                "actions": sorted(ACTIONS.keys()) if self.controls_enabled else [],
            })
        if u.path == "/api/memories":
            memories = scan(self.dirs)
            latest = max((m["mtime"] for m in memories), default=None)
            return self._json({"memories": memories, "latest_mtime": latest})
        if u.path == "/api/memory":
            qs = parse_qs(u.query)
            raw = qs.get("path", [""])[0]
            if not raw:
                return self._json({"error": "not found"}, 404)
            try:
                path = Path(raw).resolve(strict=True)
            except (OSError, RuntimeError):
                return self._json({"error": "not found"}, 404)
            # Directory containment check — NOT string prefix. Prefix is unsafe
            # because "/a/demo_evil.md" startswith("/a/demo") is True.
            allowed = False
            for d in self.dirs:
                try:
                    path.relative_to(Path(d).resolve())
                    allowed = True
                    break
                except ValueError:
                    continue
            if not allowed or not path.is_file():
                return self._json({"error": "not found"}, 404)
            return self._json({"content": path.read_text(encoding="utf-8", errors="replace")})
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path != "/api/run":
            return self._json({"error": "not found"}, 404)
        if not self.controls_enabled:
            return self._json({"error": "controls disabled; restart with --enable-controls"}, 403)
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            return self._json({"error": "invalid json"}, 400)
        action = payload.get("action")
        script_name = ACTIONS.get(action)
        if not script_name:
            return self._json({"error": f"unknown action: {action!r}"}, 400)
        script_path = (self.scripts_dir / script_name).resolve()
        if not script_path.is_file() or not os.access(script_path, os.X_OK):
            return self._json({"error": f"script not found or not executable: {script_path}"}, 500)
        try:
            result = subprocess.run(
                [str(script_path)],
                capture_output=True, text=True,
                timeout=ACTION_TIMEOUT_SEC, check=False,
            )
        except subprocess.TimeoutExpired:
            return self._json({"error": f"script timed out after {ACTION_TIMEOUT_SEC}s"}, 504)
        return self._json({
            "action": action,
            "returncode": result.returncode,
            "stdout": result.stdout[-4000:],
            "stderr": result.stderr[-4000:],
        })


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("MEMORY_VIEWER_PORT", 37777)))
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--dir", action="append", default=None,
                    help="memory directory to scan (repeatable). Default: ~/.claude/memory/global and ~/.claude/projects")
    ap.add_argument("--scripts-dir", default=str(DEFAULT_SCRIPTS_DIR),
                    help="location of aggregate/promote shell scripts (used by --enable-controls)")
    ap.add_argument("--enable-controls", action="store_true",
                    help="expose POST /api/run so the UI can trigger aggregate/promote scripts. "
                         "127.0.0.1-only. Off by default.")
    args = ap.parse_args()

    dirs = [Path(os.path.expanduser(d)) for d in (args.dir or [])] or DEFAULT_DIRS
    Handler.dirs = dirs
    Handler.scripts_dir = Path(os.path.expanduser(args.scripts_dir))
    Handler.controls_enabled = args.enable_controls
    if args.enable_controls and args.host not in ("127.0.0.1", "localhost", "::1"):
        print(f"[viewer] refusing to enable controls on non-loopback host {args.host!r}", file=sys.stderr)
        sys.exit(2)
    existing = [d for d in dirs if d.exists()]
    if not existing:
        print(f"[viewer] no memory dirs found in {[str(d) for d in dirs]}", file=sys.stderr)
        sys.exit(1)
    print(f"[viewer] scanning: {', '.join(str(d) for d in existing)}")
    if args.enable_controls:
        print(f"[viewer] controls ENABLED; scripts dir: {Handler.scripts_dir}")
    print(f"[viewer] open http://{args.host}:{args.port}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
