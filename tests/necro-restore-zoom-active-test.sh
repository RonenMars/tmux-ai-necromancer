#!/usr/bin/env bash
# necro-restore-zoom-active-test.sh — restore re-applies the saved active pane
# (select-pane), zoom (resize-pane -Z, after the layout replay), and active
# window (select-window) for windows created this run; records without the
# flags (old snapshots) trigger none of those calls.
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

# ── Leg 1: pane 2 active, window zoomed + active ────────────────────────────
SNAP="$TMP/s.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":2,"window_name":"w","cwd":"$CWD1","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","zoomed":1,"pane_active":0,"window_active":1,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w","cwd":"$CWD2","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","zoomed":1,"pane_active":1,"window_active":1,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1

fail() { echo "FAIL: $1"; cat "$CALLS"; exit 1; }

# The split pane (%20) — the active record's pane — is selected and zoomed.
grep -q '^select-pane -t %20$' "$CALLS" || fail "expected select-pane -t %20"
grep -q '^resize-pane -Z -t %20$' "$CALLS" || fail "expected resize-pane -Z -t %20"
grep -q '^select-window -t @1$' "$CALLS" || fail "expected select-window -t @1"
# Zoom must come after the layout replay (select-layout unzooms).
lay_ln=$(grep -n '^select-layout' "$CALLS" | head -1 | cut -d: -f1)
zoom_ln=$(grep -n '^resize-pane -Z' "$CALLS" | head -1 | cut -d: -f1)
[ -n "$lay_ln" ] || fail "expected a select-layout call"
[ "$zoom_ln" -gt "$lay_ln" ] || fail "zoom (line $zoom_ln) must follow select-layout (line $lay_ln)"

# ── Leg 2: pre-flag records — none of the new calls fire ────────────────────
rm -f "$CALLS" "$SESS_FLAG"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":2,"window_name":"w","cwd":"$CWD1","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w","cwd":"$CWD2","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
grep -q '^select-pane' "$CALLS" && fail "old snapshot must not select-pane"
grep -q '^resize-pane -Z' "$CALLS" && fail "old snapshot must not zoom"
grep -q '^select-window' "$CALLS" && fail "old snapshot must not select-window"

echo "PASS: necro-restore-zoom-active-test"
