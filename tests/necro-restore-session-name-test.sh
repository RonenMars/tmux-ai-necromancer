#!/usr/bin/env bash
# A snapshot session name containing backslashes must match literally, both
# through @necro_session and through an untagged live session's name.
set -uo pipefail
command -v tmux >/dev/null 2>&1 || { echo "SKIP: tmux not installed"; exit 0; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
export TMUX_TMPDIR="$TMP/sock"; mkdir -p "$TMUX_TMPDIR"
unset TMUX
trap 'tmux kill-server 2>/dev/null; rm -rf "$TMP"' EXIT
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap" SHELL=/bin/sh
mkdir -p "$NECROMANCER_SNAPSHOT_DIR" "$TMP/work"

tmux -f /dev/null new-session -d -s keep || { echo "SKIP: cannot start tmux"; exit 0; }
tagged_sid="$(tmux new-session -d -s renamed -c "$TMP/work" -P -F '#{session_id}')"
tmux set-option -t "$tagged_sid" @necro_session 'saved\name'
plain_sid="$(tmux new-session -d -s 'plain\name' -c "$TMP/work" -P -F '#{session_id}')"
# Use the same session_name format snapshots capture: tmux escapes backslashes
# when creating a session, so the live name can differ from the -s argument.
plain_name="$(tmux display-message -p -t "$plain_sid" '#{session_name}')"

fails=0
check_existing() {
  local sid="$1" snapshot_name="$2" pane out
  pane="$(tmux list-panes -t "$sid:" -F '#{pane_id}')"
  tmux set-option -p -t "$pane" @necro_id "$TMP/work|%saved"
  jq -cn --arg session "$snapshot_name" --arg cwd "$TMP/work" \
    '{session:$session, cwd:$cwd, pane_id:"%saved", window_index:0, window_name:"work", agent:"", uuid:""}' > "$TMP/s.jsonl"
  out="$(bash "$ROOT/scripts/necro-restore.sh" --dry-run "$TMP/s.jsonl" 2>&1)"
  if ! grep -qF 'Done. windows added: 0, reused: 1, agents resumed: 0' <<< "$out"; then
    printf 'FAIL: session name was not matched literally: %s\n%s\n' "$snapshot_name" "$out" >&2
    fails=$((fails+1))
  fi
}

check_existing "$tagged_sid" 'saved\name'
check_existing "$plain_sid" "$plain_name"
[ "$fails" -eq 0 ] || exit 1
echo "PASS: backslashes in tagged and untagged session names match literally"
