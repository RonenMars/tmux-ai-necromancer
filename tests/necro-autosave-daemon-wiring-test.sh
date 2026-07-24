#!/usr/bin/env bash
# necro-autosave-daemon-wiring-test.sh — the entrypoint must start both
# schedulers independently and never wire necromancer scripts into status-right.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin"
CALLS="$TMP/tmux-calls"
: > "$CALLS"

cat > "$TMP/bin/tmux" <<'TMUX_STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CALLS:?}"
case "$1" in
  show-option)
    case "${3:-}" in
      status-right) printf '#(/Users/ronenmars/.tmux/plugins/tmux-ai-necromancer/scripts/necro-status.sh)#(/Users/ronenmars/.tmux/plugins/tmux-ai-necromancer/scripts/necro-watch.sh)BASE' ;;
      @necromancer_debug) printf 'off' ;;
      @necromancer_restore_key) printf 'R' ;;
      *) printf '' ;;
    esac
    ;;
  run-shell|set-option|bind-key) exit 0 ;;
  *) exit 0 ;;
esac
TMUX_STUB
chmod +x "$TMP/bin/tmux"
export CALLS PATH="$TMP/bin:$PATH"

bash "$ROOT/tmux-ai-necromancer.tmux"

grep -F "run-shell -b $ROOT/scripts/necro-autosave-daemon.sh" "$CALLS" >/dev/null || {
  echo 'FAIL: entrypoint did not start autosave daemon' >&2
  exit 1
}
grep -F "run-shell -b $ROOT/scripts/necro-watch-daemon.sh" "$CALLS" >/dev/null || {
  echo 'FAIL: entrypoint did not start watcher daemon' >&2
  exit 1
}
if grep -E 'set-option .*status-right .*necro-(status|watch|autosave)\.sh' "$CALLS" >/dev/null; then
  echo 'FAIL: necromancer script was wired into status-right' >&2
  exit 1
fi
grep -F 'set-option -gq status-right BASE' "$CALLS" >/dev/null || {
  echo 'FAIL: legacy status-right hooks were not removed' >&2
  exit 1
}

echo 'PASS: autosave and watcher daemons are independent of status-right'
