#!/usr/bin/env bash
# The snapshot and doctor read #{pane_pid} from their existing list-panes call,
# so a node-wrapped Cursor pane needs no per-pane `display-message` to resolve it.
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
  list-panes)
    case "\$*" in
      *session_name*) printf '%%1\ts\t0\tw\t$TMP/w\tnode\tL\t0\t1\t1\t4242\n' ;;
      *) printf '%%1\tnode\t4242\n' ;;
    esac ;;
  show-options) printf '@necromancer_agents cursor\n' ;;
  show-option|display-message) printf '' ;;
  *) exit 0 ;;
esac
EOF
printf '#!/usr/bin/env bash\necho 4343\n' > "$TMP/bin/pgrep"
cat > "$TMP/bin/ps" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *command=*) echo "S+ /x/agent /x/cursor-agent/versions/1/index.js" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

fail=0
check() { [ "$2" = "$3" ] && echo "  ok: $1" || { echo "  FAIL: $1 (want '$2' got '$3')"; fail=1; }; }

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >"$TMP/out" 2>&1
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl 2>/dev/null | head -1)"
check "snapshot: node pane recorded as cursor" cursor "$(jq -r '.agent' "$OUT" 2>/dev/null)"
check "snapshot: no pane_pid display-message" 0 "$(grep -c 'display-message.*pane_pid' "$CALLS")"
check "snapshot: pane_pid in list-panes format" 1 "$(grep -c 'list-panes.*pane_pid' "$CALLS" | sed 's/^[1-9].*/1/')"

: > "$CALLS"
DOCTOR="$(bash "$ROOT/scripts/necro-doctor.sh" 2>&1)"
check "doctor: node pane counted as a cursor agent" 1 "$(printf '%s\n' "$DOCTOR" | grep -c '1 running a known agent')"
check "doctor: no pane_pid display-message" 0 "$(grep -c 'display-message.*pane_pid' "$CALLS")"
check "doctor: pane_pid in list-panes format" 1 "$(grep -c 'list-panes.*pane_pid' "$CALLS" | sed 's/^[1-9].*/1/')"

[ "$fail" = 0 ] && echo PASS || { echo FAILED; exit 1; }
