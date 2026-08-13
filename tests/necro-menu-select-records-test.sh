#!/usr/bin/env bash
# necro-menu-select-records-test.sh — the menu's resume action can hand off to
# the record picker, and the handoff really reaches it.
#
# End-to-end through a real pty rather than a grep for the flag: the menu must
# offer the choice AND route it to necro-restore.sh --menu, whose picker then
# has to actually come up. A grep would pass on a dead code path.
#
# Also pins the older answer: 'y' still restores everything, so existing muscle
# memory doesn't silently become "cancel".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin" "$TMP/proj"

command -v python3 >/dev/null || { echo "SKIP: python3 needed to allocate a pty"; exit 0; }

cat > "$TMP/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  list-sessions|list-windows|list-panes) printf '' ;;
  new-window) printf '@10\n' ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/tmux"
export PATH="$TMP/bin:$PATH"

cat > "$NECROMANCER_SNAPSHOT_DIR/2026-01-01T00-00-00Z.idle-only.jsonl" <<EOF
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w","cwd":"$TMP/proj","prev_cmd":"claude","agent":"claude","uuid":"11111111-1111-4111-8111-111111111111","uuid_source":"pane-option","window_layout":"","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

# Minimal pty driver: send each key as a line, pausing so the child's read()
# picks them up one at a time.
cat > "$TMP/drive.py" <<'PY'
import os, pty, select, sys, time
keys = sys.argv[1].split(",")
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out, deadline, nxt = [], time.time() + 25, time.time() + 0.6
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            d = os.read(fd, 65536)
        except OSError:
            break
        if not d:
            break
        out.append(d.decode("utf-8", "replace"))
    if keys and time.time() >= nxt:
        os.write(fd, (keys.pop(0) + "\n").encode())
        nxt = time.time() + 0.6
sys.stdout.write("".join(out).replace("\r", ""))
PY

# menu: [2] resume -> snapshot 1 -> don't kill sessions -> 's' select -> 'q'
out="$(python3 "$TMP/drive.py" '2,1,n,s,q' bash "$ROOT/scripts/necro-menu.sh" 2>&1)"

fails=0
case "$out" in
  *"[s]elect records"*) echo "  ok: menu offers record selection" ;;
  *) echo "  FAIL: menu never offered '[s]elect records'"; fails=$((fails + 1)) ;;
esac

case "$out" in
  *"Records in 2026-01-01T00-00-00Z.idle-only"*)
    echo "  ok: handoff reached the picker" ;;
  *)
    echo "  FAIL: picker never came up after choosing [s]"
    printf '%s\n' "$out" | tail -20 | sed 's/^/          /'
    fails=$((fails + 1)) ;;
esac

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS: necro-menu-select-records-test"
