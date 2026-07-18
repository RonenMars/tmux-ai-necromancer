#!/usr/bin/env bash
# necro-prune.sh — kill tmux windows where every pane is an idle shell.
#
# A window is "idle" when no pane's process has any child process. Operating at
# window level avoids tmux respawning a fresh shell for each killed pane.
# Sessions left with no windows are removed by tmux automatically.
#
# Usage: necro-prune.sh [--dry-run]
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

command -v tmux >/dev/null 2>&1 || { echo "tmux not found" >&2; exit 1; }

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1 && echo "[dry-run] no windows will be killed"
necro_log_event "prune" "start" "dry_run=$dry_run"

[ -n "${TMUX:-}" ] && echo "Warning: running inside tmux — may kill this pane. Ctrl-C to abort." >&2

# Collect the set of window ids that have at least one pane with children.
# A space-delimited string set keeps this POSIX-safe (no bash 4 assoc arrays,
# which fail under /bin/sh — same constraint as autosave rotation).
busy=" "
while read -r wid pid; do
  [ -z "$wid" ] && continue
  child_count="$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${child_count:-0}" -gt 0 ]; then
    case "$busy" in *" $wid "*) ;; *) busy="$busy$wid " ;; esac
  fi
done < <(tmux list-panes -a -F '#{window_id} #{pane_pid}' 2>/dev/null)

while read -r wid label; do
  [ -z "$wid" ] && continue
  case "$busy" in
    *" $wid "*)
      necro_log_event "prune" "keep" "window=$wid" "reason=active"
      echo "  keeping active window: $label ($wid)"
      ;;
    *)
      if [ "$dry_run" -eq 1 ]; then
        necro_log_event "prune" "would_kill" "window=$wid"
        echo "[dry-run] would kill idle window: $label ($wid)"
      else
        necro_log_event "prune" "kill" "window=$wid"
        echo "Killing idle window: $label"
        tmux kill-window -t "$wid" 2>/dev/null || true
      fi
      ;;
  esac
done < <(tmux list-windows -a -F '#{window_id} #{session_name}:#{window_index}' 2>/dev/null)
