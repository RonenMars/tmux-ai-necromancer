#!/usr/bin/env bash
# necro-watch-session-file-repin-test.sh — the watcher follows the session id
# Claude itself reports in ~/.claude/sessions/<pid>.json.
#
# Observed on a real server, two panes pinned to the wrong conversation:
#   %42: pinned a fresh session by cursor-pop, then claude was relaunched with
#        --resume <other id> 11s later, inside one 30s tick. Same agent, so
#        Case 1 never fired and the 43 KB abandoned session stayed pinned.
#   %26: one claude process since 17:51; its session id changed inside the
#        process (/clear or /resume). Nothing re-checks a pinned pane, so the
#        pin stayed on a transcript last written six hours earlier.
# In both, the session file named the real session.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_LIMIT_CHECK_INTERVAL=0
mkdir -p "$HOME/.claude/sessions" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
CWD="$TMP/work"
mkdir -p "$CWD"

OLD=95ffcecb-9342-44b4-8f00-3106b420e1ee   # stale: pinned earlier / still in argv
NEW=8c480377-30b0-4a48-ab23-3528fb638d68   # what the claude process is running now
STATE="$TMP/pane-opts"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-options) printf '@necromancer_agents "claude codex"\n'; exit 0 ;;
  show-option)
    if [ "$2" = "-gqv" ]; then printf '\n'; exit 0; fi
    line="$(grep -F "|${5:-}=" "$STATE" 2>/dev/null | tail -1)"
    [ -n "$line" ] && printf '%s\n' "${line#*=}"
    exit 0 ;;
  set-option)
    [ "$2" = "-gq" ] && exit 0
    if [ "$2" = "-pu" ]; then printf '%s|%s=\n' "$4" "$5" >> "$STATE"; exit 0; fi
    printf '%s|%s=%s\n' "$4" "$5" "${6:-}" >> "$STATE"
    exit 0 ;;
  list-panes)
    _o() { line="$(grep -F "%1|$1=" "$STATE" 2>/dev/null | tail -1)"; printf '%s' "${line#*=}"; }
    printf '%%1\x1fclaude\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f999\n' \
      "$(_o @necro_uuid)" "$(_o @necro_cmd)" "$(_o @necro_agent)" \
      "$(_o @necro_agent_exited)" "$(_o @necro_pane_first_seen)" "$CWD"
    exit 0 ;;
  display-message) printf '999\n'; exit 0 ;;
  *) exit 0 ;;
esac
EOF
# Pane shell 999 has one child, claude (pid 1234), whose argv still names OLD.
printf '#!/usr/bin/env bash\n[ "$2" = "999" ] && echo 1234\nexit 0\n' > "$TMPBIN/pgrep"
cat > "$TMPBIN/ps" <<EOF
#!/usr/bin/env bash
case "\$2" in
  comm=)    echo claude ;;
  command=) echo "claude --resume $OLD" ;;
esac
EOF
chmod +x "$TMPBIN/tmux" "$TMPBIN/pgrep" "$TMPBIN/ps"
export PATH="$TMPBIN:$PATH"

printf '{"pid":1234,"sessionId":"%s","cwd":"%s","kind":"interactive"}\n' "$NEW" "$CWD" \
  > "$HOME/.claude/sessions/1234.json"

opt() { grep -F "%1|$1=" "$STATE" | tail -1 | cut -d= -f2-; }
fail=0

# A: already pinned to OLD, same agent, never marked exited.
{ printf '%%1|@necro_uuid=%s\n' "$OLD"; printf '%%1|@necro_cmd=claude\n'
  printf '%%1|@necro_agent=claude\n'; printf '%%1|@necro_pane_first_seen=1\n'; } > "$STATE"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
[ "$(opt @necro_uuid)" = "$NEW" ] || { echo "FAIL A: pinned pane kept $(opt @necro_uuid), want $NEW" >&2; fail=1; }

# B: unpinned pane; argv names OLD, the session file names NEW.
: > "$STATE"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
[ "$(opt @necro_uuid)" = "$NEW" ] || { echo "FAIL B: fresh pin is $(opt @necro_uuid), want $NEW (session file over argv)" >&2; fail=1; }

# C: no session file (older Claude, other agents): the pin is left alone.
rm -f "$HOME/.claude/sessions/1234.json"
{ printf '%%1|@necro_uuid=%s\n' "$OLD"; printf '%%1|@necro_cmd=claude\n'
  printf '%%1|@necro_agent=claude\n'; printf '%%1|@necro_pane_first_seen=1\n'; } > "$STATE"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
[ "$(opt @necro_uuid)" = "$OLD" ] || { echo "FAIL C: pin changed to $(opt @necro_uuid) with no session file" >&2; fail=1; }

# D: a non-interactive session file (a headless child) is not the pane's own.
printf '{"pid":1234,"sessionId":"%s","cwd":"%s","kind":"print"}\n' "$NEW" "$CWD" \
  > "$HOME/.claude/sessions/1234.json"
{ printf '%%1|@necro_uuid=%s\n' "$OLD"; printf '%%1|@necro_cmd=claude\n'
  printf '%%1|@necro_agent=claude\n'; printf '%%1|@necro_pane_first_seen=1\n'; } > "$STATE"
bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
[ "$(opt @necro_uuid)" = "$OLD" ] || { echo "FAIL D: re-pinned from a non-interactive session file" >&2; fail=1; }

[ "$fail" = 0 ] || exit 1
echo "PASS: the watcher pins and re-pins Claude panes from ~/.claude/sessions/<pid>.json"
