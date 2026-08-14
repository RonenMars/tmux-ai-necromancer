#!/usr/bin/env bash
# necro-autosave.sh — one-shot autosave job called by the daemon or manually.
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
max_snapshots="$(necro_tmux_option @necromancer_max_snapshots 288)"
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

# Atomic mkdir guarantees only one concurrent daemon tick or manual invocation.
#
# A lock whose owner is gone MUST be reclaimed. The work runs in a backgrounded
# subshell whose EXIT trap releases the lock; if that subshell dies to a signal
# the trap cannot catch, the lock survives and every later tick exits right
# here — autosave stops permanently, with no error anywhere and the daemon
# still reporting as running. That is not hypothetical: it cost 4.5 days of
# silent outage before necro-doctor.sh surfaced it.
#
# necro-watch.sh breaks its lock on age because a tick is sub-second. Here we
# can be exact instead: a live owner is still a `necro-autosave.sh` process,
# since the work subshell inherits the parent's argv. Note the daemon does NOT
# match this pattern — `necro-autosave-daemon.sh` has no `necro-autosave.sh`
# substring — so it is never mistaken for a lock owner.
# Ownership is decided by a pid the work subshell records INSIDE the lock, then
# checked with `ps` — the same shape #21 used for the daemon locks. Scanning
# `pgrep -f necro-autosave.sh` instead looks simpler and is wrong: any wrapper
# shell whose command line merely mentions the script (a `bash -c`, an editor
# task, a CI step) reads as a live owner, so the lock is never reclaimed.
# Looking up one recorded pid cannot false-positive that way.
LOCK_DIR="$SNAP_DIR/.autosave.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  lock_cmd=""
  [ -n "$lock_pid" ] && lock_cmd="$(ps -o command= -p "$lock_pid" 2>/dev/null || true)"
  case "$lock_cmd" in
    *necro-autosave.sh*)
      necro_log_event "autosave" "skip" "reason=lock_held" "owner=$lock_pid"
      exit 0
      ;;
  esac
  if [ -z "$lock_pid" ]; then
    # No pid recorded. Either a run that just won mkdir and hasn't stamped it
    # yet (microseconds), or a lock left by a pre-upgrade version that never
    # wrote one. Age separates them, so an old plugin's wedge still self-heals.
    lock_mtime="$(necro_file_mtime "$LOCK_DIR")"
    if [ -n "$lock_mtime" ] && [ "$(( now - lock_mtime ))" -le 60 ]; then
      necro_log_event "autosave" "skip" "reason=lock_starting"
      exit 0
    fi
  fi
  necro_log_event "autosave" "recover_stale_lock" "stale_pid=${lock_pid:-none}"
  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null
  mkdir "$LOCK_DIR" 2>/dev/null || { necro_log_event "autosave" "skip" "reason=lock_held"; exit 0; }
fi
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
release_lock() { rm -f "$LOCK_DIR/pid"; rmdir "$LOCK_DIR" 2>/dev/null || true; }
{
  # The lock is held for the LIFETIME OF THIS SUBSHELL — the work, not just the
  # setup above. Released on any exit path (success, error, kill).
  #
  # The trap alone is NOT enough: bash 3.2 never runs an EXIT trap installed
  # inside a BACKGROUNDED subshell (`{ trap ... EXIT; sleep 1; } &` fires in
  # bash 5 and is silently skipped in 3.2), so on a stock Mac — the default
  # interpreter per invariant 13 — this released nothing and every run leaked
  # its lock, leaving the pid-stamp reclaim path below (built for crashes) to
  # carry normal operation. The explicit call at the end of the subshell covers
  # the ordinary path on every bash; the trap still covers signals on bash 4+.
  trap 'release_lock' EXIT
  # Stamp our pid so a later run can tell "still working" from "died holding
  # it". $$ is the PARENT's pid inside a subshell and BASHPID is bash 4+
  # (invariant 13), so ask a child for its parent instead.
  sh -c 'echo $PPID' > "$LOCK_DIR/pid" 2>/dev/null
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

  # Rotate: keep only the N most-recent snapshot files, but never the snapshot
  # pinned as the reboot target — a delayed reboot-resume must still find it.
  # POSIX loop (runs under /bin/sh via tmux — no `mapfile`).
  #
  # The glob is an allowlist, so anything not named here is immortal AND free of
  # the max_snapshots budget. rate-limited captures are listed because the
  # watcher writes them unattended on a timer; without them the cap really meant
  # "N autosaves, plus however many of everything else".
  pinned="$(readlink "$SNAP_DIR/latest-for-reboot" 2>/dev/null || true)"
  /bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl "$SNAP_DIR"/*.enriched.jsonl \
             "$SNAP_DIR"/*.rate-limited.jsonl 2>/dev/null \
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
  release_lock
} >&4 &
exec 4>&-

exit 0
