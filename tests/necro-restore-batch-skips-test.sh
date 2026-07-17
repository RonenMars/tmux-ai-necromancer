#!/usr/bin/env bash
# necro-restore-batch-skips-test.sh — a skipped record (oversized transcript)
# must not consume a pacing-batch slot or trigger a pause. Regression target:
# resume_batch_count incrementing on skips instead of only real resumes would
# throw off pacing math (pausing too early/late relative to actual launches).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
# This test measures resume pacing only; disable the post-resume message so its
# separate delay doesn't perturb the wall-clock timing assertion below.
export NECROMANCER_RESUME_MESSAGE=""
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
UUID_SKIP="00000000-0000-0000-0000-000000000000"
UUID1="11111111-1111-1111-1111-111111111111"
UUID2="22222222-2222-2222-2222-222222222222"
# Resolve via the adapter — Claude encodes '/', '.' and '_' all as '-', so a
# fixture hardcoding only the '/' rule diverges from the code under test.
PROJ_DIR="$(
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/agents/claude.sh"
  agent_claude_project_dir "$CWD"
)"
mkdir -p "$CWD" "$PROJ_DIR"
# This one is deliberately oversized relative to the tiny max-bytes below.
printf '%1000s\n' | tr ' ' 'x' > "$PROJ_DIR/$UUID_SKIP.jsonl"
printf 'transcript\n' > "$PROJ_DIR/$UUID1.jsonl"
printf 'transcript\n' > "$PROJ_DIR/$UUID2.jsonl"

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
{"pane_id":"%0","session":"s0","window_index":1,"window_name":"w0","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID_SKIP","uuid_source":"pane-option","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%1","session":"s1","window_index":1,"window_name":"w1","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID1","uuid_source":"pane-option","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s2","window_index":1,"window_name":"w2","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID2","uuid_source":"pane-option","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

# batch size 2: the skip should NOT count toward the batch. With 2 real
# resumes (UUID1, UUID2) and batch size 2, they land in the same batch — a
# single pause, not two, and NOT triggered by the skip record beforehand.
#
# RESUME_DELAY is 6s (not ~2s) so that one pause dominates the fixture's own
# overhead: the pass/fail signal is "1 pause vs 2", and a delay close to the
# script's baseline runtime makes those two cases indistinguishable.
RESUME_DELAY=6
start="$(date +%s)"
out="$(NECROMANCER_MAX_CLAUDE_TRANSCRIPT_BYTES=100 NECROMANCER_RESUME_DELAY="$RESUME_DELAY" NECROMANCER_RESUME_BATCH_SIZE=2 \
  bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
elapsed=$(( $(date +%s) - start ))

grep -F "skip resume: Claude transcript is larger than" <<<"$out" >/dev/null || {
  echo "FAIL: oversized record was not skipped as expected (test setup broken)" >&2
  echo "$out" >&2
  exit 1
}

grep -F "agents resumed: 2, resume skipped: 1" <<<"$out" >/dev/null || {
  echo "FAIL: expected 2 resumed + 1 skipped in summary" >&2
  echo "$out" >&2
  exit 1
}

# 2 real resumes at batch size 2 → exactly 1 pause, not 2. Bound the upper end
# below 2 pauses rather than tight against 1: the script's own fixture/stub
# overhead rides on top of the sleeps, so assert the pause COUNT, not a precise
# runtime. A phantom pause from the skip would push this to >= 2 * RESUME_DELAY.
[ "$elapsed" -ge "$RESUME_DELAY" ] && [ "$elapsed" -lt $(( RESUME_DELAY * 2 )) ] || {
  echo "FAIL: took ${elapsed}s — expected one ${RESUME_DELAY}s pause (2 real resumes, batch 2; skip must not pause)" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: skipped (oversized) record doesn't consume a batch slot or trigger a pause (${elapsed}s, one ${RESUME_DELAY}s pause)"
