#!/usr/bin/env bash
# necro-watch-first-seen-reset-on-restart-test.sh — Case 1 (agent relaunched
# in a pane that previously exited cleanly) must clear @necro_pane_first_seen
# along with the other @necro_* options, so the second launch gets its own
# fresh first-seen stamp instead of inheriting the first launch's. Regression
# target: a stale first_seen from launch #1 could reject launch #2's own
# legitimate transcript via the min_epoch filter.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_LIMIT_CHECK_INTERVAL=0  # disable auto limit-save; this test asserts watcher behaviour
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
CWD="$TMP/work"
mkdir -p "$CWD" "$HOME/.claude/projects/${CWD//\//-}"

STATE="$TMP/pane-opts"
# Seed state as if a prior necro-watch.sh run already pinned this pane and
# then saw it exit: @necro_uuid/@necro_cmd/@necro_agent set, exited=1, and an
# old first_seen from launch #1.
printf '%%1|@necro_uuid=11111111-1111-1111-1111-111111111111\n' > "$STATE"
printf '%%1|@necro_cmd=claude\n' >> "$STATE"
printf '%%1|@necro_agent=claude\n' >> "$STATE"
printf '%%1|@necro_agent_exited=1\n' >> "$STATE"
printf '%%1|@necro_pane_first_seen=1\n' >> "$STATE"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-option)
    if [ "$2" = "-gqv" ]; then
      opt="$3"
      case "$opt" in
        @necromancer_last_watch) printf '0\n' ;;
        @necromancer_agents) printf 'claude\n' ;;
        *) printf '\n' ;;
      esac
      exit 0
    fi
    opt="${5:-}"
    line="$(grep -F "|$opt=" "$STATE" 2>/dev/null | tail -1)"
    if [ -n "$line" ]; then printf '%s\n' "${line#*=}"; fi
    exit 0
    ;;
  set-option)
    if [ "$2" = "-gq" ]; then exit 0; fi
    if [ "$2" = "-pu" ]; then
      pane="$4"; opt="$5"
      printf '%s|%s=\n' "$pane" "$opt" >> "$STATE"
      exit 0
    fi
    pane="$4"; opt="$5"; val="${6:-}"
    printf '%s|%s=%s\n' "$pane" "$opt" "$val" >> "$STATE"
    exit 0
    ;;
  list-panes)
    # Pane options now ride along in the list-panes format, so the stub must
    # report them from the same STATE the set-option branch writes.
    _o() { line="$(grep -F "%1|$1=" "$STATE" 2>/dev/null | tail -1)"; printf '%s' "${line#*=}"; }
    printf '%%1\x1fclaude\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
      "$(_o @necro_uuid)" "$(_o @necro_cmd)" "$(_o @necro_agent)" \
      "$(_o @necro_agent_exited)" "$(_o @necro_pane_first_seen)" "$CWD"
    exit 0 ;;
  display-message) printf '999\n'; exit 0 ;;
  capture-pane) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# No argv/scrollback hit — the relaunch falls to cursor-pop, which is exactly
# where a stale inherited first_seen would matter.
cat > "$TMPBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPBIN/pgrep"
cat > "$TMPBIN/ps" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPBIN/ps"
export PATH="$TMPBIN:$PATH"

before="$(date +%s)"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
after="$(date +%s)"

new_first_seen="$(grep -F '%1|@necro_pane_first_seen=' "$STATE" | tail -1 | cut -d= -f2-)"

[ -n "$new_first_seen" ] || { echo "FAIL: first_seen not restamped after restart" >&2; exit 1; }
[ "$new_first_seen" != "1" ] || { echo "FAIL: first_seen still holds launch #1's stale value (1)" >&2; exit 1; }
[ "$new_first_seen" -ge "$before" ] && [ "$new_first_seen" -le "$after" ] || {
  echo "FAIL: new first_seen ($new_first_seen) not within this run's time window [$before, $after]" >&2
  exit 1
}
echo "PASS: first_seen resets to a fresh timestamp when the agent restarts after exit"
