#!/usr/bin/env bash
# A uuid already pinned to a LIVE pane must never be handed out again.
#
# The cursor file only remembers ids this cursor handed out. Ids resolved from
# process argv (`--resume <uuid>`) or from scrollback never reach it, and
# min_epoch can't reject them either: a live session's transcript is being
# written right now, so it is always the freshest candidate in its cwd. So a
# brand-new pane in a cwd where another pane is already running an agent got
# handed that agent's id.
#
# Observed 3x in 24h on a real server (panes %13/%27, %31/%32, %36/%41), each
# time in the new pane's very first snapshot; the %36/%41 collision persisted
# 25 minutes. Restoring such a snapshot resumes one conversation into two panes
# and silently loses the second pane's real session.
set -uo pipefail

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents.sh"

export NECRO_CURSOR_DIR="$TMP/cursors"
mkdir -p "$NECRO_CURSOR_DIR"

# tmux stub: reports the uuids currently pinned to panes, one per line, exactly
# as `list-panes -a -F '#{@necro_uuid}'` does — including the empty lines that
# unpinned panes produce.
TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "list-panes" ] && printf '%s\n' $LIVE_PINS ""
exit 0
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

CWD="/tmp/proj"
IDS=""        # what the adapter reports, newest-first
LIVE_PINS=""  # what the panes are currently pinned to
export LIVE_PINS

agent_fake_all_session_ids() { printf '%s\n' $IDS; }

fails=0
expect() { # expect <label> <want>
  local label="$1" want="$2" got
  got="$(necro_agent_pop_session_id fake "$CWD")"
  if [ "$got" = "$want" ]; then
    echo "  ok: $label -> '${got:-<none>}'"
  else
    echo "  FAIL: $label"
    echo "        want: '${want:-<none>}'  got: '${got:-<none>}'"
    fails=$((fails + 1))
  fi
}

echo "scenario 1: the live session's id was resolved from argv, not this cursor"
# Pane 1 launched with `--resume A`, so A is pinned but absent from the cursor
# file. A is also the newest transcript in the cwd — it is being written to.
LIVE_PINS="A"
IDS="A B"
expect "fresh pane skips A, pops B" "B"

echo
echo "scenario 2: no live pins — unchanged behaviour"
rm -rf "$NECRO_CURSOR_DIR"; mkdir -p "$NECRO_CURSOR_DIR"
LIVE_PINS=""
IDS="A"
expect "pops A" "A"

echo
echo "scenario 3: every candidate is live-pinned"
rm -rf "$NECRO_CURSOR_DIR"; mkdir -p "$NECRO_CURSOR_DIR"
LIVE_PINS="A B"
IDS="A B"
expect "exhausted, not a duplicate" ""

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS"
