#!/usr/bin/env bash
# An agent with no exit keys (Cursor) must not be prompted, sent keys, waited on
# for 20s, or reported as exited by `--yes`: the snapshot records its filesystem
# id and leaves the pane alone. Runs under a real pty so the tty guard passes.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin" "$TMP/w"
CALLS="$TMP/calls"; : > "$CALLS"

cat > "$TMP/bin/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  list-panes) printf '%%1\ts\t0\tw\t$TMP/w\tcursor-agent\tL\t0\t1\t1\t4242\n' ;;
  show-options) printf '@necromancer_agents cursor\n' ;;
  display-message) printf 'cursor-agent\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

start=$(date +%s)
python3 - "$ROOT/scripts/necro-snapshot.sh" > "$TMP/out" 2>&1 <<'PY'
import os, pty, sys
sys.exit(os.waitstatus_to_exitcode(pty.spawn(["bash", sys.argv[1], "--yes"])))
PY
elapsed=$(( $(date +%s) - start ))

fail=0
check() { [ "$2" = "$3" ] && echo "  ok: $1" || { echo "  FAIL: $1 (want '$2' got '$3')"; fail=1; }; }
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl 2>/dev/null | head -1)"
written=0; [ -n "$OUT" ] && [ "${OUT%.idle-only.jsonl}" = "$OUT" ] && written=1
check "snapshot written (tty guard passed, not idle-only)" 1 "$written"
check "no send-keys" 0 "$(grep -c '^send-keys' "$CALLS")"
check "no 'sending exit keys' claim" 0 "$(grep -c 'sending exit keys' "$TMP/out")"
check "no 20s wait warning" 0 "$(grep -c 'still shows cmd' "$TMP/out")"
check "returned in under 10s" 1 "$([ "$elapsed" -lt 10 ] && echo 1 || echo 0)"
check "record kept for the pane" cursor "$(jq -r '.agent' "$OUT" 2>/dev/null)"

[ "$fail" = 0 ] && echo PASS || { echo FAILED; cat "$TMP/out"; exit 1; }
