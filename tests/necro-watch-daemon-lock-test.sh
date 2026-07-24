#!/usr/bin/env bash
# necro-watch-daemon-lock-test.sh — only one watcher daemon may run.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_WATCH_TICK=60
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin"

cat > "$TMP/bin/tmux" <<'TMUX_STUB'
#!/usr/bin/env bash
case "$1" in
  show-options) printf '%s\n' '@necromancer_debug off' '@necromancer_agents claude codex' ;;
  list-sessions) exit 0 ;;
  list-panes) exit 0 ;;
  set-option) exit 0 ;;
  *) exit 0 ;;
esac
TMUX_STUB
chmod +x "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

bash "$ROOT/scripts/necro-watch-daemon.sh" &
first_pid=$!
lock="$NECROMANCER_SNAPSHOT_DIR/.watch-daemon.lock"
for _ in $(seq 1 40); do
  [ -d "$lock" ] && break
  sleep 0.05
done
[ -d "$lock" ] || { echo 'FAIL: first watcher daemon did not acquire lock' >&2; exit 1; }

bash "$ROOT/scripts/necro-watch-daemon.sh" >/dev/null 2>&1
second_rc=$?
[ "$second_rc" -eq 0 ] || { echo "FAIL: duplicate watcher daemon returned $second_rc" >&2; exit 1; }

kill "$first_pid" 2>/dev/null || true
wait "$first_pid" 2>/dev/null || true
[ ! -d "$lock" ] || { echo 'FAIL: watcher daemon lock was not released' >&2; exit 1; }

echo 'PASS: watcher daemon is single-instance and releases its lock'
