#!/usr/bin/env bash
# Invariant 2 (per-pane restore idempotency): numeric session names must be
# disambiguated from numeric window indexes when looking up @necro_id markers.
# Without a trailing ':' on the target, tmux can resolve '=2' to window 2 in
# the current session instead of session 2, causing a partial rerun to add a
# duplicate window and resume the same conversation twice.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_RESUME_MESSAGE=""
mkdir -p "$HOME"

CWD="$TMP/work"
UUID="11111111-1111-1111-1111-111111111111"
MARK="$CWD|$UUID"
PROJ_DIR="$(
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/agents/claude.sh"
  agent_claude_project_dir "$CWD"
)"
mkdir -p "$CWD" "$PROJ_DIR"
printf 'transcript\n' > "$PROJ_DIR/$UUID.jsonl"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
case "\$1" in
  has-session) exit 0 ;;
  show-option) exit 0 ;;
  list-panes)
    case " \$* " in
      *' -t =2: '*)
        case "\$*" in
          *'#{window_index}\t#{window_name}'*) printf '1\tw\t%%20\t$CWD\t%s\n' '$MARK' ;;
          *'#{@necro_id}\t#{pane_id}'*)        printf '%s\t%%20\n' '$MARK' ;;
          *'#{@necro_id}'*)                    printf '%s\n' '$MARK' ;;
          *)                                   printf '%%20\n' ;;
        esac
        ;;
      *' -t =2 '*)
        case "\$*" in
          *'#{window_index}\t#{window_name}'*) printf '2\tother\t%%10\t/tmp/other\tunrelated\n' ;;
          *'#{@necro_id}\t#{pane_id}'*)        printf 'unrelated\t%%10\n' ;;
          *'#{@necro_id}'*)                    printf 'unrelated\n' ;;
          *)                                   printf '%%10\n' ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    ;;
  display-message)
    case "\$*" in
      *'#{pane_current_command}'*) printf 'claude\n' ;;
      *) printf '\n' ;;
    esac
    ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%20","session":"2","window_index":1,"window_name":"w","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID","uuid_source":"test","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" --dry-run "$SNAP" 2>&1)"

fails=0
if ! grep -F "already restored (marker) — reusing" <<<"$out" >/dev/null; then
  echo "FAIL: numeric session marker was not reused" >&2
  fails=$((fails + 1))
fi
if ! grep -F "windows added: 0, reused: 1, agents resumed: 0" <<<"$out" >/dev/null; then
  echo "FAIL: restore proposed duplicate work for an existing numeric-session pane" >&2
  fails=$((fails + 1))
fi
if grep -F "DRY: tmux new-window" <<<"$out" >/dev/null; then
  echo "FAIL: restore proposed a duplicate window" >&2
  fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then
  echo "--- restore output ---" >&2; echo "$out" >&2
  echo "--- tmux calls ---" >&2; cat "$CALLS" >&2
  exit 1
fi
echo "PASS: numeric session targets reuse the correct pane without double-resuming"
