#!/usr/bin/env bash
# necro-status.sh — lightweight visible tmux status segment.
#
# Prints a compact indicator for status-right:
#   necro:<tracked>/<active>
# where "active" is panes currently running a configured agent and "tracked"
# is panes with a pinned @necro_uuid.
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
# shellcheck source=../lib/agents.sh
. "$SELF_DIR/../lib/agents.sh"
necro_load_agents

enabled="$(necro_tmux_option @necromancer_status "on")"
[ "$enabled" = "off" ] && exit 0

label="$(necro_tmux_option @necromancer_status_label "necro")"
active=0
tracked=0
exited=0

while IFS=$'\t' read -r pane_id cmd; do
  [ -z "$pane_id" ] && continue
  if [ -n "$(necro_agent_for_cmd "$cmd")" ]; then
    active=$((active + 1))
  fi
  if [ -n "$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)" ]; then
    tracked=$((tracked + 1))
  fi
  if [ "$(tmux show-option -pqv -t "$pane_id" @necro_agent_exited 2>/dev/null || true)" = "1" ]; then
    exited=$((exited + 1))
  fi
done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}' 2>/dev/null)

if [ "$exited" -gt 0 ]; then
  printf ' %s:%d/%d+%d ' "$label" "$tracked" "$active" "$exited"
else
  printf ' %s:%d/%d ' "$label" "$tracked" "$active"
fi
