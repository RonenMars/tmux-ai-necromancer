#!/usr/bin/env bash
# necro-doctor-coverage-test.sh — the doctor warns when the newest snapshot
# does not COVER the live server, not merely when its records are malformed.
#
# Every other snapshot check asks whether the records are well-formed. A
# snapshot written while the server was collapsing — or mid-restore, before the
# panes exist — is perfectly well-formed and resurrects only the fraction it
# saw. `necro-reboot-resume.sh` with no pinned pointer takes the NEWEST file, so
# an unrepresentative newest snapshot silently restores less than you had, and
# the doctor used to report "all checks passed" on it.
#
# Only under-coverage is a problem; more records than live panes just means
# agents exited since, which costs restore nothing.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SNAP="$TMP/snapshots"; mkdir -p "$SNAP" "$TMP/bin"

fail=0
check()  { case "$2" in *"$3"*) ;; *) echo "FAIL: $1 (expected: $3)"; fail=1 ;; esac; }
refute() { case "$2" in *"$3"*) echo "FAIL: $1 (should NOT contain: $3)"; fail=1 ;; esac; }

rec() { # rec <agent> <uuid>
  printf '{"pane_id":"%%1","session":"s","window_index":0,"window_name":"w","cwd":"/tmp","prev_cmd":"c","agent":"%s","uuid":"%s","uuid_source":"","window_layout":"","captured_at":"","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' "$1" "$2"
}

# tmux stub: a live server with THREE claude panes, each already pinned.
cat > "$TMP/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  list-sessions) exit 0 ;;                        # server is up
  list-panes)
    printf '%%1\tclaude\n%%2\tclaude\n%%3\tclaude\n' ;;
  show-options)
    case "$*" in
      *@necro_uuid*) printf 'aaaaaaaa-1111-1111-1111-111111111111\n' ;;
      *) printf '' ;;
    esac ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/tmux"

# pgrep stub: both daemons alive. Without it the doctor reads the HOST process
# table, so the test passes on a developer box that happens to be running
# necromancer and fails anywhere else (CI, a fresh clone, a contributor's
# laptop) — the daemon check reports a real problem and exit goes to 1, which
# has nothing to do with the coverage assertion under test.
cat > "$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
case "$*" in
  *necro-autosave-daemon.sh*) echo 4242 ;;
  *necro-watch-daemon.sh*)    echo 4243 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/pgrep"

run_doctor() {
  PATH="$TMP/bin:$PATH" NECROMANCER_SNAPSHOT_DIR="$SNAP" \
    /bin/bash "$ROOT/scripts/necro-doctor.sh" 2>&1
}

# --- snapshot covers only 1 of the 3 live agents ----------------------------
rm -f "$SNAP"/*.jsonl
rec claude aaaaaaaa-1111-1111-1111-111111111111 > "$SNAP/2026-08-10T00-00-00Z.idle-only.jsonl"
out="$(run_doctor)"; rc=$?
check  "under-coverage warns"        "$out" "does not represent the server"
check  "under-coverage names counts" "$out" "names 1 agent(s) but 3 are running"
refute "under-coverage must not crash" "$out" "unbound variable"
# It is a warning, not a problem: exit stays 0.
[ "$rc" -eq 0 ] || { echo "FAIL: coverage shortfall must warn, not fail (exit $rc)"; fail=1; }

# --- snapshot covers all 3 --------------------------------------------------
rm -f "$SNAP"/*.jsonl
{ rec claude aaaaaaaa-1111-1111-1111-111111111111
  rec claude bbbbbbbb-2222-2222-2222-222222222222
  rec claude cccccccc-3333-3333-3333-333333333333; } > "$SNAP/2026-08-10T00-00-00Z.idle-only.jsonl"
out="$(run_doctor)"
refute "full coverage is silent" "$out" "does not represent the server"

# --- snapshot has MORE than live (agents exited) — not a problem ------------
rm -f "$SNAP"/*.jsonl
{ rec claude aaaaaaaa-1111-1111-1111-111111111111
  rec claude bbbbbbbb-2222-2222-2222-222222222222
  rec claude cccccccc-3333-3333-3333-333333333333
  rec claude dddddddd-4444-4444-4444-444444444444; } > "$SNAP/2026-08-10T00-00-00Z.idle-only.jsonl"
out="$(run_doctor)"
refute "over-coverage is silent" "$out" "does not represent the server"

[ "$fail" -eq 0 ] || exit 1
echo "PASS: necro-doctor-coverage-test"
