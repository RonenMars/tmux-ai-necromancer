#!/usr/bin/env bash
# necro-log-divider.sh — stamp a decorative separator into every necro log file.
#
# Debugging aid: before reproducing a bug, run this with a label ("test 3") and
# it appends
#     ~~~~~~~ test 3 ~~~~~~~~
# to every *.log in the log dir (plus the snapshot-dir autosave.log). Everything
# logged after that line belongs to that repro — easy to find later.
#
# Label comes from $1 or, if absent, an interactive prompt.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SELF_DIR/../lib/common.sh"

if ! necro_debug_enabled; then
  necro_warn "Debug logging is off. Set @necromancer_debug to on first."
  exit 0
fi
necro_init_log "$0"

label="${1:-}"
if [ -z "$label" ]; then
  printf 'Divider label: '
  IFS= read -r label
fi
# ponytail: strip newlines so the label stays one decorative line
label="$(printf '%s' "$label" | tr '\n' ' ')"
[ -z "$label" ] && { necro_err "empty label — nothing written."; exit 1; }

divider="~~~~~~~ $label ~~~~~~~~"

LOG_DIR="$(necro_log_dir)"
SNAP_DIR="$(necro_snapshot_dir)"

count=0
# All per-script logs, plus the autosave log that lives in the snapshot dir.
for f in "$LOG_DIR"/*.log "$SNAP_DIR/autosave.log"; do
  [ -f "$f" ] || continue
  printf '%s\n' "$divider" >> "$f"
  count=$(( count + 1 ))
done

necro_ok "Wrote divider to $count log file(s): $divider"
