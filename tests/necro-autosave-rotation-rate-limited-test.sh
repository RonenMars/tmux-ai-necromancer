#!/usr/bin/env bash
# necro-autosave-rotation-rate-limited-test.sh — rate-limited captures age out
# with everything else, and the pin exemption still protects them.
#
# Rotation's glob is an allowlist of literal suffixes, so *.rate-limited.jsonl
# was invisible to it: the watcher wrote them on a timer
# (@necromancer_limit_check_interval) and nothing ever removed them. They also
# escaped the @necromancer_max_snapshots budget, which made that cap mean "N
# autosaves, plus however many of everything else".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"show-options -g"*)
    printf '@necromancer_interval 0\n'
    printf '@necromancer_last_saved 0\n'
    printf '@necromancer_max_snapshots 2\n'
    ;;
  *"@necromancer_interval"*)      echo "0" ;;
  *"@necromancer_last_saved"*)    echo "0" ;;
  *"@necromancer_max_snapshots"*) echo "2" ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"

cat > "$TMPBIN/necro-snapshot.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPBIN/necro-snapshot.sh"

FAKE_SCRIPTS="$TMP/scripts"
mkdir -p "$FAKE_SCRIPTS"
for f in "$ROOT/scripts"/*.sh; do
  ln -s "$f" "$FAKE_SCRIPTS/$(basename "$f")"
done
rm "$FAKE_SCRIPTS/necro-snapshot.sh"
ln -s "$TMPBIN/necro-snapshot.sh" "$FAKE_SCRIPTS/necro-snapshot.sh"

export PATH="$TMPBIN:$PATH"

# max=2, so everything older than the newest two should go — except the pin.
rl_old="$NECROMANCER_SNAPSHOT_DIR/2026-01-01T00-00-00Z.rate-limited.jsonl"
io_old="$NECROMANCER_SNAPSHOT_DIR/2026-01-02T00-00-00Z.idle-only.jsonl"
rl_pin="$NECROMANCER_SNAPSHOT_DIR/2026-01-03T00-00-00Z.rate-limited.jsonl"
new1="$NECROMANCER_SNAPSHOT_DIR/2026-01-04T00-00-00Z.idle-only.jsonl"
new2="$NECROMANCER_SNAPSHOT_DIR/2026-01-05T00-00-00Z.idle-only.jsonl"

i=1
for f in "$rl_old" "$io_old" "$rl_pin" "$new1" "$new2"; do
  echo '{}' > "$f"
  touch -t "2026010${i}0000" "$f"
  i=$(( i + 1 ))
done
ln -sfn "$rl_pin" "$NECROMANCER_SNAPSHOT_DIR/latest-for-reboot"

bash "$FAKE_SCRIPTS/necro-autosave.sh"

# The rotation runs in the backgrounded work subshell; give it time to finish.
sleep 2

fail=0
[ ! -f "$rl_old" ] || { echo "FAIL: old rate-limited capture was not rotated" >&2; fail=1; }
[ ! -f "$io_old" ] || { echo "FAIL: old autosave was not rotated" >&2; fail=1; }
[ -f "$rl_pin" ]   || { echo "FAIL: pinned rate-limited capture was rotated away" >&2; fail=1; }
[ -f "$new1" ] && [ -f "$new2" ] || { echo "FAIL: newest snapshots missing" >&2; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "PASS: rate-limited captures rotate, and the pin still exempts them"
else
  LOG="$NECROMANCER_SNAPSHOT_DIR/autosave.log"
  [ -f "$LOG" ] && cat "$LOG" >&2
  exit 1
fi
