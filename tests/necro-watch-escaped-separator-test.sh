#!/usr/bin/env bash
# necro-watch-escaped-separator-test.sh — the pane walk must survive a tmux
# that escapes control bytes in format output.
#
# tmux 3.5a returns the ASCII Unit Separator in `list-panes -F` as the four
# literal characters \037 (verified against a 3.5a built from source: zero raw
# 0x1f bytes in the output; 3.6 and 3.7b emit the raw byte). With IFS=$'\037'
# that matches nothing, so the entire line lands in pane_id, cmd is empty, no
# pane is recognised as an agent, and UUID pinning is silently dead — the
# plugin's core mechanism, failing with no error anywhere.
#
# Regression target: someone removes the unescape step in necro-watch.sh
# because "tmux emits a raw byte" — true only on 3.6+.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
TMPBIN="$TMP/bin"
CWD="$TMP/work"
UUID="aaaaaaaa-0000-0000-0000-000000000001"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMPBIN" "$CWD"

STATE="$TMP/pane-opts"
: > "$STATE"

# Stub tmux. SEP_MODE picks how list-panes renders the separator: "raw" is
# tmux >= 3.6, "escaped" is 3.5a.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-option)
    if [ "$2" = "-gqv" ]; then
      case "$3" in
        @necromancer_last_watch) printf '0\n' ;;
        @necromancer_agents) printf 'claude\n' ;;
        *) printf '\n' ;;
      esac
    fi
    exit 0
    ;;
  set-option)
    if [ "$2" = "-gq" ]; then exit 0; fi
    if [ "$2" = "-pu" ]; then printf '%s|%s=\n' "$4" "$5" >> "$STATE"; exit 0; fi
    printf '%s|%s=%s\n' "$4" "$5" "${6:-}" >> "$STATE"
    exit 0
    ;;
  list-panes)
    _o() { line="$(grep -F "%1|$1=" "$STATE" 2>/dev/null | tail -1)"; printf '%s' "${line#*=}"; }
    if [ "${SEP_MODE:-raw}" = "escaped" ]; then S='\037'; else S=$'\037'; fi
    printf '%%1%sclaude%s%s%s%s%s%s%s%s%s%s%s%s\n' \
      "$S" "$S" "$(_o @necro_uuid)" "$S" "$(_o @necro_cmd)" "$S" "$(_o @necro_agent)" \
      "$S" "$(_o @necro_agent_exited)" "$S" "$(_o @necro_pane_first_seen)" "$S" "$CWD"
    exit 0
    ;;
  display-message) printf '999\n'; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# argv tier: ground truth, so the walk pins without touching the filesystem.
cat > "$TMPBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
echo "1234"
EOF
cat > "$TMPBIN/ps" <<EOF
#!/usr/bin/env bash
printf 'claude --resume %s\n' "$UUID"
EOF
chmod +x "$TMPBIN/pgrep" "$TMPBIN/ps"
export PATH="$TMPBIN:$PATH"

run_watch() {
  : > "$STATE"
  printf '%%1|@necro_pane_first_seen=1\n' > "$STATE"
  SEP_MODE="$1" bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
  grep -F '%1|@necro_uuid=' "$STATE" | tail -1 | cut -d= -f2-
}

for mode in raw escaped; do
  got="$(run_watch "$mode")"
  [ "$got" = "$UUID" ] || {
    echo "FAIL: separator mode '$mode' — expected pane pinned to $UUID, got '$got'" >&2
    exit 1
  }
  echo "PASS: pane pinned with $mode separator"
done
