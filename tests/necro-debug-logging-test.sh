#!/usr/bin/env bash
# Verifies opt-in tracing and debug-log cleanup without a tmux server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_LOG_DIR="$TMP/logs"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME"

run_probe() {
  NECROMANCER_DEBUG="$1" bash -c '
    . "$1/lib/common.sh"
    necro_init_log "probe.sh"
    echo "debug probe"
  ' _ "$ROOT"
}

run_probe off
[ ! -e "$NECROMANCER_LOG_DIR/probe.log" ] || {
  echo "debug-disabled run created a log" >&2
  exit 1
}

run_probe on
LOG="$NECROMANCER_LOG_DIR/probe.log"
[ -f "$LOG" ] || { echo "debug-enabled run did not create a log" >&2; exit 1; }
grep -q 'event phase=run action=start script=probe' "$LOG"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"show-option"*) : ;;
  *"list-panes"*) : ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
status_output="$(PATH="$TMPBIN:$PATH" NECROMANCER_DEBUG=on bash "$ROOT/scripts/necro-status.sh")"
[ "$status_output" = ' necro:0/0 ' ] || {
  echo "debug logging changed status output: $status_output" >&2
  exit 1
}

mkdir -p "$NECROMANCER_SNAPSHOT_DIR"
printf 'autosave debug log\n' > "$NECROMANCER_SNAPSHOT_DIR/autosave.log"

bash "$ROOT/scripts/necro-clean-debug-logs.sh" --dry-run | grep -q 'Would remove 3 debug log file'
[ -f "$LOG" ] || { echo "dry-run removed a log" >&2; exit 1; }
bash "$ROOT/scripts/necro-clean-debug-logs.sh" | grep -q 'Removed 3 debug log file'
[ ! -e "$LOG" ] || { echo "cleanup did not remove the log" >&2; exit 1; }
[ ! -e "$NECROMANCER_SNAPSHOT_DIR/autosave.log" ] || { echo "cleanup did not remove autosave log" >&2; exit 1; }

echo "PASS: debug logging is opt-in and cleanup removes generated logs"
