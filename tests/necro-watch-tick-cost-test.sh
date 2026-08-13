#!/usr/bin/env bash
# A watcher tick must cost a CONSTANT number of tmux invocations, not one (or
# several) per pane. @necromancer_watch_tick defaults to 1, so anything that
# scales with pane count runs forever, every second, on the single-threaded
# tmux server.
#
# Two regressions this locks out, both of which were real:
#   1. reading each pane's @necro_* options with `show-options -p -t <pane>`
#      instead of letting them ride along in the list-panes format;
#   2. calling necro_tmux_option() without priming its cache in the top-level
#      shell — it memoizes `show-options -g`, but every caller invokes it in a
#      $( ) subshell, so the memo died with the subshell and each pane re-dumped
#      every global option once per agent adapter (measured: 28 dumps/tick on a
#      10-pane server).
#
# Steady state only: the panes here are already pinned, so no Case 1/2/3 branch
# fires. Pinning a NEW pane legitimately costs a few writes for that pane.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
export NECROMANCER_LIMIT_CHECK_INTERVAL=0  # disable auto limit-save; this test asserts watcher behaviour
export NECROMANCER_LOG_DIR="$TMP/logs"
mkdir -p "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"

# tmux stub: logs every invocation, and reports $NPANES panes that are ALL
# already pinned (uuid + cmd + agent set, exited empty) so the walk is a no-op.
# Field separator is \x1f to match the script — with tab, bash would collapse
# the run of empty option fields and shift the columns.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$CALLS"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-option)
    case "$*" in
      *@necromancer_last_watch*) echo 0 ;;
      *@necromancer_last_limit_check*) echo 9999999999 ;;
      *@necromancer_limit_check_interval*) echo 60 ;;
      *@necromancer_agents*)     echo "claude" ;;
      *) echo "" ;;
    esac
    exit 0 ;;
  show-options)
    # -g global dump: the only options the walk needs.
    # last_limit_check is far in the future so the rate-limit auto-save path
    # does not fire (it would background a snapshot and add non-tick tmux
    # calls — this test measures the steady-state walk only).
    printf '@necromancer_last_watch 0\n@necromancer_last_limit_check 9999999999\n@necromancer_limit_check_interval 60\n@necromancer_agents claude\n'
    exit 0 ;;
  list-panes)
    i=1
    while [ "$i" -le "${NPANES:-1}" ]; do
      printf '%%%s\x1fclaude\x1f0000-uuid-%s\x1fclaude\x1fclaude\x1f\x1f100\x1f/tmp\n' "$i" "$i"
      i=$((i + 1))
    done
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

run_tick() {
  : > "$CALLS"
  rm -rf "$NECROMANCER_SNAPSHOT_DIR/.watch.lock"
  NPANES="$1" bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
  wc -l < "$CALLS" | tr -d ' '
}

one="$(run_tick 1)"
many="$(run_tick 12)"

fail=0
if [ "$one" != "$many" ]; then
  echo "FAIL: tick cost scales with pane count — 1 pane=$one tmux calls, 12 panes=$many"
  echo "      a watcher tick must be O(1) in panes (watch_tick defaults to 1s)"
  fail=1
fi

# Guard the absolute number too: equal-but-huge would still pass the check
# above. The walk needs one list-panes, one global dump, one last_watch write.
if [ "$one" -gt 5 ]; then
  echo "FAIL: tick costs $one tmux invocations, expected <= 5"
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "PASS: tick cost is constant in pane count (1 pane=$one, 12 panes=$many tmux calls)"
