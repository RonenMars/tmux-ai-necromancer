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
necro_init_log "$0"

[ $# -ge 1 ] || { necro_err "Usage: $0 <snapshot.jsonl>"; exit 2; }
IN="$1"
[ -f "$IN" ] || { necro_err "Not found: $IN"; exit 1; }
OUT="${IN%.jsonl}.enriched.jsonl"
necro_log_event "context" "enrich_start" "input=$IN" "output=$OUT"

# Python does the heavy lifting: it knows each agent's transcript layout.
# Writes to a temp file and renames only on success — a partially-written
# enriched file must never be pinned as the reboot target (reboot-prep only
# checks that the file exists).
python3 - "$IN" "$OUT" "$HOME" <<'PY'
import json, os, sys

in_path, out_path, home = sys.argv[1], sys.argv[2], sys.argv[3]
tmp_path = out_path + ".tmp"

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content
                         if isinstance(c, dict) and c.get("type") in ("text", "input_text", "output_text"))
    return ""

def is_real_user(t):
    if not t: return False
    if "<command-" in t or "<local-command" in t: return False
    if t.strip().startswith("/"): return False
    return True

def claude_path(uuid, cwd):
    # Claude encodes '/', '.' and '_' all as '-'. Must match
    # agent_claude_project_dir in lib/agents/claude.sh.
    enc = cwd.replace("/", "-").replace(".", "-").replace("_", "-")
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

skipped = 0
with open(in_path) as fin, open(tmp_path, "w") as fout:
    for line in fin:
        line = line.strip()
        if not line: continue
        # A malformed record must not abort the run: restore tolerates these,
        # so they occur in practice, and a half-written enriched file can be
        # pinned as the reboot target and silently lose every later session.
        try:
            obj = json.loads(line)
        except Exception:
            skipped += 1
            fout.write(line + "\n")  # pass through untouched
            continue
        uuid = obj.get("uuid", ""); cwd = obj.get("cwd", ""); agent = obj.get("agent", "")
        if uuid and cwd and agent:
            fu, la = previews(agent, uuid, cwd)
            obj["first_user"] = fu
            obj["last_assistant"] = la
        fout.write(json.dumps(obj) + "\n")

os.replace(tmp_path, out_path)
if skipped:
    print(f"Warning: passed through {skipped} malformed record(s) unenriched")
print(f"Enriched: {out_path}")
PY
necro_log_event "context" "enrich_complete" "output=$OUT"
