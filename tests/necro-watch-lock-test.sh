#!/usr/bin/env bash
# The watcher's 1s self-throttle is a read-then-set TOCTOU: every attached
# client evaluates status-right, so two watchers can both pass the check before
# either writes the option, then race the cursor files and pane-option writes.
# An atomic mkdir lock closes it (same hazard/fix as autosave, invariant 7).
#
# Also verifies the lock self-heals: a SIGKILLed watcher leaves the dir behind,
# and a permanently-held lock would silently stop ALL UUID pinning.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
export NECROMANCER_LIMIT_CHECK_INTERVAL=0  # disable auto limit-save; this test asserts watcher behaviour
export NECROMANCER_LOG_DIR="$TMP/logs"
mkdir -p "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"
LOCK="$NECROMANCER_SNAPSHOT_DIR/.watch.lock"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
WALKS="$TMP/walks.log"

# tmux stub: report one pane so a walk is observable; last_watch=0 so the
# throttle always lets the run through (isolating the lock).
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"@necromancer_last_watch"*) echo 0 ;;
  *"@necromancer_agents"*)     echo "claude codex" ;;
  *"list-panes"*)
    echo walk >> "$WALKS"
    printf '%%1\tzsh\t/tmp\n'
    ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

fails=0

echo "1. a held lock makes a concurrent watcher exit without walking"
mkdir -p "$LOCK"
: > "$WALKS"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
walks="$(grep -c walk "$WALKS" 2>/dev/null; true)"
if [ "${walks:-0}" -eq 0 ]; then
  echo "   ok: second watcher backed off (0 walks)"
else
  echo "   FAIL: watcher walked panes despite a held lock ($walks walks)" >&2
  fails=$((fails + 1))
fi
rmdir "$LOCK" 2>/dev/null || true

echo "2. a free lock lets the watcher run, and it releases the lock"
: > "$WALKS"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
walks="$(grep -c walk "$WALKS" 2>/dev/null; true)"
if [ "${walks:-0}" -ge 1 ]; then
  echo "   ok: watcher ran ($walks walk(s))"
else
  echo "   FAIL: watcher did not walk panes with a free lock" >&2
  fails=$((fails + 1))
fi
if [ -d "$LOCK" ]; then
  echo "   FAIL: lock leaked after a clean run" >&2
  fails=$((fails + 1))
else
  echo "   ok: lock released on exit"
fi

echo "3. a stale lock (killed watcher) is broken, not honored forever"
mkdir -p "$LOCK"
touch -t 202001010000 "$LOCK"   # ancient -> cannot be a live sub-second tick
: > "$WALKS"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
walks="$(grep -c walk "$WALKS" 2>/dev/null; true)"
if [ "${walks:-0}" -ge 1 ]; then
  echo "   ok: stale lock broken, watcher recovered"
else
  echo "   FAIL: stale lock wedged the watcher permanently (UUID pinning would stop)" >&2
  fails=$((fails + 1))
fi

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS"
