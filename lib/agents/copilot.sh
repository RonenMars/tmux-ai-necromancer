#!/usr/bin/env bash
# lib/agents/copilot.sh — GitHub Copilot CLI adapter for tmux-ai-necromancer.
#
# Copilot keeps one folder per session at
#   ~/.copilot/session-state/<uuid>/
# holding workspace.yaml (`id:` and `cwd:`, the PHYSICAL path it ran in) and,
# once the first prompt is sent, events.jsonl. A session that was only opened
# has no events.jsonl and nothing to resume, so it is never a candidate.
# Resume is `copilot --resume <uuid>`; a running session's argv carries it.
#
# The native binary shows up as `copilot` in #{pane_current_command}. An npm
# install runs through node and is not detected (set
# @necromancer_copilot_commands if your wrapper has another name).

COPILOT_UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
COPILOT_SESSIONS_DIR="$HOME/.copilot/session-state"

# agent_copilot_matches <pane_current_command>
# Globs from @necromancer_copilot_commands (default "copilot"), as codex does.
agent_copilot_matches() {
  local cmd="$1" name cmds matched=1
  cmds="$(necro_tmux_option @necromancer_copilot_commands "copilot")"
  set -f   # see agent_codex_matches: don't pathname-expand the pattern list
  for name in $cmds; do
    # shellcheck disable=SC2254
    case "$cmd" in $name) matched=0; break ;; esac
  done
  set +f
  return "$matched"
}

agent_copilot_project_dir() {
  printf '%s' "$COPILOT_SESSIONS_DIR"
}

agent_copilot_latest_session_id() {
  agent_copilot_all_session_ids "$1" | head -1
}

# All resumable session ids for a cwd, newest-first. Optional 2nd arg
# min_epoch: only sessions whose events.jsonl was written at or after it.
# Bounded to the 200 most recently written sessions.
agent_copilot_all_session_ids() {
  local cwd="$1" min_epoch="${2:-}" phys ev mtime dir recorded
  phys="$(cd -P "$cwd" 2>/dev/null && pwd -P)" || phys="$cwd"
  [ -d "$COPILOT_SESSIONS_DIR" ] || return 0
  while IFS= read -r ev; do
    [ -n "$ev" ] || continue
    if [ -n "$min_epoch" ]; then
      mtime="$(necro_file_mtime "$ev")"
      [ -n "$mtime" ] && [ "$mtime" -lt "$min_epoch" ] && continue
    fi
    dir="$(dirname "$ev")"
    recorded="$(sed -n 's/^cwd: *//p' "$dir/workspace.yaml" 2>/dev/null | head -1)"
    recorded="${recorded#\"}"; recorded="${recorded%\"}"
    if [ "$recorded" = "$cwd" ] || [ "$recorded" = "$phys" ]; then
      basename "$dir"
    fi
  done < <(/bin/ls -t "$COPILOT_SESSIONS_DIR"/*/events.jsonl 2>/dev/null | head -200)
}

# No resume hint is printed on exit that we rely on.
agent_copilot_scrape_session_id() {
  return 0
}

# Ground truth from argv: `copilot --resume <uuid>` (or `--resume=<uuid>`). A
# fresh session has no id in argv — return "" and let the cursor-pop fallback
# pin it.
agent_copilot_scrape_ps_resume() {
  local pane="$1" pane_pid child
  pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)"
  [ -n "$pane_pid" ] || return 0
  for child in "$pane_pid" $(pgrep -P "$pane_pid" 2>/dev/null); do
    ps -o command= -p "$child" 2>/dev/null
  done | grep -oE -- "--resume[=[:space:]]+$COPILOT_UUID_RE" \
    | grep -oE "$COPILOT_UUID_RE" \
    | head -1
}

agent_copilot_resume_cmd() {
  printf 'copilot --resume %s' "$1"
}

# No agent_copilot_exit_keys on purpose: Copilot's quit command is unverified
# here, so interactive capture sends nothing and records the filesystem id
# (see necro_agent_exit_keys and the no-exit-keys branch of necro-snapshot.sh).
