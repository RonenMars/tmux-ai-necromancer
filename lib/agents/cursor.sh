#!/usr/bin/env bash
# lib/agents/cursor.sh — Cursor Agent CLI adapter for tmux-ai-necromancer.
#
# Cursor keeps one directory per chat at
#   ~/.cursor/chats/<md5(cwd)>/<chat-uuid>/meta.json   (+ store.db, ...)
# so, like Claude, chats are foldered by working directory. meta.json carries
# `hasConversation` (false for an empty chat that was opened and never used).
# Resume is `cursor-agent --resume <chat-uuid>`.
#
# The pane's foreground command is NOT distinctive: the CLI re-execs through a
# bundled node, so tmux reports `node` for `agent` / `cursor-agent` panes (and
# for every dev server). Matching on the command name alone would claim all of
# them, so agent_cursor_matches takes the pane id and confirms from the process
# argv (`.../cursor-agent/versions/<v>/index.js`).

CURSOR_UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
CURSOR_CHATS_DIR="$HOME/.cursor/chats"

# agent_cursor_matches <pane_current_command> [pane_id] [pane_pid]
# `cursor-agent` is unambiguous. Any other listed name (default: node, agent)
# only counts when the pane's shell or one of its children runs the Cursor
# bundle; with no pane id the ambiguous names never match.
agent_cursor_matches() {
  local cmd="$1" pane="${2:-}" pane_pid="${3:-}" name cmds listed=1
  cmds="$(necro_tmux_option @necromancer_cursor_commands "cursor-agent node agent")"
  set -f   # see agent_codex_matches: don't pathname-expand the pattern list
  for name in $cmds; do
    # shellcheck disable=SC2254
    case "$cmd" in $name) listed=0; break ;; esac
  done
  set +f
  [ "$listed" = "0" ] || return 1
  [ "$cmd" = "cursor-agent" ] && return 0
  [ -n "$pane" ] || return 1
  local pid
  [ -n "$pane_pid" ] || pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)"
  [ -n "$pane_pid" ] || return 1
  for pid in "$pane_pid" $(pgrep -P "$pane_pid" 2>/dev/null); do
    # '+' in stat = foreground process group: a Cursor left running with `&`
    # in a pane whose foreground is another node process must not match.
    ps -o stat=,command= -p "$pid" 2>/dev/null \
      | grep -qE '^ *[^ ]*\+ .*/cursor-agent/versions/' && return 0
  done
  return 1
}

agent_cursor_project_dir() {
  printf '%s' "$CURSOR_CHATS_DIR"
}

# Cursor names the per-cwd folder md5(process.cwd()), and Node's process.cwd()
# is the PHYSICAL path, so a symlinked cwd must be resolved first; a missing
# dir falls back to the path as given.
_cursor_cwd_hash() {
  local phys
  phys="$(cd -P "$1" 2>/dev/null && pwd -P)" || phys="$1"
  printf '%s' "$phys" | { md5 -q 2>/dev/null || md5sum | cut -d' ' -f1; }
}

agent_cursor_latest_session_id() {
  agent_cursor_all_session_ids "$1" | head -1
}

# All resumable chat ids for a cwd, newest-first. Optional 2nd arg min_epoch:
# only chats whose meta.json was written at or after it (see docs/agents.md).
agent_cursor_all_session_ids() {
  local cwd="$1" min_epoch="${2:-}" dir meta mtime
  dir="$CURSOR_CHATS_DIR/$(_cursor_cwd_hash "$cwd")"
  [ -d "$dir" ] || return 0
  while IFS= read -r meta; do
    [ -n "$meta" ] || continue
    grep -q '"hasConversation":false' "$meta" 2>/dev/null && continue
    if [ -n "$min_epoch" ]; then
      mtime="$(necro_file_mtime "$meta")"
      [ -n "$mtime" ] && [ "$mtime" -lt "$min_epoch" ] && continue
    fi
    basename "$(dirname "$meta")"
  done < <(/bin/ls -t "$dir"/*/meta.json 2>/dev/null)
}

# No resume hint is printed on exit that we can rely on.
agent_cursor_scrape_session_id() {
  return 0
}

# Ground truth from argv: `agent --resume <uuid>` (or `--resume=<uuid>`). A fresh
# chat has no id in argv — return "" and let the cursor-pop fallback pin it.
agent_cursor_scrape_ps_resume() {
  local pane="$1" pane_pid child
  pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)"
  [ -n "$pane_pid" ] || return 0
  for child in "$pane_pid" $(pgrep -P "$pane_pid" 2>/dev/null); do
    ps -o command= -p "$child" 2>/dev/null
  done | grep -oE -- "--resume[=[:space:]]+$CURSOR_UUID_RE" \
    | grep -oE "$CURSOR_UUID_RE" \
    | head -1
}

agent_cursor_resume_cmd() {
  printf 'cursor-agent --resume %s' "$1"
}

# No agent_cursor_exit_keys on purpose: Cursor's quit command is unverified and
# a guessed `/quit` typed into a live chat could be sent as a prompt. The
# dispatcher then sends nothing and the interactive capture falls back to the
# filesystem id (see necro_agent_exit_keys).
