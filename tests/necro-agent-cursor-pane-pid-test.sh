#!/usr/bin/env bash
# Cursor panes show `node`: (1) a supplied pane_pid spares the adapter its tmux
# call (watcher tick cost stays flat), (2) necro_agent_alive_in_pane still sees
# a node-wrapped Cursor child instead of calling the agent exited.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CALLS="$TMP/tmux.calls"; : > "$CALLS"

tmux() {
  echo "$1" >> "$CALLS"
  case "${1:-}" in
    show-options) printf '@necromancer_agents cursor\n' ;;
    display-message) echo 4242 ;;
  esac
  return 0
}
pgrep() { echo 4343; }
PS_ARGV=""
ps() {
  case "$*" in
    *comm=*) echo node ;;
    *stat=*) printf 'S+ %s\n' "$PS_ARGV" ;;
    *command=*) printf '%s\n' "$PS_ARGV" ;;
    *) echo "unstubbed ps $*" >&2; return 1 ;;
  esac
}

. "$ROOT/lib/common.sh"
. "$ROOT/lib/agents.sh"
necro_load_agents

BUNDLE="/Users/x/.local/bin/agent /Users/x/.local/share/cursor-agent/versions/2026.10.22-27dcf5f/index.js"
fail=0
check() { [ "$2" = "$3" ] && echo "  ok: $1" || { echo "  FAIL: $1 (want '$2' got '$3')"; fail=1; }; }

PS_ARGV="$BUNDLE"
: > "$CALLS"
check "pane_pid given: node pane is cursor" cursor "$(necro_agent_for_cmd node %1 4242)"
check "pane_pid given: no display-message call" 0 "$(grep -c display-message "$CALLS")"
check "no pane_pid: still falls back to tmux" cursor "$(necro_agent_for_cmd node %1)"
check "no pane_pid: display-message used" 1 "$(grep -c display-message "$CALLS")"
check "alive_in_pane sees node-wrapped cursor" cursor "$(necro_agent_alive_in_pane %1)"
PS_ARGV="node /app/vite.js"
check "alive_in_pane ignores a plain node child" "" "$(necro_agent_alive_in_pane %1)"

[ "$fail" = 0 ] && echo PASS || { echo FAILED; exit 1; }
