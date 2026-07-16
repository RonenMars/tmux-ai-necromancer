#!/usr/bin/env bash
# necro-snapshot-layout-field-test.sh — snapshot records carry a window_layout
# field scraped from tmux #{window_layout}.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CWD="$TMP/w"; mkdir -p "$CWD"
LAYOUT='c005,364x71,0,0{182x71,0,0,5,181x71,183,0,8}'

# Mock tmux: one idle pane, known window_layout, no agent.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes)
    printf '%%1\ts\t2\tw\t$CWD\tzsh\t$LAYOUT\n' ;;
  show-option) printf '' ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null 2>&1
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl | head -1)"
got="$(jq -r '.window_layout' "$OUT")"
[ "$got" = "$LAYOUT" ] || { echo "FAIL: window_layout=$got want=$LAYOUT"; cat "$OUT"; exit 1; }
echo "PASS: necro-snapshot-layout-field-test"
