#!/usr/bin/env bash
# necro-snapshot-pin-agent-mismatch-test.sh — a pane pinned while one agent ran
# (@necro_agent=cursor) and now running another (codex) must not have the old
# pin recorded as the new agent's session. Otherwise the record restores as
# `codex resume <cursor chat id>`, which fails. Companion to
# necro-watch-agent-switch-test.sh: this covers snapshots taken before the
# watcher's next tick re-pins the pane.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
CWD="$TMP/work"
mkdir -p "$CWD"
OLD=73f83129-66bf-4bc7-b45a-3e33ed982e38

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes) printf '%%1\ts\t1\tw\t$CWD\tcodex\tlayout\t0\t1\t1\t999\n' ;;
  show-option)
    case "\${5:-}" in
      @necro_uuid)  echo "$OLD" ;;
      @necro_agent) echo cursor ;;
    esac ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null 2>&1

SNAP="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.idle-only.jsonl | head -1)"
agent="$(jq -r '.agent' "$SNAP")"
uuid="$(jq -r '.uuid' "$SNAP")"

fail=0
[ "$agent" = "codex" ] || { echo "FAIL: agent=$agent, want codex" >&2; fail=1; }
[ "$uuid" != "$OLD" ]  || { echo "FAIL: the cursor pin $OLD was recorded as the codex session" >&2; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "PASS: a pin left by a different agent is not recorded as the current agent's session"
