#!/usr/bin/env bash
# Test: only one concurrent autosave fires when two copies race.
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

# tmux stub: return safe defaults for the options the script reads.
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"@necromancer_interval"*)   echo "0"  ;;
  *"@necromancer_last_saved"*) echo "0"  ;;
  *"@necromancer_max_snapshots"*) echo "20" ;;
  *"set-option"*) : ;;   # no-op writes
  *"list-panes"*) : ;;   # no panes to report
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"

# necro-snapshot.sh stub: sleeps to widen the race window.
cat > "$TMPBIN/necro-snapshot.sh" <<'EOF'
#!/usr/bin/env bash
sleep 1
EOF
chmod +x "$TMPBIN/necro-snapshot.sh"

# Patch SCRIPTS_DIR so the script finds our stub snapshot instead of the real one.
# We do this by symlinking the real scripts dir but overriding necro-snapshot.sh.
FAKE_SCRIPTS="$TMP/scripts"
mkdir -p "$FAKE_SCRIPTS"
for f in "$ROOT/scripts"/*.sh; do
  ln -s "$f" "$FAKE_SCRIPTS/$(basename "$f")"
done
# Override snapshot stub
rm "$FAKE_SCRIPTS/necro-snapshot.sh"
ln -s "$TMPBIN/necro-snapshot.sh" "$FAKE_SCRIPTS/necro-snapshot.sh"

export PATH="$TMPBIN:$PATH"

# Launch two concurrent autosave runs.
bash "$FAKE_SCRIPTS/necro-autosave.sh" &
bash "$FAKE_SCRIPTS/necro-autosave.sh" &
wait

# Let the async log-write subshell finish.
sleep 2

LOG="$NECROMANCER_SNAPSHOT_DIR/autosave.log"
count=0
if [ -f "$LOG" ]; then
  count=$(grep -c "autosave started" "$LOG" || true)
fi

if [ "$count" -eq 1 ]; then
  echo "PASS: exactly one autosave fired (lock works)"
  exit 0
else
  echo "FAIL: expected 1 autosave started, got $count" >&2
  [ -f "$LOG" ] && cat "$LOG" >&2
  exit 1
fi
