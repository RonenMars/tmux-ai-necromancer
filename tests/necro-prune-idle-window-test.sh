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
KILLS="$TMP/kills"
: > "$KILLS"

# Window @1: pane pid 1001 has a child (busy). Window @2: pane pid 1002 idle.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes)
    printf '@1 1001\n@2 1002\n'
    ;;
  list-windows)
    printf '@1 sess:0\n@2 sess:1\n'
    ;;
  kill-window)
    # args: kill-window -t <wid>
    printf '%s\n' "\$3" >> "$KILLS"
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# pgrep -P <pid>: only 1001 has a child.
cat > "$TMPBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-P" ] && [ "$2" = "1001" ] && { echo 2001; exit 0; }
exit 1
EOF
chmod +x "$TMPBIN/pgrep"

export PATH="$TMPBIN:$PATH"
unset TMUX

bash "$ROOT/scripts/necro-prune.sh" >/dev/null

killed="$(cat "$KILLS")"

[ "$killed" = "@2" ] || {
  echo "expected only idle window @2 to be killed, got: [$killed]" >&2
  exit 1
}

# --dry-run must kill nothing.
: > "$KILLS"
bash "$ROOT/scripts/necro-prune.sh" --dry-run >/dev/null
[ ! -s "$KILLS" ] || {
  echo "dry-run killed windows: $(cat "$KILLS")" >&2
  exit 1
}

echo "ok"
