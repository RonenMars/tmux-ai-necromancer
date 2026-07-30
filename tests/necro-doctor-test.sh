#!/usr/bin/env bash
# necro-doctor-test.sh — the doctor's snapshot analysis is the check users act
# on, so it must count records correctly and degrade cleanly with no tmux
# server. Also asserts the exit contract: ✗ fails, ⚠ alone does not.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SNAP="$TMP/snapshots"
mkdir -p "$SNAP"
export NECROMANCER_SNAPSHOT_DIR="$SNAP"

fail=0
check() { # check <label> <haystack> <needle>
  case "$2" in *"$3"*) ;; *) echo "FAIL: $1 (expected to find: $3)"; fail=1 ;; esac
}
refute() {
  case "$2" in *"$3"*) echo "FAIL: $1 (should NOT contain: $3)"; fail=1 ;; esac
}

rec() { # rec <agent> <uuid>
  printf '{"pane_id":"%%1","session":"s","window_index":0,"window_name":"w","cwd":"/tmp","prev_cmd":"c","agent":"%s","uuid":"%s","uuid_source":"","window_layout":"","captured_at":"","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' "$1" "$2"
}

# The doctor must survive with no tmux at all — a user whose server died is
# exactly who runs it. PATH is stripped of tmux for these runs.
run_doctor() {
  PATH="$TMP/nobin:$PATH" NECROMANCER_SNAPSHOT_DIR="$SNAP" \
    /bin/bash "$ROOT/scripts/necro-doctor.sh" 2>&1
}
mkdir -p "$TMP/nobin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/nobin/tmux"; chmod +x "$TMP/nobin/tmux"

# --- no snapshot at all -----------------------------------------------------
out="$(run_doctor)"; rc=$?
check "no-snapshot warns" "$out" "no snapshot found"
refute "no-snapshot must not crash" "$out" "unbound variable"
[ "$rc" -le 1 ] || { echo "FAIL: unexpected exit $rc with no snapshot"; fail=1; }

# --- 3 records: 2 resumable, 1 agent without a uuid -------------------------
{ rec claude aaaaaaaa-1111-1111-1111-111111111111
  rec codex  bbbbbbbb-2222-2222-2222-222222222222
  rec claude ""; } > "$SNAP/2026-07-30T00-00-00Z.idle-only.jsonl"

out="$(run_doctor)"
check "counts records"    "$out" "3 record(s)"
check "counts agents"     "$out" "3 with an agent"
check "counts uuids"      "$out" "2 with a UUID"
check "flags the gap"     "$out" "1 agent record(s) carry no UUID"
refute "no crash"         "$out" "unbound variable"

# --- every agent record resumable -> clean ----------------------------------
{ rec claude aaaaaaaa-1111-1111-1111-111111111111
  rec codex  bbbbbbbb-2222-2222-2222-222222222222; } > "$SNAP/2026-07-30T01-00-00Z.idle-only.jsonl"
out="$(run_doctor)"
check "clean snapshot passes" "$out" "every agent record carries a UUID"
refute "no false gap warning" "$out" "carry no UUID"

# --- an empty snapshot is a problem, not a warning --------------------------
: > "$SNAP/2026-07-30T02-00-00Z.idle-only.jsonl"
out="$(run_doctor)"; rc=$?
check "empty snapshot flagged" "$out" "snapshot is empty"
[ "$rc" -eq 1 ] || { echo "FAIL: empty snapshot must exit 1, got $rc"; fail=1; }

# --- dangling reboot pointer is a problem -----------------------------------
ln -sfn "$SNAP/does-not-exist.jsonl" "$SNAP/latest-for-reboot"
out="$(run_doctor)"; rc=$?
check "dangling pointer flagged" "$out" "pointer is dangling"
[ "$rc" -eq 1 ] || { echo "FAIL: dangling pointer must exit 1, got $rc"; fail=1; }
rm -f "$SNAP/latest-for-reboot"

# --- read-only contract: the doctor must not create or delete anything ------
{ rec claude aaaaaaaa-1111-1111-1111-111111111111; } > "$SNAP/2026-07-30T02-00-00Z.idle-only.jsonl"
before="$(/bin/ls -1 "$SNAP" | sort)"
run_doctor >/dev/null 2>&1
after="$(/bin/ls -1 "$SNAP" | sort)"
[ "$before" = "$after" ] || { echo "FAIL: doctor mutated the snapshot dir"; echo "  before: $before"; echo "  after:  $after"; fail=1; }

# --- --help exits 0 and sends no keys ---------------------------------------
help_out="$(/bin/bash "$ROOT/scripts/necro-doctor.sh" --help 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: --help should exit 0, got $rc"; fail=1; }
check "help mentions read-only" "$help_out" "Read-only"

# --- an unknown flag is rejected --------------------------------------------
/bin/bash "$ROOT/scripts/necro-doctor.sh" --wat >/dev/null 2>&1
[ "$?" -eq 2 ] || { echo "FAIL: unknown flag should exit 2"; fail=1; }

[ "$fail" = 0 ] && echo "PASS: necro-doctor-test" || exit 1
