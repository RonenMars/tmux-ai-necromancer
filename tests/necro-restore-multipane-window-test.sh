#!/usr/bin/env bash
# necro-restore-multipane-window-test.sh — records that share (session,
# window_index) restore into ONE window (split-window), not N windows.
# The first record creates the window; each later record with the same
# (session, window_index) splits into it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/tmux-calls.log"

CWD1="$TMP/w1"; CWD2="$TMP/w2"; CWD3="$TMP/w3"
mkdir -p "$CWD1" "$CWD2" "$CWD3"

# Stateful session mock: has-session fails until new-session runs, then succeeds
# (so records 2 & 3 see an existing session, as in a real restore).
SESS_FLAG="$TMP/session-created"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session)  [ -f "$SESS_FLAG" ] && exit 0 || exit 1 ;;
  new-session)  : > "$SESS_FLAG"; exit 0 ;;
  list-windows)
    case "\$*" in
      *'#{@necro_id}'*'#{window_id}'*) printf '' ;;   # no markers yet
      *'#{window_index}'*'#{window_name}'*) printf '' ;;
      *) printf '@1\n' ;;                             # session initial window
    esac ;;
  new-window)   printf '@10\n' ;;               # id of a newly added window
  split-window) printf '%%20\n' ;;              # id of a newly added pane
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":2,"window_name":"w","cwd":"$CWD1","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w","cwd":"$CWD2","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%3","session":"s","window_index":2,"window_name":"w","cwd":"$CWD3","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"

# Three records, one window_index=2 → exactly one window creation for that group
# (the session's initial window is claimed by record 1), and 2 splits for the rest.
nw=$(grep -c '^new-window' "$CALLS" || true)
ns=$(grep -c '^split-window' "$CALLS" || true)

# Record 1 claims the session's initial window (fresh session) — so 0 new-window
# calls, and records 2 & 3 split into it → 2 split-window calls.
[ "$ns" -eq 2 ] || { echo "FAIL: expected 2 split-window calls, got $ns"; echo "--- calls ---"; cat "$CALLS"; echo "--- out ---"; echo "$out"; exit 1; }
[ "$nw" -eq 0 ] || { echo "FAIL: expected 0 new-window (initial window claimed), got $nw"; cat "$CALLS"; exit 1; }

echo "PASS: necro-restore-multipane-window-test"
