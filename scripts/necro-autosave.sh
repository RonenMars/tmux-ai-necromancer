#!/usr/bin/env bash
# necro-autosave.sh — called from tmux status-right every status-interval seconds.
#
# Checks whether @necromancer_interval minutes have elapsed since the last run
# (stored as a tmux server option). If so, runs necro-snapshot.sh --idle-only
# in the background: no pane disruption, filesystem-fallback id capture for
# every agent. Keeps the @necromancer_max_snapshots most-recent autosaves.
#
# Mirrors tmux-continuum's status-right trigger pattern. Not interactive.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SELF_DIR/../lib/common.sh"

LAST_SAVE_OPTION="@necromancer_last_saved"
SNAP_DIR="$(necro_snapshot_dir)"
LOG="$SNAP_DIR/autosave.log"
mkdir -p "$SNAP_DIR"

interval_minutes="$(necro_tmux_option @necromancer_interval 5)"
max_snapshots="$(necro_tmux_option @necromancer_max_snapshots 20)"
interval_seconds=$(( interval_minutes * 60 ))

last_saved="$(necro_tmux_option "$LAST_SAVE_OPTION" 0)"
now="$(date +%s)"
next_run=$(( last_saved + interval_seconds ))
[ "$now" -lt "$next_run" ] && exit 0

# Mark run time before launching so concurrent status refreshes don't double-fire.
tmux set-option -gq "$LAST_SAVE_OPTION" "$now"

{
  echo "[$(necro_ts)] autosave started"
  "$SELF_DIR/necro-snapshot.sh" --idle-only 2>&1
  echo "[$(necro_ts)] autosave complete"

  # Rotate: keep only the N most-recent autosave files. POSIX loop (runs under
  # /bin/sh via tmux — no `mapfile`).
  /bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null \
    | tail -n "+$(( max_snapshots + 1 ))" \
    | while IFS= read -r f; do
        rm -f "$f"
        echo "[$(necro_ts)] rotated old snapshot: $(basename "$f")"
      done
} >> "$LOG" 2>&1 &

exit 0
