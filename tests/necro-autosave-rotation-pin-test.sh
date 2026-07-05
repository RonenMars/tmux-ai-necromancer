#!/usr/bin/env bash
# Test: rotation never deletes the snapshot pinned as latest-for-reboot,
# and still rotates unpinned files beyond @necromancer_max_snapshots.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolated snapshot dir — no live tmux or real snapshot dir needed.
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$NECROMANCER_SNAPSHOT_DIR"

# Stub bin dir prepended to PATH.
TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

# tmux stub: interval 0 so the run always fires; keep only 2 snapshots.
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"@necromancer_interval"*)      echo "0"  ;;
  *"@necromancer_last_saved"*)    echo "0"  ;;
  *"@necromancer_max_snapshots"*) echo "2"  ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"

# necro-snapshot.sh stub: no-op (we seed snapshot files ourselves).
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

# Seed: an old enriched snapshot (the pinned reboot target), an even older
# autosave, and three newer autosaves. max=2 → rotation wants to delete all
# but the newest two; the pinned file must survive anyway.
oldest="$NECROMANCER_SNAPSHOT_DIR/2026-01-01T00-00-00Z.idle-only.jsonl"
pinned="$NECROMANCER_SNAPSHOT_DIR/2026-01-02T00-00-00Z.enriched.jsonl"
mid="$NECROMANCER_SNAPSHOT_DIR/2026-01-03T00-00-00Z.idle-only.jsonl"
new1="$NECROMANCER_SNAPSHOT_DIR/2026-01-04T00-00-00Z.idle-only.jsonl"
new2="$NECROMANCER_SNAPSHOT_DIR/2026-01-05T00-00-00Z.idle-only.jsonl"

i=1
for f in "$oldest" "$pinned" "$mid" "$new1" "$new2"; do
  echo '{}' > "$f"
  touch -t "2026010${i}0000" "$f"
  i=$(( i + 1 ))
done
ln -sfn "$pinned" "$NECROMANCER_SNAPSHOT_DIR/latest-for-reboot"

bash "$FAKE_SCRIPTS/necro-autosave.sh"

# Let the async log-write subshell finish.
sleep 2

fail=0
[ -f "$pinned" ] || { echo "FAIL: pinned snapshot was rotated away" >&2; fail=1; }
[ -f "$new1" ] && [ -f "$new2" ] || { echo "FAIL: newest snapshots missing" >&2; fail=1; }
[ ! -f "$oldest" ] || { echo "FAIL: oldest unpinned snapshot not rotated" >&2; fail=1; }
[ ! -f "$mid" ] || { echo "FAIL: mid unpinned snapshot not rotated" >&2; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "PASS: rotation kept pinned reboot snapshot and rotated the rest"
else
  LOG="$NECROMANCER_SNAPSHOT_DIR/autosave.log"
  [ -f "$LOG" ] && cat "$LOG" >&2
  exit 1
fi
