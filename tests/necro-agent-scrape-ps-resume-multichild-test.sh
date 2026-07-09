#!/usr/bin/env bash
# necro-agent-scrape-ps-resume-multichild-test.sh — a pane's shell can have
# more than one child process (e.g. claude plus some background job). This
# must still find the claude --resume <uuid> child and ignore noise, not get
# confused or return the wrong/no id. Regression target: scrape_ps_resume's
# `for child in $(pgrep -P ...)` loop assumes a single relevant child and a
# noise process (e.g. tmux's own copy of the shell, a linter, a file watcher)
# could shadow or interleave with the real one.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UUID="99999999-8888-7777-6666-555555555555"

# Two real children of this shell: one pure noise, one the "claude" stand-in.
# Order matters for this test — start noise first so a naive
# `pgrep -P | head -1` (instead of scanning all children) would pick the
# wrong one and fail.
sleep 60 &
NOISE_PID=$!
eval "exec -a 'claude --resume $UUID' sleep 60" &
CHILD_PID=$!
PARENT_PID=$$
cleanup() { kill "$NOISE_PID" "$CHILD_PID" >/dev/null 2>&1 || true; }
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
  echo "FAIL: expected $UUID amid noise sibling, got '$got'" >&2
  exit 1
}
echo "PASS: scrape_ps_resume finds the claude child despite a noise sibling"
