#!/usr/bin/env bash
# Invariant 2 (multi-pane grouping): several records sharing one
# (session, window_index) must restore as splits in ONE window.
#
# The claim path (an existing unmarked pane, e.g. a tmux-resurrect layout
# shell) never registered its window in WIN_FOR_GROUP. So record 1 claimed a
# pane, and record 2 of the same group — finding no unmarked pane of its own —
# fell through to `new-window` and flattened into a separate window, which is
# exactly the regression PR #11 fixed on the fresh-session path.
set -uo pipefail

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

# Stub tmux: session 's1' exists and has ONE unmarked pane (%10) at the
# record's cwd/window-index — the tmux-resurrect layout-shell scenario.
# Record 1 claims %10; record 2 must split into that same window, not add one.
# Marker state must persist across calls, as real tmux does server-side: once
# record 1 claims %10, it is no longer an UNMARKED candidate, so record 2 must
# take the split path instead of claiming the same pane twice.
MARKFILE="$TMP/mark.%10"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
case "\$1" in
  has-session) exit 0 ;;   # session already exists -> claim path
  set-option)
    # Record the marker set on %10 so later list-panes reflect it.
    case "\$*" in
      *'@necro_id'*) printf '%s' "\${@: -1}" > "$MARKFILE" ;;
    esac
    exit 0 ;;
  list-panes)
    mark=""; [ -f "$MARKFILE" ] && mark="\$(cat "$MARKFILE")"
    # Match most-specific format first — the 5-field record lookup also
    # contains '#{@necro_id}', so a bare '@necro_id' branch would shadow it.
    case "\$*" in
      # unmarked_window_id_for_record: idx, name, pane, path, marker.
      *'#{window_index}	#{window_name}'*) printf '1\tw1\t%%10\t$CWD\t%s\n' "\$mark" ;;
      # window_id_for_mark: marker + pane_id
      *'#{@necro_id}	#{pane_id}'*)        printf '%s\t%%10\n' "\$mark" ;;
      # window_marked: markers only
      *'#{@necro_id}'*)                    printf '%s\n' "\$mark" ;;
      *) printf '%%10\n' ;;
    esac
    ;;
  split-window) echo "%11" ;;
  new-window)   echo "@99" ;;
  list-windows) printf '@1\n' ;;
  display-message)
    # Answer per requested format, as real tmux does.
    case "\$*" in
      *'#{window_id}'*)             printf '@1\n' ;;
      *'#{pane_current_command}'*)  printf 'zsh\n' ;;
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
{"pane_id":"%1","session":"s1","window_index":1,"window_name":"w1","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID1","uuid_source":"test","window_layout":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s1","window_index":1,"window_name":"w1","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID2","uuid_source":"test","window_layout":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"

# `grep -c` already prints 0 on no-match; a `|| echo 0` fallback would append a
# SECOND 0, making "$n" the string "0\n0" and every numeric test meaningless.
new_windows="$(grep -c '^new-window' "$CALLS" 2>/dev/null; true)"
splits="$(grep -c '^split-window' "$CALLS" 2>/dev/null; true)"

fails=0
if [ "$new_windows" -ne 0 ]; then
  echo "FAIL: record 2 added a new window ($new_windows) instead of splitting into the claimed one" >&2
  fails=$((fails + 1))
fi
if [ "$splits" -lt 1 ]; then
  echo "FAIL: record 2 did not split into the claimed window (splits=$splits)" >&2
  fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then
  echo "--- restore output ---" >&2; echo "$out" >&2
  echo "--- tmux calls ---" >&2; cat "$CALLS" >&2
  exit 1
fi
echo "PASS: claimed window is reused by later records in the same group (splits=$splits, new-windows=$new_windows)"
