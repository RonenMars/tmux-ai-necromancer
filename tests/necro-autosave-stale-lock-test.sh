#!/usr/bin/env bash
# necro-autosave-stale-lock-test.sh — the autosave WORK lock must self-heal.
#
# Regression target, observed in production: a work subshell was killed after
# writing its snapshot, so its EXIT trap never released .autosave.lock. Every
# tick for the next 4.5 days exited on "lock held" while the daemon kept
# reporting as running — a silent, permanent stop with no error anywhere.
#
# Two halves, and the second matters as much as the first: an ORPHANED lock is
# reclaimed, and a lock with a LIVE owner is left strictly alone.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_DEBUG=1
mkdir -p "$NECROMANCER_SNAPSHOT_DIR"
LOCK="$NECROMANCER_SNAPSHOT_DIR/.autosave.lock"
LOG="$NECROMANCER_SNAPSHOT_DIR/autosave.log"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
# The set-option arm MUST come first: the script WRITES @necromancer_last_saved,
# and a read-shaped arm would echo "0" onto the caller's stdout for that write.
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"set-option"*)                 : ;;
  *"@necromancer_interval"*)      echo "0"  ;;
  *"@necromancer_last_saved"*)    echo "0"  ;;
  *"@necromancer_max_snapshots"*) echo "20" ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMPBIN/tmux"

# Snapshot stub — the lock behaviour is what's under test, not the walk.
cat > "$TMPBIN/necro-snapshot.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPBIN/necro-snapshot.sh"

FAKE_SCRIPTS="$TMP/scripts"; mkdir -p "$FAKE_SCRIPTS"
for f in "$ROOT/scripts"/*.sh; do ln -s "$f" "$FAKE_SCRIPTS/$(basename "$f")"; done
rm "$FAKE_SCRIPTS/necro-snapshot.sh"
ln -s "$TMPBIN/necro-snapshot.sh" "$FAKE_SCRIPTS/necro-snapshot.sh"
export PATH="$TMPBIN:$PATH"

await_complete() {
  local deadline=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    [ -f "$LOG" ] && grep -q "autosave complete" "$LOG" 2>/dev/null && return 0
    sleep 0.2
  done
  return 1
}

fail=0

# Age out a lock so the 60s "a run may be starting" guard doesn't mask the
# case under test. This is also the real pre-upgrade shape: an old lock left
# by a version that never recorded a pid.
backdate() { touch -t 202601010000 "$1"; }

# ── 1. An OLD lock with no recorded pid is reclaimed ────────────────────────
# Exactly what an upgrade meets: the wedged lock predates this code, so there
# is no pid to check and age is the only signal available.
mkdir -p "$LOCK"; backdate "$LOCK"
: > "$LOG"
bash "$FAKE_SCRIPTS/necro-autosave.sh"
if await_complete; then
  echo "ok: old pid-less lock reclaimed, autosave ran"
else
  echo "FAIL: autosave did not run against an orphaned lock — the wedge is back"
  fail=1
fi
[ -d "$LOCK" ] && { echo "FAIL: lock still held after a completed run"; fail=1; }

# ── 2. A lock whose recorded pid is a LIVE autosave is left alone ───────────
# Reclaiming this one would let two autosaves run against the same dir.
mkdir -p "$LOCK"
: > "$LOG"
OWNER_DIR="$TMP/owner"; mkdir -p "$OWNER_DIR"
printf '#!/usr/bin/env bash\nsleep 10\n' > "$OWNER_DIR/necro-autosave.sh"
chmod +x "$OWNER_DIR/necro-autosave.sh"
bash "$OWNER_DIR/necro-autosave.sh" &
owner_pid=$!
printf '%s\n' "$owner_pid" > "$LOCK/pid"
sleep 1

bash "$FAKE_SCRIPTS/necro-autosave.sh"
sleep 1
if grep -q "autosave started" "$LOG" 2>/dev/null; then
  echo "FAIL: reclaimed a lock whose owner is alive — two autosaves could race"
  fail=1
else
  echo "ok: live owner respected, autosave skipped"
fi
[ -d "$LOCK" ] || { echo "FAIL: released a lock we do not own"; fail=1; }

kill "$owner_pid" 2>/dev/null
wait "$owner_pid" 2>/dev/null
rm -rf "$LOCK"

# ── 3. A lock naming a DEAD pid is reclaimed ────────────────────────────────
# The exact production shape: the subshell recorded its pid, then was killed
# before its trap could clear it.
mkdir -p "$LOCK"
: > "$LOG"
bash -c 'exit 0' & dead_pid=$!; wait "$dead_pid" 2>/dev/null
printf '%s\n' "$dead_pid" > "$LOCK/pid"
bash "$FAKE_SCRIPTS/necro-autosave.sh"
if await_complete; then
  echo "ok: lock naming a dead pid reclaimed"
else
  echo "FAIL: a dead owner still wedges autosave"
  fail=1
fi
rm -rf "$LOCK"

# ── 4. A wrapper merely MENTIONING the script is not an owner ───────────────
# Regression target found while writing this fix: matching `pgrep -f
# necro-autosave.sh` treats any shell whose command line contains the script
# path as the owner, so the lock is never reclaimed. Ownership must come from
# the recorded pid alone.
mkdir -p "$LOCK"; backdate "$LOCK"
: > "$LOG"
bash -c "sleep 10 # $FAKE_SCRIPTS/necro-autosave.sh" &
decoy_pid=$!
sleep 1
bash "$FAKE_SCRIPTS/necro-autosave.sh"
if await_complete; then
  echo "ok: a wrapper mentioning the script is not treated as an owner"
else
  echo "FAIL: a process merely mentioning necro-autosave.sh blocked recovery"
  fail=1
fi
kill "$decoy_pid" 2>/dev/null; wait "$decoy_pid" 2>/dev/null
rm -rf "$LOCK"

# ── 5. A YOUNG lock with no pid yet is respected ────────────────────────────
# Between `mkdir` and the subshell stamping its pid there is a real window.
# Reclaiming there would hand the lock to a second run while the first works.
mkdir -p "$LOCK"          # fresh, deliberately NOT backdated
: > "$LOG"
bash "$FAKE_SCRIPTS/necro-autosave.sh"
sleep 1
if grep -q "autosave started" "$LOG" 2>/dev/null; then
  echo "FAIL: stole a just-created lock before its owner could stamp a pid"
  fail=1
else
  echo "ok: a just-created lock is left alone"
fi
rm -rf "$LOCK"

[ "$fail" = 0 ] && echo "PASS: necro-autosave-stale-lock-test" || exit 1
