#!/usr/bin/env bash
# Regression test: with a REAL controlling terminal present (so the no-tty
# guard does not downgrade to --idle-only) but no input available to answer
# the per-pane exit prompt, `read -r ans </dev/tty || ans="q"` must hit EOF
# and fall back to "q" (abort), never fall through with an empty/unmatched
# answer and continue on to send exit keys. This exercises the fallback
# literal in scripts/necro-snapshot.sh directly, distinct from the no-tty
# guard tested in necro-snapshot-no-tty-guard-test.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
mkdir -p "$CWD"

CALLS="$TMP/tmux-calls.log"
: > "$CALLS"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
case "\$1" in
  list-panes)
    printf '%%1\tsess\t1\twin\t$CWD\tclaude\t\n'
    ;;
  show-option)
    exit 0
    ;;
  display-message)
    exit 0
    ;;
  send-keys)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

# `script -q /dev/null <cmd>` (BSD script, macOS) attaches <cmd> to a real
# pty, so `{ : </dev/tty; } 2>/dev/null` succeeds and the guard does NOT
# downgrade — we want to reach the interactive per-pane prompt. Stdin is
# /dev/null, so the prompt's `read -r ans </dev/tty` hits EOF immediately.
if ! timeout 10 script -q /dev/null bash "$ROOT/scripts/necro-snapshot.sh" --interactive \
    </dev/null >"$TMP/out.log" 2>&1; then
  echo "FAIL: script/necro-snapshot invocation itself failed or hung" >&2
  cat "$TMP/out.log" >&2
  exit 1
fi

if grep -q '^send-keys' "$CALLS"; then
  echo "FAIL: send-keys was called despite empty-answer EOF fallback:" >&2
  grep '^send-keys' "$CALLS" >&2
  cat "$TMP/out.log" >&2
  exit 1
fi

if ! grep -q "aborted by user" "$TMP/out.log"; then
  echo "FAIL: expected 'aborted by user' (the q|Q fallback) in output" >&2
  cat "$TMP/out.log" >&2
  exit 1
fi

echo "PASS: empty answer on EOF falls back to abort (q), zero send-keys"
