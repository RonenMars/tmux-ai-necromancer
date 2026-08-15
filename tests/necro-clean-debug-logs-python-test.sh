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

# --- --older-than retention -------------------------------------------------
seed_aged_logs() {
  # The all-or-nothing run above rmdir'd an emptied log directory.
  mkdir -p "$LOG_DIR"
  rm -f "$LOG_DIR"/*.log
  printf 'old\n' > "$LOG_DIR/old.log"
  printf 'new\n' > "$LOG_DIR/new.log"
  # touch -t is POSIX, unlike `touch -d '3 days ago'`.
  touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)" \
    "$LOG_DIR/old.log"
}

clean_py() {
  python3 "$ROOT/scripts/necro-clean-debug-logs.py" \
    --log-dir "$LOG_DIR" --snapshot-dir "$SNAPSHOT_DIR" "$@"
}

seed_aged_logs
clean_py --older-than 1d >/dev/null
[ -f "$LOG_DIR/new.log" ] || { echo "--older-than 1d removed a fresh log" >&2; exit 1; }
[ ! -e "$LOG_DIR/old.log" ] || { echo "--older-than 1d kept a stale log" >&2; exit 1; }

seed_aged_logs
clean_py --older-than 30d >/dev/null
[ -f "$LOG_DIR/old.log" ] || { echo "--older-than 30d removed a 3-day-old log" >&2; exit 1; }

seed_aged_logs
clean_py --older-than 1d12h30m >/dev/null
[ ! -e "$LOG_DIR/old.log" ] || { echo "combined duration spec did not apply" >&2; exit 1; }

seed_aged_logs
clean_py --older-than 7x >/dev/null 2>&1 && { echo "bad duration spec accepted" >&2; exit 1; }
[ -f "$LOG_DIR/old.log" ] || { echo "bad duration spec still deleted logs" >&2; exit 1; }

echo "PASS: standalone debug-log cleanup works"
