#!/usr/bin/env bash
# necro-restore-resume-message-test.sh — after a resume, restore sends the
# configured post-resume message; with an empty message it sends nothing extra.
# Uses a codex record (no transcript-size skip gate) so the resume always fires.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_case() {
  local expect="$1"; shift   # remaining args are extra flags to necro-restore
  local TMP; TMP="$(mktemp -d)"
  export HOME="$TMP/home"; export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
  mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
  local TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
  local CALLS="$TMP/calls.log"; local CWD="$TMP/w"; mkdir -p "$CWD"

  cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session) exit 1 ;;
  new-session) exit 0 ;;
  list-windows) case "\$*" in *'#{window_id}'*) printf '@1\n' ;; *) printf '' ;; esac ;;
  list-panes)  printf '%%1\n' ;;
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TMPBIN/tmux"; export PATH="$TMPBIN:$PATH"

  local SNAP="$TMP/s.jsonl"
  cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w","cwd":"$CWD","prev_cmd":"codex","agent":"codex","uuid":"22222222-2222-2222-2222-222222222222","uuid_source":"scrollback","window_layout":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

  NECROMANCER_RESUME_MESSAGE_DELAY=0 \
    bash "$ROOT/scripts/necro-restore.sh" "$@" "$SNAP" >/dev/null 2>&1
  local got; got=$(grep -c "send-keys .* continue Enter" "$CALLS" || true)
  # sanity: the resume itself must have fired, else the test proves nothing
  local resumed; resumed=$(grep -c "send-keys .* resume" "$CALLS" || true)
  rm -rf "$TMP"
  [ "$resumed" -ge 1 ] || { echo "FAIL: resume never fired (test setup bug)"; return 1; }
  [ "$got" = "$expect" ] || { echo "FAIL: expected $expect 'continue' sends, got $got"; return 1; }
}

run_case 1 || exit 1                       # default → sends 'continue'
run_case 0 --resume-message "" || exit 1   # empty → sends nothing
echo "PASS: necro-restore-resume-message-test"
