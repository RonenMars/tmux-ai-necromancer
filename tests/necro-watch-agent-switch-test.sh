#!/usr/bin/env bash
# necro-watch-agent-switch-test.sh — when one agent replaces another in a pane
# between two watcher ticks, the old agent's pin must not survive.
#
# Observed on a real server: cursor-agent in pane %335 was pinned to its chat id,
# the user quit it and started codex within one 30s tick, so no tick ever saw the
# shell. Case 3 (exit) needs no agent in the foreground and Case 1 (restart)
# needs exited=1, so neither fired. The Cursor chat id stayed in @necro_uuid,
# and every snapshot recorded `codex resume <cursor chat id>`, which fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_LIMIT_CHECK_INTERVAL=0
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
CWD="$TMP/work"
mkdir -p "$CWD"

OLD=73f83129-66bf-4bc7-b45a-3e33ed982e38   # the cursor chat id
NEW=01a1b946-7d4d-7eb0-a05c-f00a1a86d788   # the codex session now running

STATE="$TMP/pane-opts"
# Pinned by an earlier tick while cursor-agent ran; never marked exited.
printf '%%1|@necro_uuid=%s\n' "$OLD" > "$STATE"
printf '%%1|@necro_cmd=node\n' >> "$STATE"
printf '%%1|@necro_agent=cursor\n' >> "$STATE"
printf '%%1|@necro_pane_first_seen=1\n' >> "$STATE"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-options) printf '@necromancer_agents "claude codex cursor"\n'; exit 0 ;;
  show-option)
    if [ "$2" = "-gqv" ]; then printf '\n'; exit 0; fi
    opt="${5:-}"
    line="$(grep -F "|$opt=" "$STATE" 2>/dev/null | tail -1)"
    [ -n "$line" ] && printf '%s\n' "${line#*=}"
    exit 0 ;;
  set-option)
    [ "$2" = "-gq" ] && exit 0
    if [ "$2" = "-pu" ]; then printf '%s|%s=\n' "$4" "$5" >> "$STATE"; exit 0; fi
    printf '%s|%s=%s\n' "$4" "$5" "${6:-}" >> "$STATE"
    exit 0 ;;
  list-panes)
    _o() { line="$(grep -F "%1|$1=" "$STATE" 2>/dev/null | tail -1)"; printf '%s' "${line#*=}"; }
    printf '%%1\x1fcodex\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f999\n' \
      "$(_o @necro_uuid)" "$(_o @necro_cmd)" "$(_o @necro_agent)" \
      "$(_o @necro_agent_exited)" "$(_o @necro_pane_first_seen)" "$CWD"
    exit 0 ;;
  display-message) printf '999\n'; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# The pane's child is codex, resumed with its real id — the argv ground truth.
printf '#!/usr/bin/env bash\n[ "$2" = "999" ] && echo 1234\nexit 0\n' > "$TMPBIN/pgrep"
cat > "$TMPBIN/ps" <<EOF
#!/usr/bin/env bash
case "\$2" in
  comm=)    echo codex ;;
  command=) echo "codex resume $NEW" ;;
esac
EOF
chmod +x "$TMPBIN/pgrep" "$TMPBIN/ps"
export PATH="$TMPBIN:$PATH"

bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1

opt() { grep -F "%1|$1=" "$STATE" | tail -1 | cut -d= -f2-; }
uuid="$(opt @necro_uuid)"; agent="$(opt @necro_agent)"; cmd="$(opt @necro_cmd)"

fail=0
[ "$uuid" = "$NEW" ]    || { echo "FAIL: @necro_uuid=$uuid, want the codex id $NEW (the cursor pin survived the switch)" >&2; fail=1; }
[ "$agent" = "codex" ]  || { echo "FAIL: @necro_agent=$agent, want codex" >&2; fail=1; }
[ "$cmd" = "codex" ]    || { echo "FAIL: @necro_cmd=$cmd, want codex" >&2; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "PASS: a pane whose agent changed between ticks is re-pinned to the new agent's session"
