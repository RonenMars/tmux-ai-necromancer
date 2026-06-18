#!/usr/bin/env bash
# necro-context.sh — enrich a snapshot with first-user / last-assistant previews.
#
# Reads a snapshot .jsonl, looks up each record's transcript (per-agent) and
# fills first_user + last_assistant. Writes <snapshot>.enriched.jsonl.
#
# Usage: necro-context.sh <snapshot.jsonl>
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SELF_DIR/../lib/common.sh"

[ $# -ge 1 ] || { necro_err "Usage: $0 <snapshot.jsonl>"; exit 2; }
IN="$1"
[ -f "$IN" ] || { necro_err "Not found: $IN"; exit 1; }
OUT="${IN%.jsonl}.enriched.jsonl"

# Python does the heavy lifting: it knows each agent's transcript layout.
python3 - "$IN" "$OUT" "$HOME" <<'PY'
import json, os, sys

in_path, out_path, home = sys.argv[1], sys.argv[2], sys.argv[3]

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content
                         if isinstance(c, dict) and c.get("type") == "text")
    return ""

def is_real_user(t):
    if not t: return False
    if "<command-" in t or "<local-command" in t: return False
    if t.strip().startswith("/"): return False
    return True

def claude_path(uuid, cwd):
    enc = cwd.replace("/", "-")
    return os.path.join(home, ".claude", "projects", enc, f"{uuid}.jsonl")

def codex_path(uuid, cwd):
    # Codex rollouts are date-nested; find the file whose name ends with the uuid.
    root = os.path.join(home, ".codex", "sessions")
    if not os.path.isdir(root): return None
    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if fn.endswith(f"-{uuid}.jsonl"):
                return os.path.join(dirpath, fn)
    return None

def previews(agent, uuid, cwd):
    path = None
    if agent == "claude":
        path = claude_path(uuid, cwd)
    elif agent == "codex":
        path = codex_path(uuid, cwd)
    if not path or not os.path.exists(path):
        return "", ""
    first_user = last_assistant = ""
    try:
        with open(path) as f:
            for line in f:
                try: obj = json.loads(line)
                except Exception: continue
                # Claude: {message:{role,content}}. Codex: {payload:{role,content}}.
                msg = obj.get("message") or obj.get("payload") or {}
                role = msg.get("role")
                content = text_of(msg.get("content"))
                if role == "user" and not first_user and is_real_user(content):
                    first_user = content[:240].replace("\n", " ").strip()
                if role == "assistant" and content:
                    last_assistant = content[:240].replace("\n", " ").strip()
    except Exception:
        return "", ""
    return first_user, last_assistant

with open(in_path) as fin, open(out_path, "w") as fout:
    for line in fin:
        line = line.strip()
        if not line: continue
        obj = json.loads(line)
        uuid = obj.get("uuid", ""); cwd = obj.get("cwd", ""); agent = obj.get("agent", "")
        if uuid and cwd and agent:
            fu, la = previews(agent, uuid, cwd)
            obj["first_user"] = fu
            obj["last_assistant"] = la
        fout.write(json.dumps(obj) + "\n")

print(f"Enriched: {out_path}")
PY
