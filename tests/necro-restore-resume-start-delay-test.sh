#!/usr/bin/env bash
# necro-restore-resume-start-delay-test.sh — restore must wait
# NECROMANCER_RESUME_START_DELAY after creating a fresh pane before sending
# the resume command into it. Regression target: a pane just created by
# new-window/split-window/new-session isn't immediately ready for input (its
# shell is still starting); keystrokes sent right away are dropped rather
# than queued, so the resume command never lands and the pane sits empty
# with the agent never resumed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
# Isolate the assertion to the start-delay alone: no batch pause, no
# post-resume message delay.
export NECROMANCER_RESUME_DELAY=0
export NECROMANCER_RESUME_MESSAGE=""
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
UUID1="11111111-1111-1111-1111-111111111111"
PROJ_DIR="$(
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/agents/claude.sh"
  agent_claude_project_dir "$CWD"
)"
mkdir -p "$CWD" "$PROJ_DIR"
printf 'transcript\n' > "$PROJ_DIR/$UUID1.jsonl"

cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  new-session) echo "@1"; exit 0 ;;
  new-window)  echo "@2"; exit 0 ;;
  list-windows)
    case "$*" in
      *'#{@necro_id}'*) exit 0 ;;
      *) printf '@1\n' ;;
    esac
    ;;
  show-option) exit 0 ;;
  set-option)  exit 0 ;;
  display-message) printf 'zsh\n' ;;
  send-keys)   exit 0 ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s1","window_index":1,"window_name":"w1","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID1","uuid_source":"pane-option","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

start="$(date +%s)"
out="$(NECROMANCER_RESUME_START_DELAY=2 bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
elapsed=$(( $(date +%s) - start ))

grep -F "Pane readiness wait before resume: 2s" <<<"$out" >/dev/null || {
  echo "FAIL: start-delay setting not reported in output" >&2
  echo "$out" >&2
  exit 1
}
[ "$elapsed" -ge 2 ] || {
  echo "FAIL: restore with NECROMANCER_RESUME_START_DELAY=2 finished in ${elapsed}s — expected >=2s" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: NECROMANCER_RESUME_START_DELAY=2 waits before sending the resume command (${elapsed}s)"

start="$(date +%s)"
NECROMANCER_RESUME_START_DELAY=0 bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
elapsed=$(( $(date +%s) - start ))
[ "$elapsed" -le 2 ] || {
  echo "FAIL: NECROMANCER_RESUME_START_DELAY=0 still took ${elapsed}s — delay=0 not honored" >&2
  exit 1
}
echo "PASS: NECROMANCER_RESUME_START_DELAY=0 skips the wait"

out="$(bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
grep -F "Pane readiness wait before resume: 1s" <<<"$out" >/dev/null || {
  echo "FAIL: default start-delay should be 1s" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: default NECROMANCER_RESUME_START_DELAY is 1s"
