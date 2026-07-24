#!/usr/bin/env bash
# necro-watch-daemon.sh — one tmux-managed pane watcher scheduler.
#
# Runs necro-watch.sh independently of status-right rendering. A filesystem
# lock makes plugin reloads idempotent, and the daemon exits when the tmux
# server disappears so it cannot outlive its server.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
necro_init_log "$0"

SNAP_DIR="$(necro_snapshot_dir)"
LOCK_DIR="$SNAP_DIR/.watch-daemon.lock"
mkdir -p "$SNAP_DIR"

daemon_pid="$$"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  existing_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  existing_cmd=""
  if [ -n "$existing_pid" ]; then
    existing_cmd="$(ps -o command= -p "$existing_pid" 2>/dev/null || true)"
  fi
  case "$existing_cmd" in
    *necro-watch-daemon.sh*)
      necro_log_event "watch_daemon" "skip" "reason=already_running" "pid=$existing_pid"
      exit 0
      ;;
    *)
      rm -f "$LOCK_DIR/pid"
      rmdir "$LOCK_DIR" 2>/dev/null || {
        necro_log_event "watch_daemon" "skip" "reason=lock_held"
        exit 0
      }
      mkdir "$LOCK_DIR" 2>/dev/null || exit 0
      ;;
  esac
fi

printf '%s\n' "$daemon_pid" > "$LOCK_DIR/pid"
cleanup() {
  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
stop() {
  cleanup
  exit 0
}
trap cleanup EXIT
trap stop INT TERM HUP

tick_seconds="${NECROMANCER_WATCH_TICK:-$(necro_tmux_option @necromancer_watch_tick 1)}"
case "$tick_seconds" in
  ''|*[!0-9]*|0) tick_seconds=1 ;;
esac
necro_log_event "watch_daemon" "start" "pid=$daemon_pid" "tick_seconds=$tick_seconds"

while tmux list-sessions >/dev/null 2>&1; do
  "$SELF_DIR/necro-watch.sh"
  sleep "$tick_seconds"
done

necro_log_event "watch_daemon" "stop" "reason=tmux_server_unavailable"
