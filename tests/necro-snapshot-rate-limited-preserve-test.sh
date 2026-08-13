#!/usr/bin/env bash
# necro-snapshot-rate-limited-preserve-test.sh — a --rate-limited run that saves
# nothing must not delete a snapshot it did not create.
#
# When every limited pane is already marked @necro_limit_saved, the run has
# nothing to write and removes $OUT to clean up after itself:
#
#   scripts/necro-snapshot.sh:322
#   if [ "$RATE_LIMITED" = 1 ] && [ "$RATE_LIMITED_SAVED" != 1 ]; then rm -f "$OUT"
#
# $OUT is "$SNAP_DIR/${TS}.rate-limited.jsonl" and TS has ONE-SECOND resolution,
# so a save from the same second resolves to the same path — and the cleanup
# deletes that earlier file instead of its own.
#
# Not theoretical: necro-watch.sh runs --rate-limited --auto on a timer
# (@necromancer_limit_check_interval, default 60s). Save your quota-blocked
# sessions from menu [6], have an auto tick land in that same second, and the
# file you just saved is gone.
#
# `date` is stubbed so TS is fixed. The real collision is a ~1-in-3 race, which
# is exactly why necro-snapshot-rate-limited-test.sh was flaky rather than
# failing outright; a test for this has to make the collision certain.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin" "$TMP/work"

CWD="$TMP/work"
STATE="$TMP/pane-opts"; : > "$STATE"

# Pin the clock so $OUT is a known path in both runs.
FROZEN="2026-08-13T12-00-00Z"
cat > "$TMP/bin/date" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *%Y-%m-%dT%H-%M-%SZ*) printf '$FROZEN\n' ;;
  *) exec /bin/date "\$@" ;;
esac
EOF
chmod +x "$TMP/bin/date"

# One claude pane showing a limit banner, ALREADY marked as saved — so an
# --auto run finds nothing new and takes the cleanup path.
cat > "$TMP/bin/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
EOF
cat >> "$TMP/bin/tmux" <<'EOF'
case "$1" in
  list-panes)
    printf '%%1\tsess\t1\tw1\t%s\tclaude\tlayout\t0\t1\t1\n' "$CWD" ;;
  capture-pane)
    printf "You've hit your session limit · resets 12:40pm\n" ;;
  show-option)
    case "$2" in
      -gqv|-gq) exit 0 ;;
    esac
    pane=""; opt=""; prev=""
    for a in "$@"; do
      case "$prev" in -t) pane="$a" ;; esac
      case "$a" in @necro_*) opt="$a" ;; esac
      prev="$a"
    done
    grep "^${pane}|${opt}=" "$STATE" 2>/dev/null | tail -1 | sed "s/^.*=//"
    exit 0 ;;
  set-option)
    pane=""; kv=""; prev=""
    for a in "$@"; do
      case "$prev" in -t) pane="$a" ;; esac
      case "$a" in @necro_*) kv="$a" ;; esac
      prev="$a"
    done
    shift $(($# - 1)); printf '%s|%s=%s\n' "$pane" "$kv" "$1" >> "$STATE"
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

printf '%%1|@necro_uuid=11111111-1111-1111-1111-111111111111\n' >> "$STATE"
printf '%%1|@necro_limit_saved=1\n' >> "$STATE"

# A rate-limited snapshot saved earlier in the SAME second the next run will use.
VICTIM="$NECROMANCER_SNAPSHOT_DIR/${FROZEN}.rate-limited.jsonl"
printf '{"pane_id":"%%1","session":"sess","cwd":"%s","agent":"claude"}\n' "$CWD" > "$VICTIM"
sentinel="$(cat "$VICTIM")"

bash "$ROOT/scripts/necro-snapshot.sh" --rate-limited --auto >/dev/null 2>&1 </dev/null

fails=0
if [ -f "$VICTIM" ]; then
  echo "  ok: the earlier save survived a no-op --auto run"
else
  echo "  FAIL: --auto deleted a rate-limited snapshot it did not create"
  echo "        $VICTIM"
  fails=$((fails + 1))
fi

if [ -f "$VICTIM" ] && [ "$(cat "$VICTIM")" = "$sentinel" ]; then
  echo "  ok: contents untouched"
elif [ -f "$VICTIM" ]; then
  echo "  FAIL: the earlier save was overwritten"
  fails=$((fails + 1))
fi

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS: necro-snapshot-rate-limited-preserve-test"
