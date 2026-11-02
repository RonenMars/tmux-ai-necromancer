#!/usr/bin/env bash
# End-to-end on a REAL tmux server (isolated via TMUX_TMPDIR): an after-new-session
# hook renames the session restore just created. The resume must still reach the
# pane and a rerun must not create a second session. Skips without tmux.
set -uo pipefail
command -v tmux >/dev/null 2>&1 || { echo "SKIP: tmux not installed"; exit 0; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
export TMUX_TMPDIR="$TMP/sock"; mkdir -p "$TMUX_TMPDIR"
unset TMUX
trap 'tmux kill-server 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$TMP/home" NECROMANCER_RESUME_MESSAGE="" NECROMANCER_RESUME_START_DELAY=0
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap" SHELL=/bin/sh
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/w" "$TMP/fakebin"
# A stand-in codex, so the resume never launches the real agent in the pane.
printf '#!/bin/sh\necho "FAKE $*"\nsleep 30\n' > "$TMP/fakebin/codex"; chmod +x "$TMP/fakebin/codex"
export PATH="$TMP/fakebin:$PATH"

tmux -f /dev/null new-session -d -s keep -x 80 -y 24 || { echo "SKIP: cannot start tmux"; exit 0; }
tmux set-hook -g after-new-session 'rename-session hooked'

UUID="22222222-2222-2222-2222-222222222222"
SNAP="$TMP/s.jsonl"
printf '{"pane_id":"%%1","session":"1","window_index":1,"window_name":"w","cwd":"%s","prev_cmd":"codex","agent":"codex","uuid":"%s","uuid_source":"x","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' "$TMP/w" "$UUID" > "$SNAP"

bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >"$TMP/out1" 2>&1
sleep 1
fails=0
bad() { echo "FAIL: $1" >&2; fails=$((fails+1)); }
tmux has-session -t =hooked 2>/dev/null || bad "hook did not rename the session (test setup)"
tmux capture-pane -p -t =hooked: 2>/dev/null | grep -q "FAKE resume $UUID" || bad "resume never reached the renamed session's pane"
n="$(tmux list-sessions | wc -l | tr -d ' ')"
bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >"$TMP/out2" 2>&1
[ "$(tmux list-sessions | wc -l | tr -d ' ')" = "$n" ] || bad "rerun created another session"

[ "$fails" -eq 0 ] || { cat "$TMP/out1" >&2; tmux list-panes -a -F "#{session_name} #{pane_id}" >&2; tmux capture-pane -p -t =hooked: >&2; exit 1; }
echo "PASS: real tmux, session renamed by after-new-session hook"
