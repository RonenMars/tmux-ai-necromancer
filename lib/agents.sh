#!/usr/bin/env bash
# lib/agents.sh — agent adapter registry + dispatch for tmux-ai-necromancer.
#
# Sources every adapter in lib/agents/ and provides a uniform front-end so the
# scripts never hardcode a specific agent. Adding an agent = drop a new file in
# lib/agents/<name>.sh implementing the contract (see docs/agents.md) and add
# its name to @necromancer_agents. Only listed agents are sourced — an adapter
# file that isn't named in that option is never loaded.
#
# Requires lib/common.sh to be sourced first (for LIB_DIR + necro_tmux_option).

# Which agents are enabled. Override with `set -g @necromancer_agents "claude codex"`.
necro_enabled_agents() {
  necro_tmux_option @necromancer_agents "claude codex"
}

# Source all adapter files for the enabled agents. Idempotent.
necro_load_agents() {
  local name
  for name in $(necro_enabled_agents); do
    local f="$LIB_DIR/agents/${name}.sh"
    if [ -f "$f" ]; then
      necro_log_event "agents" "load_adapter" "agent=$name"
      # shellcheck disable=SC1090
      . "$f"
    else
      necro_log_event "agents" "missing_adapter" "agent=$name"
      necro_warn "agent adapter not found: $f (skipping '$name')"
    fi
  done
}

# Given a pane's foreground command, echo the matching agent name ("" if none).
necro_agent_for_cmd() {
  local cmd="$1" name
  for name in $(necro_enabled_agents); do
    if declare -f "agent_${name}_matches" >/dev/null 2>&1; then
      if "agent_${name}_matches" "$cmd"; then
        printf '%s' "$name"
        return 0
      fi
    fi
  done
  return 0
}

# Echo the agent name if an agent process is still alive among the pane's child
# processes, "" otherwise. Unlike pane_current_command (the tty foreground pgrp
# leader), this sees the agent even when it is SUSPENDED — e.g. codex honors
# Ctrl-Z and stops (state T), which flips pane_current_command to the shell
# while the codex process is still very much alive as a pane child. The watcher
# uses this to tell a suspend (agent alive, don't mark exited) from a real exit
# (no agent child). Same pgrep -P pane_pid probe the *_scrape_ps_resume
# adapters already use.
necro_agent_alive_in_pane() {
  local pane="$1" pane_pid child ccmd agent
  pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)"
  [ -n "$pane_pid" ] || return 0
  for child in $(pgrep -P "$pane_pid" 2>/dev/null); do
    ccmd="$(ps -o comm= -p "$child" 2>/dev/null)"
    ccmd="${ccmd##*/}"  # basename — ps may print a full path
    agent="$(necro_agent_for_cmd "$ccmd")"
    if [ -n "$agent" ]; then
      printf '%s' "$agent"
      return 0
    fi
  done
  return 0
}

# --- Per-cwd UUID cursor ----------------------------------------------------
# File-based cursor so state survives subshell boundaries (command substitution
# forks a subshell; writes to an in-memory array would be lost on return).
# Cursor files live in $NECRO_CURSOR_DIR (set by the snapshot script before sourcing).
# Usage: necro_agent_pop_session_id "$agent" "$cwd" ["$min_epoch"] — prints
# next unused UUID. When min_epoch is given, candidates are pre-filtered to
# transcripts created at or after that time (see agent_<name>_all_session_ids)
# so a stale/unrelated session from days ago can't be handed to a pane that
# didn't exist yet when it was written.
#
# The cursor records WHICH ids were handed out, not HOW MANY. A positional
# index breaks against the watcher's persistent cursor dir, because the
# newest-first listing changes between ticks: idx=1 into a shrunk 1-entry list
# reads as "exhausted" (a fresh session never gets pinned), and idx=1 into
# [new, old] re-hands the old id that is already pinned to another pane.
# Storing ids makes the pop idempotent under any reordering of the listing.
necro_agent_pop_session_id() {
  local agent="$1" cwd="$2" min_epoch="${3:-}"
  declare -f "agent_${agent}_all_session_ids" >/dev/null 2>&1 || return 0
  # Cursor dir must be set by the caller (snapshot script sets NECRO_CURSOR_DIR).
  local cursor_dir="${NECRO_CURSOR_DIR:-}"
  [ -n "$cursor_dir" ] || return 0
  # Safe filename: replace non-alnum with _.
  local key; key="$(printf '%s:%s' "$agent" "$cwd" | tr -cs 'a-zA-Z0-9' '_')"
  local cursor_file="$cursor_dir/$key"
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if [ -f "$cursor_file" ] && grep -qxF "$id" "$cursor_file" 2>/dev/null; then
      continue  # already handed out
    fi
    printf '%s' "$id"
    printf '%s\n' "$id" >> "$cursor_file" 2>/dev/null
    necro_log_event "agents" "pop_session_id" "agent=$agent" "result=found"
    return 0
  done < <("agent_${agent}_all_session_ids" "$cwd" "$min_epoch" 2>/dev/null)
  necro_log_event "agents" "pop_session_id" "agent=$agent" "result=exhausted"
  return 0  # exhausted — every candidate already pinned
}

# --- Dispatch wrappers ------------------------------------------------------
# Each takes the agent name as the first arg and forwards the rest to the
# adapter function. Returns empty/no-op when the adapter lacks the function.

necro_agent_latest_session_id() {
  local agent="$1"; shift
  declare -f "agent_${agent}_latest_session_id" >/dev/null 2>&1 || return 0
  "agent_${agent}_latest_session_id" "$@"
}

necro_agent_scrape_session_id() {
  local agent="$1"; shift
  declare -f "agent_${agent}_scrape_session_id" >/dev/null 2>&1 || return 0
  "agent_${agent}_scrape_session_id" "$@"
}

necro_agent_scrape_resume_cmd() {
  local agent="$1"; shift
  declare -f "agent_${agent}_scrape_resume_cmd" >/dev/null 2>&1 || return 0
  "agent_${agent}_scrape_resume_cmd" "$@"
}

necro_agent_scrape_ps_resume() {
  local agent="$1"; shift
  declare -f "agent_${agent}_scrape_ps_resume" >/dev/null 2>&1 || return 0
  "agent_${agent}_scrape_ps_resume" "$@"
}

necro_agent_resume_cmd() {
  local agent="$1"; shift
  declare -f "agent_${agent}_resume_cmd" >/dev/null 2>&1 || return 0
  "agent_${agent}_resume_cmd" "$@"
}

necro_agent_transcript_path() {
  local agent="$1"; shift
  declare -f "agent_${agent}_transcript_path" >/dev/null 2>&1 || return 0
  "agent_${agent}_transcript_path" "$@"
}

necro_agent_transcript_size() {
  local agent="$1"; shift
  declare -f "agent_${agent}_transcript_size" >/dev/null 2>&1 || return 0
  "agent_${agent}_transcript_size" "$@"
}

necro_agent_exit_keys() {
  local agent="$1"; shift
  declare -f "agent_${agent}_exit_keys" >/dev/null 2>&1 || return 0
  "agent_${agent}_exit_keys" "$@"
}

# Exit 0 if the pane's scrollback shows this agent's rate/session-limit banner.
# Adapters without agent_<name>_hit_limit return 1 (not limited).
necro_agent_hit_limit() {
  local agent="$1"; shift
  declare -f "agent_${agent}_hit_limit" >/dev/null 2>&1 || return 1
  "agent_${agent}_hit_limit" "$@"
}
