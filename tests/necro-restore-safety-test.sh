#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_MAX_CLAUDE_TRANSCRIPT_BYTES=10
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  show-option) exit 0 ;;
  list-windows) exit 0 ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SMALL_UUID="11111111-1111-1111-1111-111111111111"
LARGE_UUID="22222222-2222-2222-2222-222222222222"
UNSAFE_UUID="33333333-3333-3333-3333-333333333333"
CODEX_UUID="44444444-4444-4444-4444-444444444444"
SMALL_CWD="$TMP/small"
LARGE_CWD="$TMP/large"
CODEX_CWD="$TMP/codex"
UNSAFE_CWD="/private/tmp/claude-501/work/scratchpad/tmux-debug-build/tmux/crashtest"
mkdir -p "$SMALL_CWD" "$LARGE_CWD" "$CODEX_CWD"

small_dir="$HOME/.claude/projects/${SMALL_CWD//\//-}"
large_dir="$HOME/.claude/projects/${LARGE_CWD//\//-}"
mkdir -p "$small_dir" "$large_dir"
printf 'small\n' > "$small_dir/$SMALL_UUID.jsonl"
printf 'this transcript is intentionally large\n' > "$large_dir/$LARGE_UUID.jsonl"

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"safe","window_index":0,"window_name":"small","cwd":"$SMALL_CWD","prev_cmd":"claude","agent":"claude","uuid":"$SMALL_UUID","uuid_source":"test","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"safe","window_index":1,"window_name":"large","cwd":"$LARGE_CWD","prev_cmd":"claude","agent":"claude","uuid":"$LARGE_UUID","uuid_source":"test","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%3","session":"unsafe","window_index":0,"window_name":"unsafe","cwd":"$UNSAFE_CWD","prev_cmd":"claude","agent":"claude","uuid":"$UNSAFE_UUID","uuid_source":"test","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%4","session":"codex","window_index":0,"window_name":"codex","cwd":"$CODEX_CWD","prev_cmd":"codex","agent":"codex","uuid":"$CODEX_UUID","uuid_source":"test","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" --dry-run "$SNAP" 2>&1)"

grep -F "resume: claude --resume $SMALL_UUID" <<<"$out" >/dev/null || {
  echo "missing small transcript resume" >&2
  echo "$out" >&2
  exit 1
}

grep -F "skip resume: Claude transcript is larger than 10 B" <<<"$out" >/dev/null || {
  echo "missing large transcript skip" >&2
  echo "$out" >&2
  exit 1
}

grep -F "skipping unsafe/unsafe: unsafe cwd matches" <<<"$out" >/dev/null || {
  echo "missing unsafe cwd skip" >&2
  echo "$out" >&2
  exit 1
}

grep -F "resume: codex resume $CODEX_UUID" <<<"$out" >/dev/null || {
  echo "missing codex resume" >&2
  echo "$out" >&2
  exit 1
}

forced="$(bash "$ROOT/scripts/necro-restore.sh" --dry-run --force-large "$SNAP" 2>&1)"
grep -F "resume: claude --resume $LARGE_UUID" <<<"$forced" >/dev/null || {
  echo "missing forced large transcript resume" >&2
  echo "$forced" >&2
  exit 1
}
