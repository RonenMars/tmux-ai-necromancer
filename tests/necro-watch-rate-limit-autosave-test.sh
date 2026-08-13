#!/usr/bin/env bash
# Watcher auto-saves rate-limited panes on a throttled interval (not every
# watch tick), and clears @necro_limit_saved when an agent restarts after exit
# so a later limit event can be saved again.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_LOG_DIR="$TMP/logs"
export NECROMANCER_LIMIT_SAVE_SYNC=1  # deterministic: no background race in assertions
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
CWD="$TMP/work"
mkdir -p "$CWD"

STATE="$TMP/pane-opts"
SNAP_INVOCATIONS="$TMP/snapshot-invocations.log"
LAST_LIMIT_FILE="$TMP/last_limit_check"
: > "$SNAP_INVOCATIONS"
echo 0 > "$LAST_LIMIT_FILE"

# Seed: pinned live agent.
printf '%%1|@necro_uuid=11111111-1111-1111-1111-111111111111\n' > "$STATE"
printf '%%1|@necro_cmd=claude\n' >> "$STATE"
printf '%%1|@necro_agent=claude\n' >> "$STATE"
printf '%%1|@necro_pane_first_seen=100\n' >> "$STATE"
printf '%%1|@necro_limit_saved=1\n' >> "$STATE"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
LAST_LIMIT_FILE="$LAST_LIMIT_FILE"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-option)
    if [ "$2" = "-gqv" ]; then
      opt="$3"
      case "$opt" in
        @necromancer_last_watch) printf '0\n' ;;
        @necromancer_last_limit_check) cat "$LAST_LIMIT_FILE" 2>/dev/null; printf '\n' ;;
        @necromancer_limit_check_interval) printf '60\n' ;;
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
  show-options)
    printf '@necromancer_last_watch 0\n'
    printf '@necromancer_last_limit_check %s\n' "$(cat "$LAST_LIMIT_FILE" 2>/dev/null || echo 0)"
    printf '@necromancer_limit_check_interval 60\n'
    printf '@necromancer_agents claude\n'
    exit 0
    ;;
  set-option)
    if [ "$2" = "-gq" ]; then
      if [ "$3" = "@necromancer_last_limit_check" ]; then
        printf '%s' "$4" > "$LAST_LIMIT_FILE"
      fi
      exit 0
    fi
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

# Watch resolves SELF_DIR from BASH_SOURCE and calls $SELF_DIR/necro-snapshot.sh.
# Run a copy whose sibling snapshot is a stub that logs argv.
FAKE_ROOT="$TMP/plugin"
mkdir -p "$FAKE_ROOT/scripts" "$FAKE_ROOT/lib/agents"
for f in "$ROOT/lib"/*.sh; do ln -s "$f" "$FAKE_ROOT/lib/$(basename "$f")"; done
for f in "$ROOT/lib/agents"/*.sh; do ln -s "$f" "$FAKE_ROOT/lib/agents/$(basename "$f")"; done
cp "$ROOT/scripts/necro-watch.sh" "$FAKE_ROOT/scripts/necro-watch.sh"
cat > "$FAKE_ROOT/scripts/necro-snapshot.sh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$SNAP_INVOCATIONS"
exit 0
EOF
chmod +x "$FAKE_ROOT/scripts/necro-snapshot.sh"

export PATH="$TMPBIN:$PATH"

# --- Case A: interval not due → no snapshot invocation ----------------------
rm -rf "$NECROMANCER_SNAPSHOT_DIR/.watch.lock" "$NECROMANCER_SNAPSHOT_DIR/.limit-save.lock"
: > "$SNAP_INVOCATIONS"
date +%s > "$LAST_LIMIT_FILE"
bash "$FAKE_ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
if [ -s "$SNAP_INVOCATIONS" ]; then
  echo "FAIL: snapshot invoked while limit-check interval not due:" >&2
  cat "$SNAP_INVOCATIONS" >&2
  exit 1
fi

# --- Case B: interval due → --rate-limited --auto fired ---------------------
rm -rf "$NECROMANCER_SNAPSHOT_DIR/.watch.lock" "$NECROMANCER_SNAPSHOT_DIR/.limit-save.lock"
: > "$SNAP_INVOCATIONS"
echo 0 > "$LAST_LIMIT_FILE"
bash "$FAKE_ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
if ! grep -q -- '--rate-limited' "$SNAP_INVOCATIONS"; then
  echo "FAIL: expected --rate-limited auto-save when interval due:" >&2
  cat "$SNAP_INVOCATIONS" >&2
  exit 1
fi
if ! grep -q -- '--auto' "$SNAP_INVOCATIONS"; then
  echo "FAIL: auto-save must pass --auto:" >&2
  cat "$SNAP_INVOCATIONS" >&2
  exit 1
fi
got_last="$(cat "$LAST_LIMIT_FILE")"
[ -n "$got_last" ] && [ "$got_last" != "0" ] || {
  echo "FAIL: @necromancer_last_limit_check was not updated (got '$got_last')" >&2
  exit 1
}

# --- Case C: agent restart clears @necro_limit_saved ------------------------
rm -rf "$NECROMANCER_SNAPSHOT_DIR/.watch.lock"
printf '%%1|@necro_uuid=11111111-1111-1111-1111-111111111111\n' > "$STATE"
printf '%%1|@necro_cmd=claude\n' >> "$STATE"
printf '%%1|@necro_agent=claude\n' >> "$STATE"
printf '%%1|@necro_agent_exited=1\n' >> "$STATE"
printf '%%1|@necro_pane_first_seen=1\n' >> "$STATE"
printf '%%1|@necro_limit_saved=1\n' >> "$STATE"
date +%s > "$LAST_LIMIT_FILE"  # not due — focus on Case 1 clear
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

bash "$FAKE_ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
last_limit="$(grep -F '%1|@necro_limit_saved=' "$STATE" | tail -1 | cut -d= -f2-)"
if [ -n "$last_limit" ]; then
  echo "FAIL: @necro_limit_saved still set after agent restart (got '$last_limit')" >&2
  grep limit_saved "$STATE" >&2
  exit 1
fi

echo "PASS: necro-watch-rate-limit-autosave-test"
