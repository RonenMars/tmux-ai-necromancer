#!/usr/bin/env bash
# necro-apply-resume-message-test.sh — after a resume, necro-apply sends the
# configured post-resume message; with an empty message it sends nothing extra.
# Uses a codex record so the resume always fires (no transcript-size gate).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_case() {
  local expect="$1"; shift   # remaining args are extra flags to necro-apply
  local TMP; TMP="$(mktemp -d)"
  export HOME="$TMP/home"; export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
  mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
  local TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
  local CALLS="$TMP/calls.log"; local CWD="$TMP/w"; mkdir -p "$CWD"

  # Mock tmux: pane is an idle shell (so resume fires), dest session absent.
  cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session) exit 1 ;;
  new-session) exit 0 ;;
  move-window) exit 0 ;;
  list-panes) printf '%%1 @1\n' ;;   # pane %1 -> window @1 (else apply skips it)
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TMPBIN/tmux"; export PATH="$TMPBIN:$PATH"

  # dest_session set to a value != source so no move-skip; agent=codex resumes.
  local SNAP="$TMP/s.jsonl"
  cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"src","window_index":1,"window_name":"w","cwd":"$CWD","prev_cmd":"codex","agent":"codex","uuid":"33333333-3333-3333-3333-333333333333","uuid_source":"scrollback","window_layout":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"dst","dest_window_name":""}
EOF

  NECROMANCER_RESUME_MESSAGE_DELAY=0 \
    bash "$ROOT/scripts/necro-apply.sh" "$@" "$SNAP" >/dev/null 2>&1
  local got; got=$(grep -c "send-keys .* continue Enter" "$CALLS" || true)
  local resumed; resumed=$(grep -c "send-keys .* resume" "$CALLS" || true)
  rm -rf "$TMP"
  [ "$resumed" -ge 1 ] || { echo "FAIL: resume never fired (test setup bug)"; return 1; }
  [ "$got" = "$expect" ] || { echo "FAIL: expected $expect 'continue' sends, got $got"; return 1; }
}

run_case 1 || exit 1                       # default → sends 'continue'
run_case 0 --resume-message "" || exit 1   # empty → sends nothing
echo "PASS: necro-apply-resume-message-test"
