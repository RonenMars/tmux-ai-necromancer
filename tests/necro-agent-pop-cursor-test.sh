#!/usr/bin/env bash
# The watcher's cursor dir is PERSISTENT (unlike the snapshot script's per-run
# mktemp), so a positional index into a newest-first listing goes wrong as the
# listing changes underneath it:
#
#   1. never-pinned : idx=1 but the filtered list shrank back to 1 entry ->
#                     "exhausted" -> a genuinely fresh session never gets pinned.
#   2. duplicate    : idx=1 into [B, A] hands out A again -- already pinned
#                     to another pane.
#
# Fix: remember which ids were handed out, not how many.
set -uo pipefail

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents.sh"

export NECRO_CURSOR_DIR="$TMP/cursors"
mkdir -p "$NECRO_CURSOR_DIR"

CWD="/tmp/proj"
IDS=""   # what the fake adapter currently reports, newest-first

agent_fake_all_session_ids() { printf '%s\n' $IDS; }

fails=0
expect() { # expect <label> <want>
  local label="$1" want="$2" got
  got="$(necro_agent_pop_session_id fake "$CWD")"
  if [ "$got" = "$want" ]; then
    echo "  ok: $label -> '${got:-<none>}'"
  else
    echo "  FAIL: $label"
    echo "        want: '$want'  got: '$got'"
    fails=$((fails + 1))
  fi
}

echo "scenario 1: fresh session after an older one aged out of the listing"
IDS="A"
expect "pane 1 pops A" "A"
# Days later: A is filtered out by min_epoch, only fresh B remains.
IDS="B"
expect "pane 2 pops B (not 'exhausted')" "B"

echo
echo "scenario 2: second live session while the first is still listed"
rm -rf "$NECRO_CURSOR_DIR"; mkdir -p "$NECRO_CURSOR_DIR"
IDS="A"
expect "pane 1 pops A" "A"
IDS="B A"     # newest-first: B is new, A still active
expect "pane 2 pops B (A already handed out)" "B"

echo
echo "scenario 3: genuinely exhausted"
expect "no unseen ids left" ""

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS"
