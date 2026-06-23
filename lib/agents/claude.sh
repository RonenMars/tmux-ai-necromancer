#!/usr/bin/env bash
# lib/agents/claude.sh — Claude Code adapter for tmux-ai-necromancer.
#
# Claude Code stores one transcript per conversation as a .jsonl file under
#   ~/.claude/projects/<cwd-with-slashes-as-dashes>/<uuid>.jsonl
# and resumes with `claude --resume <uuid>`. On clean exit it prints a farewell
# line containing `claude --resume <uuid>` which the snapshotter can scrape.

CLAUDE_UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# Does this pane's foreground command belong to Claude Code?
agent_claude_matches() {
  [ "$1" = "claude" ]
}

# Per-project transcript directory for a cwd ("" if none).
agent_claude_project_dir() {
  local cwd="$1"
  printf '%s' "$HOME/.claude/projects/${cwd//\//-}"
}

# Most-recent session id (UUID) for a cwd via filesystem fallback ("" if none).
agent_claude_latest_session_id() {
  local cwd="$1"
  agent_claude_all_session_ids "$cwd" | head -1
}

# All session ids for a cwd, newest-first, one per line.
agent_claude_all_session_ids() {
  local cwd="$1" proj_dir
  proj_dir="$(agent_claude_project_dir "$cwd")"
  [ -d "$proj_dir" ] || return 0
  /bin/ls -t "$proj_dir"/*.jsonl 2>/dev/null \
    | xargs -n1 basename 2>/dev/null \
    | sed -nE "s/^($CLAUDE_UUID_RE)\.jsonl\$/\\1/p"
}

# Scrape a session id from pane scrollback near a "resume" marker ("" if none).
agent_claude_scrape_session_id() {
  local pane="$1"
  tmux capture-pane -p -t "$pane" -S -200 2>/dev/null \
    | grep -iE "resume.*$CLAUDE_UUID_RE|$CLAUDE_UUID_RE.*resume" \
    | tail -1 \
    | grep -oE "$CLAUDE_UUID_RE" \
    | head -1
}

# Shell command that resumes a given session id.
agent_claude_resume_cmd() {
  printf 'claude --resume %s' "$1"
}

# Keys to send for a clean exit when capturing a live session.
agent_claude_exit_keys() {
  printf '/exit'
}
