#!/usr/bin/env bash
# Invariant 7: the autosave lock must be held for the DURATION OF THE WORK,
# not just the setup.
#
# necro-autosave.sh does its work in a backgrounded `{ ... } &` subshell while
# the parent returns immediately (tmux status-right must not block). An EXIT
# trap on the PARENT therefore releases the lock within milliseconds, leaving
# the snapshot it is meant to serialize completely unprotected — measured at
# 17ms of protection for 3000ms of work before this was fixed. The trap has to
# live inside the backgrounded subshell that owns the work.
#
# This test asserts the lock outlives a deliberately slow snapshot stub.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
export NECROMANCER_LOG_DIR="$TMP/logs"
mkdir -p "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"

WORK_SECONDS=3

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"@necromancer_interval"*)      echo 5  ;;
  *"@necromancer_last_saved"*)    echo 0  ;;   # last save "long ago" -> proceed
  *"@necromancer_max_snapshots"*) echo 20 ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

# COPY the script + libs (don't symlink): the script resolves its siblings via
# $SELF_DIR after following symlinks, so a symlinked copy would silently run
# the REAL necro-snapshot.sh instead of the slow stub and invalidate the test.
FAKE_SCRIPTS="$TMP/scripts"; mkdir -p "$FAKE_SCRIPTS" "$TMP/lib"
cp "$ROOT/scripts/necro-autosave.sh" "$FAKE_SCRIPTS/"
cp -R "$ROOT/lib/." "$TMP/lib/"
printf '#!/usr/bin/env bash\nsleep %d\n' "$WORK_SECONDS" > "$FAKE_SCRIPTS/necro-snapshot.sh"
chmod +x "$FAKE_SCRIPTS/necro-snapshot.sh"

LOCK="$NECROMANCER_SNAPSHOT_DIR/.autosave.lock"
bash "$FAKE_SCRIPTS/necro-autosave.sh" >/dev/null 2>&1   # returns immediately

start_ns="$(date +%s%N)"
deadline=$(( $(date +%s) + WORK_SECONDS + 15 ))
while [ -d "$LOCK" ]; do
  [ "$(date +%s)" -ge "$deadline" ] && { echo "FAIL: lock never released (leaked)" >&2; exit 1; }
  sleep 0.05
done
held_ms=$(( ( $(date +%s%N) - start_ns ) / 1000000 ))
work_ms=$(( WORK_SECONDS * 1000 ))

# Allow slack for process startup, but the lock must clearly outlive the work
# rather than being dropped at parent exit (which measured ~17ms).
min_ms=$(( work_ms - 500 ))
if [ "$held_ms" -lt "$min_ms" ]; then
  echo "FAIL: lock held only ${held_ms}ms for ${work_ms}ms of work — released before the work finished" >&2
  echo "      (the EXIT trap must live inside the backgrounded work subshell)" >&2
  exit 1
fi
echo "PASS: lock held ${held_ms}ms, spanning the ${work_ms}ms of work"
