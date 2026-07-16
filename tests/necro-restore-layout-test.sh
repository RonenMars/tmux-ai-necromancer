#!/usr/bin/env bash
# necro-restore-layout-test.sh — a 2-pane window group whose records carry a
# window_layout string triggers exactly one select-layout on the group's window,
# and only when live pane count matches the saved count.
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
  list-panes)   printf '%%1\n%%20\n' ;;   # 2 live panes in the group window
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/s.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":2,"window_name":"w","cwd":"$CWD1","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w","cwd":"$CWD2","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
n=$(grep -c "^select-layout .* $LAYOUT" "$CALLS" || true)
[ "$n" -eq 1 ] || { echo "FAIL: expected 1 select-layout with layout, got $n"; grep select-layout "$CALLS" || true; exit 1; }
echo "PASS: necro-restore-layout-test"
