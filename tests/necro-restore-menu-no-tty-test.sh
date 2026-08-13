#!/usr/bin/env bash
# necro-restore-menu-no-tty-test.sh — `--menu` refuses to run without a real
# controlling terminal, and changes nothing when it refuses.
#
# Same guard as invariant 14, for the same reason: restore is reachable from
# tmux run-shell (the restore keybind), display-popup, launchd and cron, none
# of which can answer a prompt. A picker that "reads" a selection there would
# get EOF and fall through to restoring whatever the empty answer implied.
#
# The check must be an actual open of /dev/tty. `[ -t 0 ]` tests the wrong fd
# (necro_init_log pipes stdout through tee) and `[ -r /dev/tty ]` false-passes
# in a ttyless context, because the permission bits allow access(2) even when
# there is no controlling terminal for open(2) to attach to.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"
CWD1="$TMP/a"; mkdir -p "$CWD1"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session) exit 1 ;;
  list-windows|list-panes) printf '' ;;
  new-window)  printf '@10\n' ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/s.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w","cwd":"$CWD1","prev_cmd":"claude","agent":"claude","uuid":"11111111-1111-4111-8111-111111111111","uuid_source":"pane-option","window_layout":"","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

fails=0
: > "$CALLS"

# setsid detaches from the controlling terminal where available; redirecting
# stdin alone is not enough, since /dev/tty follows the CONTROLLING terminal,
# not fd 0. Without setsid the harness is already ttyless, which is the case
# this guards anyway.
out="$(bash "$ROOT/scripts/necro-restore.sh" "$SNAP" --menu </dev/null 2>&1)"
rc=$?

# Exit 2 alone proves nothing here: an unimplemented --menu is rejected as an
# unknown flag, which also exits 2. The message is what distinguishes them.
case "$out" in
  *"needs a real terminal"*)
    echo "  ok: refused with a tty-specific message" ;;
  *)
    echo "  FAIL: expected a 'needs a real terminal' refusal"
    echo "        rc=$rc output:"
    printf '%s\n' "$out" | sed 's/^/          /'
    fails=$((fails + 1)) ;;
esac

if [ "$rc" -ne 0 ]; then
  echo "  ok: non-zero exit ($rc)"
else
  echo "  FAIL: exited 0 despite refusing"
  fails=$((fails + 1))
fi

built=$(grep -c -e '^new-session' -e '^new-window' -e '^split-window' -e '^send-keys' "$CALLS" || true)
if [ "$built" -eq 0 ]; then
  echo "  ok: changed nothing"
else
  echo "  FAIL: mutated tmux while refusing ($built call(s))"
  grep -e '^new-session' -e '^new-window' -e '^split-window' -e '^send-keys' "$CALLS" || true
  fails=$((fails + 1))
fi

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS: necro-restore-menu-no-tty-test"
