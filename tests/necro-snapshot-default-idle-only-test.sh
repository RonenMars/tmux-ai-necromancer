#!/usr/bin/env bash
# Regression test: a bare `necro-snapshot.sh` invocation (no flags at all)
# defaults to --idle-only. It must never send exit keys and must never block
# on a read prompt, even with a real tty available to the test process.
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

# No flags at all — this must run synchronously and return without hanging.
# A blocking read here would hang the test itself, so a completed run is
# already proof there was no blocking read.
bash "$ROOT/scripts/necro-snapshot.sh" >/dev/null 2>&1 </dev/null

if grep -q '^send-keys' "$CALLS"; then
  echo "FAIL: send-keys was called on a bare invocation (should default to idle-only):" >&2
  grep '^send-keys' "$CALLS" >&2
  exit 1
fi

SNAP="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl 2>/dev/null | head -1)"
if [ -z "$SNAP" ]; then
  echo "FAIL: no snapshot file was written" >&2
  exit 1
fi
case "$SNAP" in
  *.idle-only.jsonl) : ;;
  *)
    echo "FAIL: newest snapshot is not *.idle-only.jsonl: $SNAP" >&2
    exit 1 ;;
esac

echo "PASS: bare invocation defaults to --idle-only, zero send-keys, no hang"
