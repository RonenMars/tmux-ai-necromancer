#!/usr/bin/env bash
# A copilot snapshot record restores as `copilot --resume <id>` in a fresh pane.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" NECROMANCER_SNAPSHOT_DIR="$TMP/snap" NECROMANCER_RESUME_MESSAGE="" NECROMANCER_RESUME_START_DELAY=0
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin" "$TMP/w"
CALLS="$TMP/calls.log"; UUID="aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
cat > "$TMP/bin/tmux" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session) exit 1 ;;
  list-windows) case "\$*" in *'#{window_id}'*) printf '@1\n' ;; esac ;;
  list-panes) printf '%%1\n' ;;
  display-message) printf 'zsh\n' ;;
esac
exit 0
EOS
chmod +x "$TMP/bin/tmux"; export PATH="$TMP/bin:$PATH"
cat > "$TMP/s.jsonl" <<EOS
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w","cwd":"$TMP/w","prev_cmd":"copilot","agent":"copilot","uuid":"$UUID","uuid_source":"argv","window_layout":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOS
bash "$ROOT/scripts/necro-restore.sh" "$TMP/s.jsonl" >/dev/null 2>&1
grep -qF "send-keys -t %1 copilot --resume $UUID Enter" "$CALLS" \
  && echo "PASS: copilot record restores via copilot --resume" \
  || { echo "FAIL: resume not sent"; cat "$CALLS"; exit 1; }
