#!/usr/bin/env bash
# necro-debug-log-rotation-test.sh — a debug log crossing
# @necromancer_debug_log_max_bytes gets rotated to `.old`, not left to grow
# unbounded. Regression target: @necromancer_debug=on with the watcher's 1Hz
# tick against 27 panes produced 158 MB in 38 minutes with nothing capping
# it — scheduled cleanup only deletes whole files by age and is opt-in, so a
# user who just flips debug on gets unbounded growth by default.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_LOG_DIR="$TMP/logs"
mkdir -p "$HOME" "$NECROMANCER_LOG_DIR"

init_probe() {
  NECROMANCER_DEBUG=on NECROMANCER_DEBUG_LOG_MAX_BYTES="${1:-}" bash -c '
    . "$1/lib/common.sh"
    necro_init_log "probe.sh"
    echo "debug probe"
  ' _ "$ROOT"
}

LOG="$NECROMANCER_LOG_DIR/probe.log"
OLD="$LOG.old"

# Under the cap: no rotation.
init_probe 1000 >/dev/null
[ -f "$LOG" ] || { echo "FAIL: log not created" >&2; exit 1; }
[ ! -e "$OLD" ] || { echo "FAIL: rotated a log that was never over the cap" >&2; exit 1; }
echo "PASS: a log under the cap is not rotated"

# Push it over a tiny cap, then init again — should rotate.
printf 'x%.0s' $(seq 1 2000) >> "$LOG"
before_size="$(wc -c < "$LOG" | tr -d ' ')"
[ "$before_size" -gt 1000 ] || { echo "FAIL: fixture didn't grow the log past the cap" >&2; exit 1; }

init_probe 1000 >/dev/null

[ -f "$OLD" ] || { echo "FAIL: oversized log was not rotated to .old" >&2; exit 1; }
old_size="$(wc -c < "$OLD" | tr -d ' ')"
[ "$old_size" -eq "$before_size" ] || {
  echo "FAIL: rotated .old file size ($old_size) doesn't match the pre-rotation log ($before_size)" >&2
  exit 1
}
new_size="$(wc -c < "$LOG" | tr -d ' ')"
[ "$new_size" -lt 1000 ] || { echo "FAIL: fresh log after rotation should start small, got $new_size bytes" >&2; exit 1; }
echo "PASS: an oversized log rotates to .old and a fresh log starts"

# Rotating twice overwrites .old rather than accumulating generations.
printf 'y%.0s' $(seq 1 2000) >> "$LOG"
init_probe 1000 >/dev/null
[ -f "$NECROMANCER_LOG_DIR/probe.log.old.old" ] && {
  echo "FAIL: rotation created a second generation instead of overwriting .old" >&2
  exit 1
}
echo "PASS: rotation overwrites .old instead of accumulating generations"

# necro-clean-debug-logs.sh must sweep .old files too, or a rotated-away
# generation never gets cleaned up even with scheduled cleanup configured.
out="$(NECROMANCER_DEBUG=off bash "$ROOT/scripts/necro-clean-debug-logs.sh" --dry-run)"
grep -Fq "Would remove: $OLD" <<<"$out" || {
  echo "FAIL: cleanup dry-run doesn't see the rotated .old file" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: necro-clean-debug-logs.sh sweeps rotated .old logs too"

# The default cap (no override) must not rotate a small log.
unset NECROMANCER_DEBUG_LOG_MAX_BYTES
rm -f "$LOG" "$OLD"
NECROMANCER_DEBUG=on bash -c '
  . "$1/lib/common.sh"
  necro_init_log "probe.sh"
' _ "$ROOT" >/dev/null
[ -f "$LOG" ] && [ ! -e "$OLD" ] || { echo "FAIL: default cap misbehaved on a small log" >&2; exit 1; }
echo "PASS: default cap (20 MiB) leaves a small log untouched"
