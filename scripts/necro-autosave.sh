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
necro_init_log "$0"

LAST_SAVE_OPTION="@necromancer_last_saved"
SNAP_DIR="$(necro_snapshot_dir)"
LOG="$SNAP_DIR/autosave.log"
mkdir -p "$SNAP_DIR"

interval_minutes="$(necro_tmux_option @necromancer_interval 5)"
max_snapshots="$(necro_tmux_option @necromancer_max_snapshots 20)"
interval_seconds=$(( interval_minutes * 60 ))
necro_log_event "autosave" "schedule" "interval_minutes=$interval_minutes" "max_snapshots=$max_snapshots"

last_saved="$(necro_tmux_option "$LAST_SAVE_OPTION" 0)"
now="$(date +%s)"
next_run=$(( last_saved + interval_seconds ))
if [ "$now" -lt "$next_run" ]; then
  necro_log_event "autosave" "skip" "reason=interval"
  exit 0
fi

# ponytail: skip autosave during first 90s of uptime — avoids snapshotting a
# half-restored server right after boot before necro-resume has run.
boot_time="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*{ sec = \([0-9][0-9]*\),.*/\1/p')"
if [ -n "$boot_time" ] && [ $(( now - boot_time )) -lt 90 ]; then
  necro_log_event "autosave" "skip" "reason=recent_boot"
  exit 0
fi

# ponytail: mkdir is atomic — guarantees only one concurrent status-right fires
LOCK_DIR="$SNAP_DIR/.autosave.lock"
mkdir "$LOCK_DIR" 2>/dev/null || { necro_log_event "autosave" "skip" "reason=lock_held"; exit 0; }
necro_log_event "autosave" "start" "snapshot_dir=$SNAP_DIR"
tmux set-option -gq "$LAST_SAVE_OPTION" "$now"
# NOTE: no `trap ... EXIT` here. The real work runs in the backgrounded
# subshell below, and this parent exits immediately — an EXIT trap on the
# parent would drop the lock while the snapshot is still running, leaving the
# work it is meant to serialize unprotected. The subshell owns the lock and
# releases it via its own trap when the work is actually done.

if necro_debug_enabled; then
  exec 4>> "$LOG"
else
  exec 4> /dev/null
fi
{
  # The lock is held for the LIFETIME OF THIS SUBSHELL — the work, not just the
  # setup above. Released on any exit path (success, error, kill).
  trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT
  echo "[$(necro_ts)] autosave started"
  "$SELF_DIR/necro-snapshot.sh" --idle-only 2>&1

  # Summary: count records with/without UUIDs per agent for later debugging.
  latest="$(/bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null | head -1)"
  if [ -f "$latest" ]; then
    total=$(wc -l < "$latest" | tr -d ' ')
    with_uuid=$(grep -c '"uuid":"[^"]' "$latest" 2>/dev/null || true)
    with_uuid=${with_uuid:-0}
    no_uuid=$(( total - with_uuid ))
    agents_seen=$(grep -o '"agent":"[^"]*"' "$latest" 2>/dev/null \
      | sort | uniq -c | tr '\n' ' ' || echo "none")
    echo "[$(necro_ts)] summary: total=$total with_uuid=$with_uuid no_uuid=$no_uuid agents=[$agents_seen]"
  fi

  echo "[$(necro_ts)] autosave complete"
  necro_log_event "autosave" "complete" "snapshot_dir=$SNAP_DIR"

  # Log panes whose agents exited since the last autosave.
  while IFS=$'\t' read -r pane_id cwd; do
    [ -z "$pane_id" ] && continue
    exited="$(tmux show-option -pqv -t "$pane_id" @necro_agent_exited 2>/dev/null || true)"
    [ "$exited" != "1" ] && continue
    uuid="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
    cmd="$(tmux show-option -pqv  -t "$pane_id" @necro_cmd  2>/dev/null || true)"
    echo "[$(necro_ts)] closed: pane=$pane_id agent=${cmd:-unknown} uuid=${uuid:-none} cwd=$cwd"
  done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_path}' 2>/dev/null)

  # Rotate: keep only the N most-recent autosave files, but never the snapshot
  # pinned as the reboot target — a delayed reboot-resume must still find it.
  # POSIX loop (runs under /bin/sh via tmux — no `mapfile`).
  pinned="$(readlink "$SNAP_DIR/latest-for-reboot" 2>/dev/null || true)"
  /bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl "$SNAP_DIR"/*.enriched.jsonl 2>/dev/null \
    | tail -n "+$(( max_snapshots + 1 ))" \
    | while IFS= read -r f; do
        if [ "$f" = "$pinned" ]; then
          echo "[$(necro_ts)] rotation kept pinned reboot snapshot: $(basename "$f")"
          continue
        fi
        rm -f "$f"
        echo "[$(necro_ts)] rotated old snapshot: $(basename "$f")"
      done

  # ponytail: tail-based log rotation — keeps last 5000 lines, avoids unbounded growth
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 5000 ]; then
    tail -n 5000 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
    echo "[$(necro_ts)] log rotated to 5000 lines"
  fi
} >&4 &
exec 4>&-

exit 0
