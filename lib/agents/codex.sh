#!/usr/bin/env bash
# lib/agents/codex.sh — Codex CLI adapter for tmux-ai-necromancer.
#
# Codex stores one "rollout" transcript per session at
#   ~/.codex/sessions/YYYY/MM/DD/rollout-<ISO-ts>-<uuid>.jsonl
# The FIRST line of each rollout is a `session_meta` record carrying both the
# session `id` (UUID) and the `cwd` it ran in. Unlike Claude, sessions are NOT
# foldered by cwd, so the cwd→session mapping is recovered by reading that meta
# line. Resume is `codex resume <uuid>`.

CODEX_UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
CODEX_SESSIONS_DIR="$HOME/.codex/sessions"

# Does this pane's foreground command belong to Codex?
# tmux reports the native binary's truncated basename (e.g. "codex-aarch64-a"
# for codex-aarch64-apple-darwin), not the "codex" wrapper — match that too.
agent_codex_matches() {
  case "$1" in codex|codex-*) return 0 ;; *) return 1 ;; esac
}

# Codex has no per-project dir; report the sessions root for diagnostics.
agent_codex_project_dir() {
  printf '%s' "$CODEX_SESSIONS_DIR"
}

# Most-recent session id for a cwd, by scanning rollout meta lines newest-first.
# Returns "" if none found. Bounded to the 200 most-recent rollouts for speed.
agent_codex_latest_session_id() {
  local cwd="$1"
  agent_codex_all_session_ids "$cwd" | head -1
}

# All session ids for a cwd, newest-first, one per line.
agent_codex_all_session_ids() {
  local cwd="$1"
  [ -d "$CODEX_SESSIONS_DIR" ] || return 0
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    local id
    id="$(head -1 "$f" 2>/dev/null | python3 -c '
import sys, json
try:
    o = json.loads(sys.stdin.readline() or "{}")
except Exception:
    sys.exit(0)
p = o.get("payload", o)
# Codex canonicalizes cwd to lowercase; macOS FS is case-insensitive, so
# compare case-folded (tb-PRs-follow == tb-prs-follow).
if (p.get("cwd") or "").lower() == sys.argv[1].lower():
    sys.stdout.write(p.get("id", ""))
' "$cwd" 2>/dev/null)"
    [ -n "$id" ] && printf '%s\n' "$id"
  done <<EOF
$(/bin/ls -t "$CODEX_SESSIONS_DIR"/*/*/*/rollout-*.jsonl 2>/dev/null | head -200)
EOF
}

# Codex doesn't print a resume farewell line reliably; no scrollback scrape.
agent_codex_scrape_session_id() {
  return 0
}

# Shell command that resumes a given session id.
agent_codex_resume_cmd() {
  printf 'codex resume %s' "$1"
}

# Codex exits cleanly on Ctrl-D / "/quit"; we use /quit for parity.
agent_codex_exit_keys() {
  printf '/quit'
}
