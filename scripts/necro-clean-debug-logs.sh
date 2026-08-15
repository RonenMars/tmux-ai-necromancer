#!/usr/bin/env bash
# necro-clean-debug-logs.sh — remove opt-in necromancer debug logs.
#
# Usage: necro-clean-debug-logs.sh [--dry-run] [--older-than <spec>] [--scheduled]
#
#   --older-than <spec>  keep logs younger than <spec>; only older ones go.
#                        <spec> is a duration: 30m, 12h, 7d, or a combination
#                        such as 1d12h30m (units d/h/m/s).
#   --scheduled          run only when @necromancer_logs_scheduled_cleanup says
#                        it is due, then record the run. Exits 0 doing nothing
#                        when the option is unset or the schedule is not due.
#                        The autosave daemon calls this once per tick.
#
# Schedule option (@necromancer_logs_scheduled_cleanup / the matching
# NECROMANCER_ env var) is either a duration ("run every 7d") or a five-field
# cron expression ("0 3 * * *"). @necromancer_logs_max_age supplies the default
# --older-than for scheduled runs; unset means a scheduled run removes every log.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SELF_DIR/../lib/common.sh"

usage() {
  necro_err "Usage: $0 [--dry-run] [--older-than <spec>] [--scheduled]"
  exit 2
}

dry_run=0
scheduled=0
older_than=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)    dry_run=1 ;;
    --scheduled)  scheduled=1 ;;
    --older-than) shift; [ "$#" -gt 0 ] || usage; older_than="$1" ;;
    *) usage ;;
  esac
  shift
done

# --- schedule parsing -------------------------------------------------------

# "7d" / "45m" / "1d12h30m" -> seconds on stdout. Non-zero exit on a bad spec.
parse_duration() {
  local spec="$1" total=0 num unit rest
  case "$spec" in ''|*[!0-9dhms]*) return 1 ;; esac
  rest="$spec"
  while [ -n "$rest" ]; do
    num="${rest%%[dhms]*}"
    case "$num" in ''|*[!0-9]*) return 1 ;; esac
    rest="${rest#"$num"}"
    unit="${rest%"${rest#?}"}"
    rest="${rest#?}"
    case "$unit" in
      d) total=$((total + num * 86400)) ;;
      h) total=$((total + num * 3600)) ;;
      m) total=$((total + num * 60)) ;;
      s) total=$((total + num)) ;;
      *) return 1 ;;
    esac
  done
  [ "$total" -gt 0 ] || return 1
  printf '%s' "$total"
}

# Broken-down "M H d m w" for an epoch. GNU accepts -d and rejects -r <number>;
# BSD is the mirror image, so GNU-first falls back correctly on both (the same
# ordering rule as necro_file_mtime).
date_fields() {
  date -d "@$1" +'%M %H %d %m %w' 2>/dev/null ||
    date -r "$1" +'%M %H %d %m %w' 2>/dev/null
}

# Does one cron field (with *, a-b, */n and comma lists) accept a value?
cron_field_matches() {
  local field="$1" value="$2" fmin="$3" fmax="$4"
  local part step lo hi saved_ifs
  saved_ifs="$IFS"
  # noglob: an unquoted "*" field would otherwise expand to the working
  # directory's file list and match nothing.
  set -f
  IFS=,
  set -- $field
  IFS="$saved_ifs"
  set +f
  for part in "$@"; do
    step=1
    case "$part" in
      */*) step="${part##*/}"; part="${part%%/*}" ;;
    esac
    case "$step" in ''|*[!0-9]*|0) continue ;; esac
    case "$part" in
      '*') lo="$fmin"; hi="$fmax" ;;
      *-*) lo="${part%%-*}"; hi="${part##*-}" ;;
      *)   lo="$part"; hi="$part" ;;
    esac
    case "$lo" in ''|*[!0-9]*) continue ;; esac
    case "$hi" in ''|*[!0-9]*) continue ;; esac
    [ "$value" -ge "$lo" ] && [ "$value" -le "$hi" ] || continue
    [ $(((value - lo) % step)) -eq 0 ] && return 0
  done
  return 1
}

# Day-of-week accepts both 0 and 7 for Sunday.
cron_dow_matches() {
  cron_field_matches "$1" "$2" 0 6 && return 0
  [ "$2" -eq 0 ] && cron_field_matches "$1" 7 0 7
}

# Did a cron occurrence fall in (last, now]? Walks minute by minute, which is
# one date(1) call per minute.
# ponytail: capped at 24h of backlog, so a schedule missed across a longer
# sleep/shutdown fires on the next matching occurrence instead of immediately.
cron_due_since() {
  local spec="$1" last="$2" now="$3"
  local cmin chour cdom cmon cdow t floor fields
  set -f
  set -- $spec
  set +f
  [ "$#" -eq 5 ] || return 1
  cmin="$1" chour="$2" cdom="$3" cmon="$4" cdow="$5"

  t=$(((last / 60 + 1) * 60))
  floor=$((now - 86400))
  [ "$t" -lt "$floor" ] && t="$floor"
  while [ "$t" -le "$now" ]; do
    fields="$(date_fields "$t")" || return 1
    set -- $fields
    if cron_field_matches "$cmin" "$((10#$1))" 0 59 &&
      cron_field_matches "$chour" "$((10#$2))" 0 23 &&
      cron_field_matches "$cdom" "$((10#$3))" 1 31 &&
      cron_field_matches "$cmon" "$((10#$4))" 1 12 &&
      cron_dow_matches "$cdow" "$((10#$5))"; then
      return 0
    fi
    t=$((t + 60))
  done
  return 1
}

LOG_DIR="$(necro_log_dir)"
SNAP_DIR="$(necro_snapshot_dir)"
STAMP="$LOG_DIR/.last-cleanup"

# --- scheduled gate ---------------------------------------------------------
# Everything below the gate is the same work a manual run does. The gate exits
# before necro_init_log so a disabled or not-due tick writes nothing at all —
# it runs once a minute forever, and logging it would grow the logs it cleans.
if [ "$scheduled" = "1" ]; then
  schedule="${NECROMANCER_LOGS_SCHEDULED_CLEANUP:-$(necro_tmux_option @necromancer_logs_scheduled_cleanup "")}"
  case "$schedule" in ''|off|0) exit 0 ;; esac

  [ -n "$older_than" ] ||
    older_than="${NECROMANCER_LOGS_MAX_AGE:-$(necro_tmux_option @necromancer_logs_max_age "")}"

  now="$(date +%s)"
  mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
  if [ ! -f "$STAMP" ]; then
    # First sighting of the schedule: start the clock, never clean on the spot.
    printf '%s\n' "$now" > "$STAMP"
    exit 0
  fi
  last="$(cat "$STAMP" 2>/dev/null || true)"
  case "$last" in ''|*[!0-9]*) last="$now" ;; esac

  due=1
  if interval="$(parse_duration "$schedule")"; then
    [ "$((now - last))" -ge "$interval" ] || due=0
  elif ! cron_due_since "$schedule" "$last" "$now"; then
    due=0
  fi
  [ "$due" = "1" ] || exit 0
  printf '%s\n' "$now" > "$STAMP"
fi

max_age_seconds=""
if [ -n "$older_than" ]; then
  max_age_seconds="$(parse_duration "$older_than")" || {
    necro_init_log "$0"
    necro_err "Not a duration: $older_than (expected e.g. 30m, 12h, 7d, 1d12h)"
    exit 2
  }
fi

necro_init_log "$0"
necro_log_event "cleanup" "start" \
  "dry_run=$dry_run" "scheduled=$scheduled" "max_age=${max_age_seconds:-all}" "log_dir=$LOG_DIR"

cutoff=0
[ -n "$max_age_seconds" ] && cutoff=$(($(date +%s) - max_age_seconds))

count=0
kept=0
for file in "$LOG_DIR"/*.log "$SNAP_DIR/autosave.log"; do
  [ -f "$file" ] || continue
  if [ -n "$max_age_seconds" ]; then
    mtime="$(necro_file_mtime "$file")"
    case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
    if [ "$mtime" -gt "$cutoff" ]; then
      kept=$((kept + 1))
      continue
    fi
  fi
  if [ "$dry_run" = "1" ]; then
    printf 'Would remove: %s\n' "$file"
  else
    rm -f "$file"
    printf 'Removed: %s\n' "$file"
  fi
  count=$((count + 1))
done

necro_log_event "cleanup" "complete" "removed=$count" "kept=$kept" "dry_run=$dry_run"

if [ "$dry_run" = "1" ]; then
  necro_ok "Would remove $count debug log file(s)${max_age_seconds:+, keeping $kept newer than $older_than}"
else
  rmdir "$LOG_DIR" 2>/dev/null || true
  necro_ok "Removed $count debug log file(s)${max_age_seconds:+, kept $kept newer than $older_than}"
fi
