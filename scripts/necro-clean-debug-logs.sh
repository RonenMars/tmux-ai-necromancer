#!/usr/bin/env bash
# necro-clean-debug-logs.sh — remove opt-in necromancer debug logs.
#
# Usage: necro-clean-debug-logs.sh [--dry-run]
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SELF_DIR/../lib/common.sh"
necro_init_log "$0"

dry_run=0
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=1 ;;
  *) necro_err "Usage: $0 [--dry-run]"; exit 2 ;;
esac

LOG_DIR="$(necro_log_dir)"
SNAP_DIR="$(necro_snapshot_dir)"
necro_log_event "cleanup" "start" "dry_run=$dry_run" "log_dir=$LOG_DIR"

count=0
for file in "$LOG_DIR"/*.log "$SNAP_DIR/autosave.log"; do
  [ -f "$file" ] || continue
  if [ "$dry_run" = "1" ]; then
    printf 'Would remove: %s\n' "$file"
  else
    rm -f "$file"
    printf 'Removed: %s\n' "$file"
  fi
  count=$((count + 1))
done

if [ "$dry_run" = "1" ]; then
  necro_ok "Would remove $count debug log file(s)"
else
  rmdir "$LOG_DIR" 2>/dev/null || true
  necro_ok "Removed $count debug log file(s)"
fi
