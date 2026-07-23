#!/usr/bin/env bash
# necro-autosave-daemon-lock-test.sh — only one daemon may own the scheduler.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_AUTOSAVE_TICK=60
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin"

cat > "$TMP/bin/tmux" <<'TMUX_STUB'
#!/usr/bin/env bash
case "$1" in
  show-options) printf '%s\n' '@necromancer_debug off' '@necromancer_interval 5' '@necromancer_max_snapshots 20' ;;
  list-sessions) exit 0 ;;
  list-panes) exit 0 ;;
  set-option) exit 0 ;;
  *) exit 0 ;;
esac
TMUX_STUB
chmod +x "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

bash "$ROOT/scripts/necro-autosave-daemon.sh" &
first_pid=$!
lock="$NECROMANCER_SNAPSHOT_DIR/.autosave-daemon.lock"
for _ in $(seq 1 40); do
  [ -d "$lock" ] && break
  sleep 0.05
done
[ -d "$lock" ] || { echo 'FAIL: first daemon did not acquire lock' >&2; exit 1; }

bash "$ROOT/scripts/necro-autosave-daemon.sh" >/dev/null 2>&1
second_rc=$?
[ "$second_rc" -eq 0 ] || { echo "FAIL: duplicate daemon returned $second_rc" >&2; exit 1; }

kill "$first_pid" 2>/dev/null || true
wait "$first_pid" 2>/dev/null || true
[ ! -d "$lock" ] || { echo 'FAIL: daemon lock was not released' >&2; exit 1; }

echo 'PASS: autosave daemon is single-instance and releases its lock'
