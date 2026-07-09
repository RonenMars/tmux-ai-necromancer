#!/usr/bin/env bash
# necro-watch-first-seen-persistence-test.sh — @necro_pane_first_seen must be
# written once and reused on later ticks for the same still-unpinned pane, not
# reset to "now" every time. Regression target: a stamp that keeps advancing
# would let a stale transcript slip past the min_epoch filter simply because
# the watcher happened to tick again before argv/scrollback resolved.
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
mkdir -p "$CWD" "$HOME/.claude/projects/${CWD//\//-}"

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
  list-panes) printf '%%1\tclaude\t%s\n' "$CWD"; exit 0 ;;
  display-message) printf '999\n'; exit 0 ;;
  capture-pane) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# No argv/scrollback hit and no transcript on disk — uuid never resolves, so
# the pane stays permanently unpinned across every tick (exactly the
# condition where first_seen must not keep drifting forward).
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

: > "$STATE"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
first_tick="$(grep -F '%1|@necro_pane_first_seen=' "$STATE" | tail -1 | cut -d= -f2-)"
[ -n "$first_tick" ] || { echo "FAIL: first_seen not stamped on first tick" >&2; exit 1; }

sleep 2
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
second_tick="$(grep -F '%1|@necro_pane_first_seen=' "$STATE" | tail -1 | cut -d= -f2-)"

[ "$second_tick" = "$first_tick" ] || {
  echo "FAIL: first_seen changed across ticks ($first_tick -> $second_tick) — should persist while unpinned" >&2
  exit 1
}
echo "PASS: first_seen stamp persists across ticks for a still-unpinned pane"
