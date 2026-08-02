#!/usr/bin/env bash
# necro-snapshot-active-zoom-field-test.sh — snapshot records carry zoomed /
# pane_active / window_active flags scraped from tmux, and a mock that omits
# the fields (pre-flag tmux format) still yields valid 0-flag JSON.
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

# Mock tmux: two idle panes in one window — pane %2 is active, window zoomed
# and active; pane %1 is neither.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes)
    printf '%%1\ts\t2\tw\t$CWD\tzsh\t$LAYOUT\t1\t0\t1\n'
    printf '%%2\ts\t2\tw\t$CWD\tzsh\t$LAYOUT\t1\t1\t1\n' ;;
  show-option) printf '' ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null 2>&1
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl | head -1)"

got="$(jq -c '[.zoomed, .pane_active, .window_active]' "$OUT" | tr '\n' ' ')"
want='[1,0,1] [1,1,1] '
[ "$got" = "$want" ] || { echo "FAIL: flags=$got want=$want"; cat "$OUT"; exit 1; }

# Pre-flag mock (7 fields only) — flags must default to 0, JSON stays valid.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes) printf '%%1\ts\t2\tw\t$CWD\tzsh\t$LAYOUT\n' ;;
  show-option) printf '' ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
rm -f "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl
sleep 1  # distinct timestamped filename
bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null 2>&1
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl | head -1)"
got="$(jq -c '[.zoomed, .pane_active, .window_active]' "$OUT")"
[ "$got" = "[0,0,0]" ] || { echo "FAIL: defaulted flags=$got want=[0,0,0]"; cat "$OUT"; exit 1; }

echo "PASS: necro-snapshot-active-zoom-field-test"
