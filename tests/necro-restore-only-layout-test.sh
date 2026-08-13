#!/usr/bin/env bash
# necro-restore-only-layout-test.sh — a window restored only in PART must not
# have its saved layout replayed.
#
# window_layout describes the whole window. Replaying a 2-pane layout onto a
# window where --only brought back 1 pane either errors or squeezes the
# survivor into a cell meant for a pane that isn't there.
#
# The pre-existing live-vs-saved guard cannot catch this by itself: restore 1
# of 2 panes and the live count (1) equals the saved count (1), which reads as
# a perfect match. Telling the two apart needs the group's PRE-filter record
# count, which is why full_count is tracked separately from count.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"
CWD1="$TMP/a"; CWD2="$TMP/b"; mkdir -p "$CWD1" "$CWD2"
LAYOUT='c005,364x71,0,0{182x71,0,0,5,181x71,183,0,8}'

SESS_FLAG="$TMP/created"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session)  [ -f "$SESS_FLAG" ] && exit 0 || exit 1 ;;
  new-session)  : > "$SESS_FLAG"; exit 0 ;;
  list-windows)
    case "\$*" in
      *'#{@necro_id}'*'#{window_id}'*) printf '' ;;
      *'#{window_index}'*'#{window_name}'*) printf '' ;;
      *) printf '@1\n' ;;
    esac ;;
  new-window)   printf '@10\n' ;;
  split-window) printf '%%20\n' ;;
  list-panes)
    # Only the layout replay's live-count probe asks for a bare #{pane_id};
    # marker lookups use a multi-field format and must stay empty. \$LIVE_PANES
    # is how many panes the window ends up with — 2 for a whole-window restore,
    # 1 when --only brought back half of it. Reporting 2 unconditionally would
    # hide the bug: the live-vs-saved check would catch the partial case on its
    # own and the layout guard would never be exercised.
    case "\$*" in
      *"-F #{pane_id}"*)
        i=1; while [ "\$i" -le "\${LIVE_PANES:-2}" ]; do printf '%%%s\n' "\$i"; i=\$((i+1)); done ;;
      *) printf '' ;;
    esac ;;
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

# Two panes of ONE window (same session + window_index), both carrying the
# window's 2-pane layout string.
SNAP="$TMP/s.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":2,"window_name":"w","cwd":"$CWD1","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w","cwd":"$CWD2","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

SCRIPT="${NECRO_RESTORE_SCRIPT:-$ROOT/scripts/necro-restore.sh}"
fails=0

echo "whole window selected"
: > "$CALLS"; rm -f "$SESS_FLAG"
LIVE_PANES=2 bash "$SCRIPT" "$SNAP" --resume-delay 0 --resume-message '' >/dev/null 2>&1
n=$(grep -c "^select-layout .* $LAYOUT" "$CALLS" || true)
if [ "$n" -eq 1 ]; then
  echo "  ok: layout replayed once"
else
  echo "  FAIL: expected 1 select-layout, got $n"
  fails=$((fails + 1))
fi

echo
echo "half the window selected"
: > "$CALLS"; rm -f "$SESS_FLAG"
out="$(LIVE_PANES=1 bash "$SCRIPT" "$SNAP" --only '%1' --resume-delay 0 --resume-message '' 2>&1)"
n=$(grep -c "^select-layout" "$CALLS" || true)
if [ "$n" -eq 0 ]; then
  echo "  ok: no select-layout for a partial window"
else
  echo "  FAIL: replayed a whole-window layout onto a partial restore ($n call(s))"
  grep '^select-layout' "$CALLS" || true
  fails=$((fails + 1))
fi

case "$out" in
  *"partial selection (1 of 2 panes)"*)
    echo "  ok: says why it skipped" ;;
  *)
    echo "  FAIL: no 'partial selection' explanation in output"
    printf '%s\n' "$out" | grep -i layout || true
    fails=$((fails + 1)) ;;
esac

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS: necro-restore-only-layout-test"
