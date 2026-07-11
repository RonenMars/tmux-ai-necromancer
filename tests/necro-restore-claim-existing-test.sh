#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
UUID="11111111-1111-1111-1111-111111111111"
mkdir -p "$CWD" "$HOME/.claude/projects/${CWD//\//-}"
printf 'transcript\n' > "$HOME/.claude/projects/${CWD//\//-}/$UUID.jsonl"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  has-session)
    exit 0
    ;;
  show-option)
    exit 0
    ;;
  list-panes)
    case "\$*" in
      *'#{@necro_id}'*'#{pane_id}'*)
        printf '\t%%1\n'
        ;;
      *'#{window_index}'*'#{window_name}'*'#{pane_id}'*'#{pane_current_path}'*)
        printf '1\tw\t%%1\t$CWD\t\n'
        ;;
      *)
        printf '%%1\n'
        ;;
    esac
    ;;
  list-windows)
    printf '@1\n'
    ;;
  display-message)
    printf 'zsh\n'
    ;;
  new-window)
    echo "unexpected new-window" >&2
    exit 9
    ;;
  split-window)
    echo "unexpected split-window" >&2
    exit 9
    ;;
  list-sessions)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/snapshot.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"$UUID","uuid_source":"pane-option","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

out="$(bash "$ROOT/scripts/necro-restore.sh" --dry-run "$SNAP" 2>&1)"

grep -F "existing pane matches snapshot — claiming marker" <<<"$out" >/dev/null || {
  echo "missing claim message" >&2
  echo "$out" >&2
  exit 1
}

grep -F "windows added: 0, reused: 1, agents resumed: 1" <<<"$out" >/dev/null || {
  echo "unexpected restore summary" >&2
  echo "$out" >&2
  exit 1
}

if grep -F "new-window" <<<"$out" >/dev/null; then
  echo "restore attempted to add a duplicate window" >&2
  echo "$out" >&2
  exit 1
fi
