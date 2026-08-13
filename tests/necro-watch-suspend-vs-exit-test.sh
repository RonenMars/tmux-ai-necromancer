#!/usr/bin/env bash
# necro-watch-suspend-vs-exit-test.sh — Case 3 (agent exited) must not fire
# for a pane whose agent is merely SUSPENDED. pane_current_command follows
# the tty foreground pgrp leader, which flips to the shell when the agent is
# Ctrl-Z'd (codex honors SIGTSTP and stops; claude ignores it) — but the agent
# process is still alive as a pane child. Marking a suspended pane "exited"
# would wipe its pin on the next tick and can permanently lose the UUID for a
# fresh (non-resumed) session via the min_epoch filter. Regression target:
# someone removes the necro_agent_alive_in_pane guard from Case 3 and a
# suspended agent gets treated exactly like a real exit.
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
mkdir -p "$CWD"

STATE="$TMP/pane-opts"

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
        @necromancer_agents) printf 'claude codex\n' ;;
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
    # -p -t <pane> — batched pane option read. $2=-p $3=-t $4=<pane>
    pane="$4"
    for opt in @necro_uuid @necro_cmd @necro_agent @necro_agent_exited @necro_pane_first_seen; do
      line="$(grep -F "$pane|$opt=" "$STATE" 2>/dev/null | tail -1)"
      if [ -n "$line" ]; then
        val="${line#*=}"
        [ -n "$val" ] && printf '%s %s\n' "$opt" "$val"
      fi
    done
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
    # Agent suspended (Ctrl-Z) or exited: pane_current_command reports the
    # shell either way — that's the whole reason Case 3 needs the liveness
    # check instead of trusting this field alone.
    # Pane options now ride along in the list-panes format, so the stub must
    # report them from the same STATE the set-option branch writes.
    _o() { line="$(grep -F "%1|$1=" "$STATE" 2>/dev/null | tail -1)"; printf '%s' "${line#*=}"; }
    printf '%%1\x1fzsh\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
      "$(_o @necro_uuid)" "$(_o @necro_cmd)" "$(_o @necro_agent)" \
      "$(_o @necro_agent_exited)" "$(_o @necro_pane_first_seen)" "$CWD"
    exit 0
    ;;
  display-message) printf '999\n'; exit 0 ;;
  capture-pane) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# pgrep -P <pane_pid> / ps -o comm= -p <child> — real argv shape:
# `ps -o comm= -p "$child"` => $1=-o $2=comm= $3=-p $4=<child>.
cat > "$TMPBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
# -P 999 -> child list
if [ "$1" = "-P" ] && [ "$2" = "999" ]; then
  [ -n "${NECRO_TEST_CHILD_ALIVE:-}" ] && echo "1234"
fi
exit 0
EOF
chmod +x "$TMPBIN/pgrep"

cat > "$TMPBIN/ps" <<'EOF'
#!/usr/bin/env bash
if [ "$4" = "1234" ]; then
  echo "${NECRO_TEST_CHILD_COMM:-codex-aarch64-apple-darwin}"
fi
exit 0
EOF
chmod +x "$TMPBIN/ps"

export PATH="$TMPBIN:$PATH"

seed_pinned_pane() {
  printf '%%1|@necro_cmd=codex-aarch64-apple-darwin\n' > "$STATE"
  printf '%%1|@necro_agent=codex\n' >> "$STATE"
  printf '%%1|@necro_uuid=test-uuid-1234\n' >> "$STATE"
}

# Case A: agent is SUSPENDED — pane_current_command is "zsh" but a live codex
# child survives. Must NOT be marked exited.
seed_pinned_pane
export NECRO_TEST_CHILD_ALIVE=1
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
exited="$(grep -F '%1|@necro_agent_exited=' "$STATE" | tail -1 | cut -d= -f2-)"
[ -z "$exited" ] || {
  echo "FAIL: suspended agent (live child) was marked exited" >&2
  exit 1
}
echo "PASS: suspended agent with a live pane child is not marked exited"

# Case B: agent has GENUINELY exited — no live child at all. Must still be
# marked exited (the guard must not swallow real exits).
seed_pinned_pane
unset NECRO_TEST_CHILD_ALIVE
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
exited="$(grep -F '%1|@necro_agent_exited=' "$STATE" | tail -1 | cut -d= -f2-)"
[ "$exited" = "1" ] || {
  echo "FAIL: genuine exit (no live child) was not marked exited (got '$exited')" >&2
  exit 1
}
echo "PASS: genuine exit with no live pane child is still marked exited"
