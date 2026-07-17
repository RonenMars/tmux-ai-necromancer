#!/usr/bin/env bash
# necro-restore.sh must run under macOS's stock /bin/bash 3.2, which has no
# associative arrays. The group-tracking maps (window / layout / pane-count per
# session|window_index) once used `declare -A`; under 3.2 that errored, the
# group key then arithmetic-evaluated as an indexed subscript, and `set -u`
# aborted the loop on the FIRST record — a silent 0-session restore (exit 0,
# nothing rebuilt), the plugin's worst failure mode. This pins the 3.2 path:
# no declare/unbound errors, and multi-pane grouping (which needs those maps)
# still splits later records into the first record's window.
set -uo pipefail

BASH32="/bin/bash"
if [ ! -x "$BASH32" ]; then
  echo "SKIP: $BASH32 not present" >&2; exit 0
fi
case "$("$BASH32" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" in
  3) : ;;  # exactly the version we need to exercise
  *) echo "SKIP: $BASH32 is not 3.x (nothing to exercise)" >&2; exit 0 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_RESUME_MESSAGE=""
export NECROMANCER_RESUME_DELAY=0
mkdir -p "$HOME"

CWD="$TMP/work"
UUID1="11111111-1111-1111-1111-111111111111"
UUID2="22222222-2222-2222-2222-222222222222"
PROJ_DIR="$(
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/agents/claude.sh"
  agent_claude_project_dir "$CWD"
)"
mkdir -p "$CWD" "$PROJ_DIR"
printf 'transcript\n' > "$PROJ_DIR/$UUID1.jsonl"
printf 'transcript\n' > "$PROJ_DIR/$UUID2.jsonl"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"

# Fresh session 's1' with a single initial pane (%10). Record 1 claims it,
# record 2 (same session|window_index) must split into that same window.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
case "\$1" in
  has-session)   exit 1 ;;   # session does NOT exist -> fresh-create path
  new-session)   exit 0 ;;
  list-panes)    printf '%%10\n' ;;
  list-windows)  printf '@1\n' ;;
  split-window)  echo "%11" ;;
  new-window)    echo "@99" ;;
  display-message)
    case "\$*" in
      *'#{window_id}'*)            printf '@1\n' ;;
      *'#{pane_current_command}'*) printf 'zsh\n' ;;
      *) printf '\n' ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snap.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s1","window_index":1,"window_name":"w1","cwd":"$CWD","agent":"claude","uuid":"$UUID1","window_layout":""}
{"pane_id":"%2","session":"s1","window_index":1,"window_name":"w1","cwd":"$CWD","agent":"claude","uuid":"$UUID2","window_layout":""}
EOF

# Run under /bin/bash 3.2 specifically — the environment stock-macOS TPM users hit.
out="$("$BASH32" "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
rc=$?

fails=0
if printf '%s' "$out" | grep -qiE 'declare: -A|invalid option|unbound variable'; then
  echo "FAIL: bash-4 construct broke under $BASH32 (declare -A / unbound variable)" >&2
  fails=$((fails + 1))
fi
if [ "$rc" -ne 0 ]; then
  echo "FAIL: restore exited non-zero ($rc) under $BASH32" >&2
  fails=$((fails + 1))
fi
splits="$(grep -c '^split-window' "$CALLS" 2>/dev/null; true)"
new_windows="$(grep -c '^new-window' "$CALLS" 2>/dev/null; true)"
if [ "$splits" -lt 1 ]; then
  echo "FAIL: record 2 did not split into the group's window (splits=$splits) — group map lost" >&2
  fails=$((fails + 1))
fi
if [ "$new_windows" -ne 0 ]; then
  echo "FAIL: record 2 added a new window ($new_windows) instead of splitting" >&2
  fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then
  echo "--- restore output ---" >&2; echo "$out" >&2
  echo "--- tmux calls ---" >&2; cat "$CALLS" >&2
  exit 1
fi
echo "PASS: necro-restore.sh runs clean under $BASH32 3.2 and groups panes (splits=$splits)"
