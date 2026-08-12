#!/usr/bin/env bash
# Numeric snapshot session names must be explicit session targets in every
# target-window command. Otherwise '=2' can select window index 2 in the
# current session, marking the wrong initial pane and adding later windows to
# the wrong session.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_RESUME_MESSAGE=""
mkdir -p "$HOME"

CWD="$TMP/work"
mkdir -p "$CWD"
TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"
SESSION_CREATED="$TMP/session-created"
MARKFILE="$TMP/mark"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
case "\$1" in
  has-session) [ -f "$SESSION_CREATED" ] ;;
  new-session) touch "$SESSION_CREATED" ;;
  show-option) exit 0 ;;
  set-option)
    case "\$*" in *'@necro_id'*) printf '%s' "\${@: -1}" > "$MARKFILE" ;; esac
    ;;
  list-panes)
    mark=""; [ -f "$MARKFILE" ] && mark="\$(cat "$MARKFILE")"
    case " \$* " in
      *' -s -t =2: '*)
        case "\$*" in
          *'#{window_index}\t#{window_name}'*) printf '1\tw1\t%%20\t$CWD\t%s\n' "\$mark" ;;
          *'#{@necro_id}\t#{pane_id}'*)        printf '%s\t%%20\n' "\$mark" ;;
          *'#{@necro_id}'*)                    printf '%s\n' "\$mark" ;;
          *)                                   printf '%%20\n' ;;
        esac
        ;;
      *' -t =2: '*) printf '%%20\n' ;;
      *' -t =2 '*)  printf '%%10\n' ;;
      *' -t @21 '*) printf '%%21\n' ;;
      *) exit 1 ;;
    esac
    ;;
  list-windows) printf '@20\n' ;;
  new-window) printf '@21\n' ;;
  display-message)
    case "\$*" in *'#{window_id}'*) printf '@20\n' ;; *) printf 'zsh\n' ;; esac
    ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%20","session":"2","window_index":1,"window_name":"w1","cwd":"$CWD","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%21","session":"2","window_index":2,"window_name":"w2","cwd":"$CWD","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"

# Dry-run output is part of the recovery interface: it must show the same
# disambiguated target that the real command will execute.
printf 'unrelated' > "$MARKFILE"
dry_out="$(bash "$ROOT/scripts/necro-restore.sh" --dry-run "$SNAP" 2>&1)"

fails=0
if ! grep -F 'list-panes -t =2: -F #{pane_id}' "$CALLS" >/dev/null; then
  echo "FAIL: fresh numeric session did not claim its own initial pane" >&2
  fails=$((fails + 1))
fi
if ! grep -F 'new-window -d -t =2:' "$CALLS" >/dev/null; then
  echo "FAIL: later window was not added to the numeric snapshot session" >&2
  fails=$((fails + 1))
fi
if grep -F 'list-panes -t =2 -F #{pane_id}' "$CALLS" >/dev/null || \
   grep -F 'new-window -d -t =2 ' "$CALLS" >/dev/null; then
  echo "FAIL: restore used an ambiguous numeric target-window" >&2
  fails=$((fails + 1))
fi
if ! grep -F 'DRY: tmux new-window -t =2:' <<<"$dry_out" >/dev/null || \
   grep -F 'DRY: tmux new-window -t =2 -c' <<<"$dry_out" >/dev/null; then
  echo "FAIL: dry-run reported an ambiguous numeric target-window" >&2
  fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then
  echo "--- restore output ---" >&2; echo "$out" >&2
  echo "--- tmux calls ---" >&2; cat "$CALLS" >&2
  exit 1
fi
echo "PASS: numeric session creation marks and adds windows in the intended session"
