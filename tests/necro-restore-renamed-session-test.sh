#!/usr/bin/env bash
# A tmux after-new-session hook may rename the session we just created (e.g. a
# numeric name -> its cwd basename). Restore must keep targeting the session it
# created, by its snapshot-name tag, not by the stale name: otherwise the
# initial pane isn't claimed and the resume send-keys hit "can't find session".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_RESUME_MESSAGE=""
export NECROMANCER_RESUME_START_DELAY=0
mkdir -p "$HOME"

CWD="$TMP/work"; mkdir -p "$CWD"
UUID="22222222-2222-2222-2222-222222222222"
PROJ_DIR="$(
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/agents/claude.sh"
  agent_claude_project_dir "$CWD"
)"
mkdir -p "$PROJ_DIR"; printf 'transcript\n' > "$PROJ_DIR/$UUID.jsonl"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"; STATE="$TMP/renamed"

# State: after new-session the only session is "renamed" (tagged @necro_session=1).
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
case "\$1" in
  has-session)  [ "\$3" = "=renamed" ] && [ -f "$STATE" ] ;;
  new-session)  touch "$STATE"; printf '\$7\n' ;;
  list-sessions) [ -f "$STATE" ] && printf '1\trenamed\n' ;;
  list-panes)
    case " \$* " in
      *' -t =renamed: '*) printf '%%30\n' ;;
      *) exit 1 ;;
    esac ;;
  list-windows) printf '@30\n' ;;
  show-option)  exit 0 ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"; export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snap.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"1","window_index":1,"window_name":"w","cwd":"$CWD","prev_cmd":"zsh","agent":"claude","uuid":"$UUID","uuid_source":"x","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"

fails=0
grep -F 'set-option -t $7 @necro_session 1' "$CALLS" >/dev/null || { echo "FAIL: created session not tagged with its snapshot name" >&2; fails=$((fails+1)); }
grep -F 'send-keys -t %30 claude --resume' "$CALLS" >/dev/null || { echo "FAIL: resume not sent to the renamed session's pane" >&2; fails=$((fails+1)); }
grep -E "send-keys -t 1:" "$CALLS" >/dev/null && { echo "FAIL: send-keys used the stale session name" >&2; fails=$((fails+1)); }
n="$(grep -c '^new-session' "$CALLS")"
bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
[ "$(grep -c '^new-session' "$CALLS")" = "$n" ] || { echo "FAIL: rerun created a duplicate session" >&2; fails=$((fails+1)); }

[ "$fails" -eq 0 ] || { echo "$out" >&2; cat "$CALLS" >&2; exit 1; }
echo "PASS: restore follows a session renamed by an after-new-session hook"
