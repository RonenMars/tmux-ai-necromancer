#!/usr/bin/env bash
# necro-restore-resume-delay-test.sh — real (non-dry-run) restore of 2 records
# must sleep NECROMANCER_RESUME_DELAY seconds between resumes, not fire them
# back-to-back. Regression target: restoring several sessions at once spiked
# CPU/memory enough to stall the machine (see PR discussion after a
# terminal-crash restore + a separate reopen-script incident).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
# This test measures resume pacing only; disable the post-resume message so its
# separate delay doesn't perturb the wall-clock timing assertions below.
export NECROMANCER_RESUME_MESSAGE=""
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
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
printf 'transcript\n' > "$PROJ_DIR/$UUID1.jsonl"
printf 'transcript\n' > "$PROJ_DIR/$UUID2.jsonl"

# Stub tmux: session/window always "fresh" so both records reach resume.
# session_fresh path is taken when has-session fails on first check and the
# subsequent list-windows for "unmarked" comes back empty — simplest fresh
# stub is to report no existing marked window and let new-session/new-window
# succeed trivially.
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
{"pane_id":"%2","session":"s2","window_index":1,"window_name":"w2","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID2","uuid_source":"pane-option","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

# Batch size 1 (default): 2 resumes means 2 pauses (one after each). Allow
# some slack since restore itself takes non-zero time too.
start="$(date +%s)"
out="$(NECROMANCER_RESUME_DELAY=2 bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
elapsed=$(( $(date +%s) - start ))

grep -F "Resume pacing: 2s pause every 1 resume(s)" <<<"$out" >/dev/null || {
  echo "FAIL: pacing setting not reported in output" >&2
  echo "$out" >&2
  exit 1
}

[ "$elapsed" -ge 4 ] || {
  echo "FAIL: restore of 2 records (batch=1) finished in ${elapsed}s — expected >=4s (2 pauses)" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: batch size 1 pauses after every resume (${elapsed}s for 2 records)"

# Zero delay must skip waiting entirely — restore should be near-instant.
start="$(date +%s)"
NECROMANCER_RESUME_DELAY=0 bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
elapsed=$(( $(date +%s) - start ))
[ "$elapsed" -le 2 ] || {
  echo "FAIL: NECROMANCER_RESUME_DELAY=0 still took ${elapsed}s — delay=0 not honored" >&2
  exit 1
}
echo "PASS: NECROMANCER_RESUME_DELAY=0 skips the wait"

# Batch size 2: both resumes launch in the same batch, so only 1 pause total
# instead of 2 — proves batching actually reduces pause count, not just delay=0.
#
# The delay is 6s so a single pause dominates the script's own runtime: the
# signal here is "1 pause vs 2", and a delay near the baseline makes those two
# indistinguishable (fixture + stub overhead rides on top of the sleeps).
BATCH_DELAY=6
start="$(date +%s)"
out="$(NECROMANCER_RESUME_DELAY="$BATCH_DELAY" NECROMANCER_RESUME_BATCH_SIZE=2 bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
elapsed=$(( $(date +%s) - start ))

grep -F "Resume pacing: ${BATCH_DELAY}s pause every 2 resume(s)" <<<"$out" >/dev/null || {
  echo "FAIL: batch-size setting not reported in output" >&2
  echo "$out" >&2
  exit 1
}
[ "$elapsed" -ge "$BATCH_DELAY" ] && [ "$elapsed" -lt $(( BATCH_DELAY * 2 )) ] || {
  echo "FAIL: batch size 2 took ${elapsed}s — expected one ${BATCH_DELAY}s pause for 2 records, not two" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: batch size 2 pauses once for 2 records (${elapsed}s, one ${BATCH_DELAY}s pause)"

# --resume-delay / --resume-batch-size CLI flags override env/tmux-option.
out="$(bash "$ROOT/scripts/necro-restore.sh" --resume-delay 0 --resume-batch-size 5 "$SNAP" 2>&1)"
grep -F "Resume pacing: 0s pause every 5 resume(s)" <<<"$out" >/dev/null || {
  echo "FAIL: CLI flags --resume-delay/--resume-batch-size not honored" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: --resume-delay and --resume-batch-size CLI flags work"
