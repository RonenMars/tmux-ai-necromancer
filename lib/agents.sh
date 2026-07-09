#!/usr/bin/env bash
# lib/agents.sh — agent adapter registry + dispatch for tmux-ai-necromancer.
#
# Sources every adapter in lib/agents/ and provides a uniform front-end so the
# scripts never hardcode a specific agent. Adding an agent = drop a new file in
# lib/agents/<name>.sh implementing the contract (see docs/agents.md) and add
# its name to the default @necromancer_agents list (or it's auto-discovered).
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
      # shellcheck disable=SC1090
      . "$f"
    else
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

# --- Per-cwd UUID cursor ----------------------------------------------------
# File-based cursor so the index survives subshell boundaries (command substitution
# forks a subshell; writes to an in-memory array would be lost on return).
# Cursor files live in $NECRO_CURSOR_DIR (set by the snapshot script before sourcing).
# Usage: necro_agent_pop_session_id "$agent" "$cwd" ["$min_epoch"] — prints
# next unused UUID. When min_epoch is given, candidates are pre-filtered to
# transcripts created at or after that time (see agent_<name>_all_session_ids)
# so a stale/unrelated session from days ago can't be handed to a pane that
# didn't exist yet when it was written.
necro_agent_pop_session_id() {
  local agent="$1" cwd="$2" min_epoch="${3:-}"
  declare -f "agent_${agent}_all_session_ids" >/dev/null 2>&1 || return 0
  # Cursor dir must be set by the caller (snapshot script sets NECRO_CURSOR_DIR).
  local cursor_dir="${NECRO_CURSOR_DIR:-}"
  [ -n "$cursor_dir" ] || return 0
  # Safe filename: replace non-alnum with _.
  local key; key="$(printf '%s:%s' "$agent" "$cwd" | tr -cs 'a-zA-Z0-9' '_')"
  local cursor_file="$cursor_dir/$key"
  local idx=0
  [ -f "$cursor_file" ] && idx="$(cat "$cursor_file" 2>/dev/null || echo 0)"
  local ids=()
  while IFS= read -r id; do
    [ -n "$id" ] && ids+=("$id")
  done < <("agent_${agent}_all_session_ids" "$cwd" "$min_epoch" 2>/dev/null)
  if [ "${#ids[@]}" -eq 0 ] || [ "$idx" -ge "${#ids[@]}" ]; then
    return 0  # exhausted
  fi
  printf '%s' "${ids[$idx]}"
  printf '%d' $(( idx + 1 )) > "$cursor_file"
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
