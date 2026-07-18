#!/usr/bin/env bash
# Verifies the standalone cleanup utility without tmux or platform-specific tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LOG_DIR="$TMP/logs"
SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$LOG_DIR" "$SNAPSHOT_DIR"
printf 'debug\n' > "$LOG_DIR/necro-watch.log"
printf 'debug\n' > "$LOG_DIR/tui.log"
printf 'debug\n' > "$SNAPSHOT_DIR/autosave.log"
printf 'snapshot\n' > "$SNAPSHOT_DIR/keep.jsonl"

python3 "$ROOT/scripts/necro-clean-debug-logs.py" \
  --log-dir "$LOG_DIR" \
  --snapshot-dir "$SNAPSHOT_DIR" \
  --dry-run | grep -q 'Would remove 3 debug log file(s)'
[ -f "$LOG_DIR/necro-watch.log" ] || { echo "dry-run removed a log" >&2; exit 1; }

python3 "$ROOT/scripts/necro-clean-debug-logs.py" \
  --log-dir "$LOG_DIR" \
  --snapshot-dir "$SNAPSHOT_DIR" | grep -q 'Removed 3 debug log file(s)'
[ ! -e "$LOG_DIR/necro-watch.log" ] || { echo "cleanup did not remove script log" >&2; exit 1; }
[ ! -e "$LOG_DIR/tui.log" ] || { echo "cleanup did not remove tui log" >&2; exit 1; }
[ ! -e "$SNAPSHOT_DIR/autosave.log" ] || { echo "cleanup did not remove autosave log" >&2; exit 1; }
[ -f "$SNAPSHOT_DIR/keep.jsonl" ] || { echo "cleanup removed a snapshot" >&2; exit 1; }

echo "PASS: standalone debug-log cleanup works"
