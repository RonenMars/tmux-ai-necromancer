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

necro_agent_resume_cmd() {
  local agent="$1"; shift
  declare -f "agent_${agent}_resume_cmd" >/dev/null 2>&1 || return 0
  "agent_${agent}_resume_cmd" "$@"
}

necro_agent_exit_keys() {
  local agent="$1"; shift
  declare -f "agent_${agent}_exit_keys" >/dev/null 2>&1 || return 0
  "agent_${agent}_exit_keys" "$@"
}
