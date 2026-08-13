#!/usr/bin/env bash
# necro-reboot-prep-skips-rate-limited-test.sh — the reboot target must never be
# a *.rate-limited.jsonl snapshot.
#
# In exit-capture mode the child writes a plain <TS>.jsonl, so reboot-prep finds
# it by taking the newest snapshot that is neither idle-only nor enriched:
#
#   ls -t *.jsonl | grep -v idle-only | grep -v enriched | head -1
#
# A rate-limited capture matches that filter and holds ONLY the panes that hit a
# limit — as few as one record. Pinning it as the reboot target means the next
# necro-reboot-resume.sh rebuilds one pane and calls it a restored machine.
#
# The window is real but narrow: prep takes its own snapshot first, so its fresh
# file is normally newest. It loses that race whenever its own snapshot is older
# than a rate-limited one — the watcher writes those on a timer
# (@necromancer_limit_check_interval), unattended. The test forces the ordering
# with a future mtime rather than trying to win a race.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin" "$TMP/proj"
unset TMUX

command -v python3 >/dev/null || { echo "SKIP: python3 needed to allocate a pty"; exit 0; }

# One idle shell pane: enough for the snapshot to produce a record, and no agent
# means --yes sends no exit keys.
cat > "$TMP/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-sessions) printf 's: 1 windows\n' ;;
  list-panes)
    printf '%%1\t s\t 1\t w\t $TMP/proj\t zsh\t layout\t 0\t 1\t 1\n' | tr -d ' ' ;;
  display-message) printf 'zsh\n' ;;
  show-option|show-options) printf '' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

# A rate-limited capture that is NEWER than anything this run will write.
RL="$NECROMANCER_SNAPSHOT_DIR/2026-08-12T19-28-54Z.rate-limited.jsonl"
cat > "$RL" <<EOF
{"pane_id":"%9","session":"s","window_index":9,"window_name":"limited","cwd":"$TMP/proj","prev_cmd":"claude","agent":"claude","uuid":"99999999-9999-4999-8999-999999999999","uuid_source":"pane-option","window_layout":"","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF
touch -t 209901010000 "$RL"

cat > "$TMP/drive.py" <<'PY'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out, deadline = [], time.time() + 30
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if not r:
        continue
    try:
        d = os.read(fd, 65536)
    except OSError:
        break
    if not d:
        break
    out.append(d.decode("utf-8", "replace"))
sys.stdout.write("".join(out).replace("\r", ""))
PY

# --yes needs a real tty or reboot-prep downgrades to --idle-only, which takes
# the other branch entirely and would never exercise this glob.
out="$(python3 "$TMP/drive.py" bash "$ROOT/scripts/necro-reboot-prep.sh" --yes --no-enrich 2>&1)"

fails=0

case "$out" in
  *"Mode:    yes"*) echo "  ok: ran in exit-capture mode (the branch under test)" ;;
  *)
    echo "  FAIL: never reached --yes mode, so the glob was not exercised"
    printf '%s\n' "$out" | head -20 | sed 's/^/          /'
    fails=$((fails + 1)) ;;
esac

pointer="$NECROMANCER_SNAPSHOT_DIR/latest-for-reboot"
target="$(readlink "$pointer" 2>/dev/null || true)"
case "$target" in
  "")
    echo "  FAIL: no reboot pointer was written"
    fails=$((fails + 1)) ;;
  *rate-limited*)
    echo "  FAIL: pinned a rate-limited capture as the reboot target"
    echo "        $target"
    fails=$((fails + 1)) ;;
  *)
    echo "  ok: pinned $(basename "$target")" ;;
esac

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS: necro-reboot-prep-skips-rate-limited-test"
