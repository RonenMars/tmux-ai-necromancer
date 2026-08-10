#!/usr/bin/env bash
# necro-restore-split-order-test.sh — each split targets the PREVIOUS pane of
# the group, not the window.
#
# `split-window -t <window>` splits that window's ACTIVE pane, and `-d` keeps
# the new pane from becoming active — so every split hits the same pane and
# each new pane is inserted directly after it, reversing records 2..N. The
# layout replay then places contents by pane index, so a 3-pane window comes
# back with its panes holding each other's agents. Verified against tmux: three
# `split-window -d -t <window>` calls yield index order 1,3,2.
#
# Two panes cannot show the bug (one split, nothing to reorder), so this test
# uses three.
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

# Stateful mock. Record 1 claims the session's initial pane (%100); each split
# hands back the next id so the test can assert what the NEXT split targets.
SESS_FLAG="$TMP/session-created"
SPLIT_N="$TMP/split-count"
echo 0 > "$SPLIT_N"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session)  [ -f "$SESS_FLAG" ] && exit 0 || exit 1 ;;
  new-session)  : > "$SESS_FLAG"; exit 0 ;;
  list-panes)   printf '%%100\n' ;;             # session's initial pane
  list-windows)
    case "\$*" in
      *'#{@necro_id}'*'#{window_id}'*) printf '' ;;
      *'#{window_index}'*'#{window_name}'*) printf '' ;;
      *) printf '@1\n' ;;
    esac ;;
  new-window)   printf '@10\n' ;;
  split-window)
    n=\$(( \$(cat "$SPLIT_N") + 1 )); echo "\$n" > "$SPLIT_N"
    printf '%%10%s\n' "\$n" ;;                  # %101, %102, ...
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

# Record 1 claims %100; record 2 must split from %100; record 3 from %101.
split1="$(grep '^split-window' "$CALLS" | sed -n '1p')"
split2="$(grep '^split-window' "$CALLS" | sed -n '2p')"

case "$split1" in
  *"-t %100"*) ;;
  *) echo "FAIL: first split should target the claimed pane %100, got: $split1"
     echo "--- calls ---"; cat "$CALLS"; echo "--- out ---"; echo "$out"; exit 1 ;;
esac

case "$split2" in
  *"-t %101"*) ;;
  *) echo "FAIL: second split should target the first split's pane %101, got: $split2"
     echo "       (targeting the window re-splits the same active pane and"
     echo "        reverses pane order — see the header of this test)"
     echo "--- calls ---"; cat "$CALLS"; echo "--- out ---"; echo "$out"; exit 1 ;;
esac

echo "PASS: necro-restore-split-order-test"
