#!/usr/bin/env bash
# Regression test: necro-snapshot.sh --yes / --interactive, run with no
# controlling terminal (cron/launchd/scripted context), must NOT send exit
# keys to any live agent pane. This is the exact production incident: an
# empty `read -r ans </dev/tty || ans=""` fell through the `case` statement
# and silently exited live Claude Code sessions. The fix refuses exit-capture
# when /dev/tty cannot actually be opened and downgrades to --idle-only.
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

# tmux stub: one pane running `claude` (a known AI-agent command per
# lib/agents/claude.sh's agent_claude_matches), and logs every send-keys
# call it receives so we can assert none happened.
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

run_ttyless() {
  local flag="$1"
  : > "$CALLS"
  # os.setsid() detaches the controlling terminal entirely, so /dev/tty
  # cannot be opened inside the child — the exact ttyless condition from
  # the production incident (cron/launchd/scripted invocation).
  python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "$ROOT/scripts/necro-snapshot.sh" "$flag" >"$TMP/out.log" 2>&1
}

assert_no_send_keys() {
  local flag="$1"
  if grep -q '^send-keys' "$CALLS"; then
    echo "FAIL ($flag): send-keys was called with no controlling terminal:" >&2
    grep '^send-keys' "$CALLS" >&2
    exit 1
  fi
}

assert_idle_only_output() {
  local flag="$1"
  local snap
  snap="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl 2>/dev/null | head -1)"
  if [ -z "$snap" ]; then
    echo "FAIL ($flag): no snapshot file was written" >&2
    exit 1
  fi
  case "$snap" in
    *.idle-only.jsonl) : ;;
    *)
      echo "FAIL ($flag): newest snapshot is not *.idle-only.jsonl: $snap" >&2
      exit 1 ;;
  esac
}

assert_warning_printed() {
  local flag="$1"
  if ! grep -q "No controlling terminal" "$TMP/out.log"; then
    echo "FAIL ($flag): downgrade warning ('No controlling terminal') not found in output" >&2
    cat "$TMP/out.log" >&2
    exit 1
  fi
}

for flag in --yes --interactive; do
  run_ttyless "$flag"
  assert_no_send_keys "$flag"
  assert_idle_only_output "$flag"
  assert_warning_printed "$flag"
  echo "PASS ($flag): no controlling terminal -> zero send-keys, idle-only snapshot, warning printed"
  rm -f "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl
done

echo "PASS: no-tty guard holds for both --yes and --interactive"
