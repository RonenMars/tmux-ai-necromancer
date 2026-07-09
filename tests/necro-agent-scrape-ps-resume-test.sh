#!/usr/bin/env bash
# necro-agent-scrape-ps-resume-test.sh — argv-based UUID recovery is ground
# truth: it must read the id a pane's claude process was actually launched
# with, not guess from scrollback or a filesystem cursor. Regression target:
# the cursor-pop fallback silently pinning a stale/wrong/subagent transcript
# to a live pane (see PR discussion following a terminal-crash restore).
#
# No live tmux server needed: stub `tmux display-message` to report a real
# background process's PID, matching how the function actually consumes it
# (pane_pid -> pgrep -P -> ps argv).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UUID="11111111-2222-3333-4444-555555555555"

# A real child process whose argv contains "--resume <uuid>", standing in for
# a pane's claude process. Only the "--resume <uuid>" substring is matched,
# so any long-lived command with those literal args in its command line works.
eval "exec -a 'claude --resume $UUID' sleep 60" &
CHILD_PID=$!
PARENT_PID=$$
cleanup() { kill "$CHILD_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

tmux() {
  if [ "$1" = "display-message" ]; then
    echo "$PARENT_PID"
    return 0
  fi
  command tmux "$@"
}
export -f tmux

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/agents.sh
. "$ROOT/lib/agents.sh"
necro_load_agents

got="$(necro_agent_scrape_ps_resume claude "%fake-pane")"

[ "$got" = "$UUID" ] || {
  echo "FAIL: expected $UUID, got '$got'" >&2
  exit 1
}
echo "PASS: scrape_ps_resume read the UUID from live process argv"
