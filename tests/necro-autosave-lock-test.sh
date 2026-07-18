#!/usr/bin/env bash
# Test: only one concurrent autosave fires when two copies race.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolated snapshot dir — no live tmux or real snapshot dir needed.
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_DEBUG=1
mkdir -p "$NECROMANCER_SNAPSHOT_DIR"

# Stub bin dir prepended to PATH.
TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

# tmux stub: return safe defaults for the options the script reads.
#
# @necromancer_last_saved must PERSIST across calls like a real tmux server
# option. In production the lock and the throttle work together: mkdir wins the
# instant of the race, then the winner stamps last_saved so the loser — which
# may not reach mkdir until after the winner's `trap EXIT` released the lock —
# is stopped by the throttle instead. A stub that hardcodes last_saved=0
# disables that second half, so the loser can legitimately fire a second
# autosave and the test fails intermittently, blaming a lock that is fine.
LAST_SAVED_FILE="$TMP/last_saved"
echo 0 > "$LAST_SAVED_FILE"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"set-option"*"@necromancer_last_saved"*)
    printf '%s' "\${@: -1}" > "$LAST_SAVED_FILE" ;;
  *"@necromancer_interval"*)      echo "0"  ;;
  *"@necromancer_last_saved"*)    cat "$LAST_SAVED_FILE" 2>/dev/null || echo 0 ;;
  *"@necromancer_max_snapshots"*) echo "20" ;;
  *"set-option"*) : ;;   # other no-op writes
  *"list-panes"*) : ;;   # no panes to report
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"

# necro-snapshot.sh stub: sleeps to widen the race window.
cat > "$TMPBIN/necro-snapshot.sh" <<'EOF'
#!/usr/bin/env bash
sleep 1
EOF
chmod +x "$TMPBIN/necro-snapshot.sh"

# Patch SCRIPTS_DIR so the script finds our stub snapshot instead of the real one.
# We do this by symlinking the real scripts dir but overriding necro-snapshot.sh.
FAKE_SCRIPTS="$TMP/scripts"
mkdir -p "$FAKE_SCRIPTS"
for f in "$ROOT/scripts"/*.sh; do
  ln -s "$f" "$FAKE_SCRIPTS/$(basename "$f")"
done
# Override snapshot stub
rm "$FAKE_SCRIPTS/necro-snapshot.sh"
ln -s "$TMPBIN/necro-snapshot.sh" "$FAKE_SCRIPTS/necro-snapshot.sh"

export PATH="$TMPBIN:$PATH"

# Launch two concurrent autosave runs.
bash "$FAKE_SCRIPTS/necro-autosave.sh" &
bash "$FAKE_SCRIPTS/necro-autosave.sh" &
wait

LOG="$NECROMANCER_SNAPSHOT_DIR/autosave.log"

# autosave backgrounds its work subshell, so `wait` above doesn't cover the
# log write. Poll for the completion marker instead of sleeping a fixed
# interval: under CPU load a fixed sleep reads the log before the winner has
# written it and miscounts, which fails the test for a race that never
# happened (the lock itself is fine).
deadline=$(( $(date +%s) + 30 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ -f "$LOG" ] && grep -q "autosave complete" "$LOG" 2>/dev/null && break
  sleep 0.2
done

count=0
if [ -f "$LOG" ]; then
  count=$(grep -c "autosave started" "$LOG" || true)
fi

if [ "$count" -eq 1 ]; then
  echo "PASS: exactly one autosave fired (lock works)"
  exit 0
else
  echo "FAIL: expected 1 autosave started, got $count" >&2
  [ -f "$LOG" ] && cat "$LOG" >&2
  exit 1
fi
