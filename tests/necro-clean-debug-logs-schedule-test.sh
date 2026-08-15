#!/usr/bin/env bash
# Verifies --older-than retention and --scheduled duration/cron gating.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEAN="$ROOT/scripts/necro-clean-debug-logs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_LOG_DIR="$TMP/logs"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_DEBUG=off
mkdir -p "$HOME" "$NECROMANCER_LOG_DIR" "$NECROMANCER_SNAPSHOT_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }

seed_logs() {
  rm -f "$NECROMANCER_LOG_DIR"/*.log
  printf 'old\n' > "$NECROMANCER_LOG_DIR/old.log"
  printf 'new\n' > "$NECROMANCER_LOG_DIR/new.log"
  # 3 days back — touch -t is POSIX, unlike `touch -d '3 days ago'`.
  touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)" \
    "$NECROMANCER_LOG_DIR/old.log"
}

# --- --older-than keeps young logs -----------------------------------------
seed_logs
bash "$CLEAN" --older-than 1d >/dev/null
[ -f "$NECROMANCER_LOG_DIR/new.log" ] || fail "--older-than 1d removed a fresh log"
[ ! -e "$NECROMANCER_LOG_DIR/old.log" ] || fail "--older-than 1d kept a 3-day-old log"

# A window wide enough to cover both keeps both.
seed_logs
bash "$CLEAN" --older-than 30d >/dev/null
[ -f "$NECROMANCER_LOG_DIR/old.log" ] || fail "--older-than 30d removed a 3-day-old log"

# Combined units parse.
seed_logs
bash "$CLEAN" --older-than 1d12h30m >/dev/null
[ ! -e "$NECROMANCER_LOG_DIR/old.log" ] || fail "combined duration spec did not apply"

# A malformed spec is rejected and changes nothing.
seed_logs
bash "$CLEAN" --older-than 7x >/dev/null 2>&1 && fail "bad duration spec was accepted"
[ -f "$NECROMANCER_LOG_DIR/old.log" ] || fail "bad duration spec still deleted logs"

# --- --scheduled is off by default ------------------------------------------
seed_logs
rm -f "$NECROMANCER_LOG_DIR/.last-cleanup"
bash "$CLEAN" --scheduled >/dev/null
[ -f "$NECROMANCER_LOG_DIR/old.log" ] || fail "--scheduled cleaned with no schedule configured"
[ ! -e "$NECROMANCER_LOG_DIR/.last-cleanup" ] || fail "disabled schedule wrote a stamp"

# --- first sighting starts the clock, it does not clean ---------------------
seed_logs
NECROMANCER_LOGS_SCHEDULED_CLEANUP=1m bash "$CLEAN" --scheduled >/dev/null
[ -f "$NECROMANCER_LOG_DIR/old.log" ] || fail "first scheduled sighting cleaned immediately"
[ -f "$NECROMANCER_LOG_DIR/.last-cleanup" ] || fail "first scheduled sighting wrote no stamp"

# --- duration schedule: not due, then due -----------------------------------
seed_logs
printf '%s\n' "$(date +%s)" > "$NECROMANCER_LOG_DIR/.last-cleanup"
NECROMANCER_LOGS_SCHEDULED_CLEANUP=1d bash "$CLEAN" --scheduled >/dev/null
[ -f "$NECROMANCER_LOG_DIR/old.log" ] || fail "schedule fired before its interval elapsed"

printf '%s\n' "$(($(date +%s) - 90000))" > "$NECROMANCER_LOG_DIR/.last-cleanup"
NECROMANCER_LOGS_SCHEDULED_CLEANUP=1d bash "$CLEAN" --scheduled >/dev/null
[ ! -e "$NECROMANCER_LOG_DIR/old.log" ] || fail "schedule did not fire after its interval"
[ ! -e "$NECROMANCER_LOG_DIR/new.log" ] || fail "scheduled run without max_age kept a log"
stamp="$(cat "$NECROMANCER_LOG_DIR/.last-cleanup")"
[ "$(($(date +%s) - stamp))" -lt 60 ] || fail "a fired schedule did not restamp"

# --- NECROMANCER_LOGS_MAX_AGE is the scheduled retention --------------------
seed_logs
printf '%s\n' "$(($(date +%s) - 90000))" > "$NECROMANCER_LOG_DIR/.last-cleanup"
NECROMANCER_LOGS_SCHEDULED_CLEANUP=1d NECROMANCER_LOGS_MAX_AGE=1d \
  bash "$CLEAN" --scheduled >/dev/null
[ -f "$NECROMANCER_LOG_DIR/new.log" ] || fail "scheduled max_age removed a fresh log"
[ ! -e "$NECROMANCER_LOG_DIR/old.log" ] || fail "scheduled max_age kept a stale log"

# --- cron schedule ----------------------------------------------------------
# Every minute matches whatever the clock says, so this is always due.
seed_logs
printf '%s\n' "$(($(date +%s) - 300))" > "$NECROMANCER_LOG_DIR/.last-cleanup"
NECROMANCER_LOGS_SCHEDULED_CLEANUP='* * * * *' bash "$CLEAN" --scheduled >/dev/null
[ ! -e "$NECROMANCER_LOG_DIR/old.log" ] || fail "'* * * * *' cron did not fire"

# A month that cannot be the current one is never due.
seed_logs
printf '%s\n' "$(($(date +%s) - 300))" > "$NECROMANCER_LOG_DIR/.last-cleanup"
other_month=$(( $(date +%m | sed 's/^0//') % 12 + 1 ))
NECROMANCER_LOGS_SCHEDULED_CLEANUP="* * * $other_month *" bash "$CLEAN" --scheduled >/dev/null
[ -f "$NECROMANCER_LOG_DIR/old.log" ] || fail "cron fired in the wrong month"

# Step syntax over a window that certainly contains a match.
seed_logs
printf '%s\n' "$(($(date +%s) - 3600))" > "$NECROMANCER_LOG_DIR/.last-cleanup"
NECROMANCER_LOGS_SCHEDULED_CLEANUP='*/5 * * * *' bash "$CLEAN" --scheduled >/dev/null
[ ! -e "$NECROMANCER_LOG_DIR/old.log" ] || fail "'*/5' cron step did not fire within an hour"

echo "PASS: necro-clean-debug-logs-schedule-test"
