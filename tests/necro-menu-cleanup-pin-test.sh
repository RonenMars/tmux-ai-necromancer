#!/usr/bin/env bash
# The menu's cleanup must never delete the snapshot pinned as the reboot
# target. Autosave rotation already guards it (necro-autosave-rotation-pin-test)
# but the menu's three delete modes bypassed that, leaving reboot-resume with a
# dangling pointer — i.e. sessions silently lost after a reboot.
#
# Also pins the path-resolution detail that broke the first cut of this fix: on
# macOS `readlink -f` reports /private/var/... while `ls` yields /var/... for
# the same file, so both sides must be resolved before comparing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
export NECROMANCER_LOG_DIR="$TMP/logs"
mkdir -p "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"

PINNED="$NECROMANCER_SNAPSHOT_DIR/2026-07-11T00-00-00Z.idle-only.jsonl"
for n in 1 2 3; do
  printf '{}\n' > "$NECROMANCER_SNAPSHOT_DIR/2026-07-1${n}T00-00-00Z.idle-only.jsonl"
  sleep 0.02
done
ln -sfn "$PINNED" "$NECROMANCER_SNAPSHOT_DIR/latest-for-reboot"

# Load the menu's helpers without running its interactive loop.
. "$ROOT/lib/common.sh"
SNAP_DIR="$(necro_snapshot_dir)"
POINTER="$SNAP_DIR/latest-for-reboot"
eval "$(sed -n '/^resolve_path()/,/^}/p; /^pinned_snapshot()/,/^}/p; /^filter_pinned()/,/^}/p' "$ROOT/scripts/necro-menu.sh")"

fails=0

echo "pinned_snapshot resolves the pointer"
got="$(pinned_snapshot)"
if [ -z "$got" ]; then
  echo "  FAIL: pointer not resolved" >&2; fails=$((fails + 1))
else
  echo "  ok: $(basename "$got")"
fi

echo "filter_pinned drops the pinned snapshot from a delete list"
# "keep newest 1" => the two older files are candidates; the pinned one is among them.
to_delete="$(/bin/ls -t "$SNAP_DIR"/*.jsonl | tail -n +2 | filter_pinned 2>/dev/null)"
if grep -qF "2026-07-11" <<<"$to_delete"; then
  echo "  FAIL: pinned reboot snapshot would be deleted" >&2
  echo "  list: $to_delete" >&2
  fails=$((fails + 1))
else
  echo "  ok: pinned snapshot excluded"
fi

echo "filter_pinned still passes through non-pinned snapshots"
if grep -qF "2026-07-12" <<<"$to_delete"; then
  echo "  ok: unpinned snapshot still deletable"
else
  echo "  FAIL: filter dropped a snapshot that isn't pinned" >&2
  echo "  list: $to_delete" >&2
  fails=$((fails + 1))
fi

echo "no pointer => nothing filtered"
rm -f "$POINTER"
all="$(/bin/ls -t "$SNAP_DIR"/*.jsonl | filter_pinned 2>/dev/null | grep -c . )"
if [ "$all" -eq 3 ]; then
  echo "  ok: all 3 snapshots pass through when nothing is pinned"
else
  echo "  FAIL: expected 3 snapshots to pass through, got $all" >&2
  fails=$((fails + 1))
fi

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS"
