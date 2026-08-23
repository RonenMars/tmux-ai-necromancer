#!/usr/bin/env bash
# necro-reboot-resume-headless-restore-test.sh — Phase 1 must persist a real
# tmux server (not bare `start-server`, which self-exits under exit-empty
# with zero sessions) and must hand tmux-resurrect's restore.sh a valid
# $TMUX so its `tmux_socket()` (`echo $TMUX | cut -d',' -f1`) doesn't resolve
# to an empty socket path. Regression target: a real headless reboot-resume
# run looped "no server running" / "error creating  (No such file or
# directory)" / "[: -ne: unary operator expected" once per window in the
# saved layout, and never created a session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_LOG_DIR="$TMP/logs"
unset TMUX
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"

# Empty snapshot: Phase 2 (necro-restore.sh) has nothing to restore, so this
# test isolates Phase 1's server-bootstrap + resurrect-fallback behavior.
SNAPSHOT="$NECROMANCER_SNAPSHOT_DIR/reboot.idle-only.jsonl"
: > "$SNAPSHOT"
ln -sfn "$SNAPSHOT" "$NECROMANCER_SNAPSHOT_DIR/latest-for-reboot"

SESSIONS_FILE="$TMP/sessions"
RESURRECT_CAPTURE="$TMP/resurrect_tmux_env"
FAKE_SOCKET="$TMP/fake-tmux-socket"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
SESSIONS_FILE="$SESSIONS_FILE"
FAKE_SOCKET="$FAKE_SOCKET"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  list-sessions)
    [ -s "$SESSIONS_FILE" ] || exit 1
    cat "$SESSIONS_FILE"
    exit 0
    ;;
  new-session)
    # new-session -d -s NAME [-c cwd] [-n name]
    name=""
    prev=""
    for arg in "$@"; do
      [ "$prev" = "-s" ] && name="$arg"
      prev="$arg"
    done
    [ -n "$name" ] && echo "$name" >> "$SESSIONS_FILE"
    exit 0
    ;;
  kill-session)
    name=""
    prev=""
    for arg in "$@"; do
      [ "$prev" = "-t" ] && name="$arg"
      prev="$arg"
    done
    [ -n "$name" ] && grep -Fxv "$name" "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" 2>/dev/null || : > "$SESSIONS_FILE.tmp"
    mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
    exit 0
    ;;
  display-message)
    case "$*" in
      *'#{socket_path}'*) printf '%s\n' "$FAKE_SOCKET" ;;
    esac
    exit 0
    ;;
  list-panes)
    exit 0
    ;;
  list-windows)
    exit 0
    ;;
  has-session)
    exit 0
    ;;
  show-option)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

RESURRECT_RESTORE="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
mkdir -p "$(dirname "$RESURRECT_RESTORE")"
cat > "$RESURRECT_RESTORE" <<EOF
#!/usr/bin/env bash
printf '%s' "\$TMUX" > "$RESURRECT_CAPTURE"
EOF
chmod +x "$RESURRECT_RESTORE"

out="$(printf 'n\n' | bash "$ROOT/scripts/necro-reboot-resume.sh" 2>&1)"

grep -Fq "_necro_boot_" "$SESSIONS_FILE" || {
  echo "FAIL: Phase 1 never seeded a placeholder session — bare 'tmux start-server' self-exits with 0 sessions (exit-empty)" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: Phase 1 seeds a real session instead of bare start-server"

[ -s "$RESURRECT_CAPTURE" ] || {
  echo "FAIL: resurrect restore.sh was never invoked" >&2
  echo "$out" >&2
  exit 1
}
captured_tmux="$(cat "$RESURRECT_CAPTURE")"
[ -n "$captured_tmux" ] || {
  echo "FAIL: \$TMUX passed to resurrect restore.sh is empty — tmux_socket() will resolve to an empty -S path and crash" >&2
  echo "$out" >&2
  exit 1
}
case "$captured_tmux" in
  "$FAKE_SOCKET,"*) : ;;
  *)
    echo "FAIL: \$TMUX ('$captured_tmux') doesn't carry the socket path ('$FAKE_SOCKET') as its first field" >&2
    exit 1
    ;;
esac
echo "PASS: resurrect restore.sh receives a valid \$TMUX derived from the running server's socket"

grep -Fq "Server up (1 session(s))" <<<"$out" || {
  echo "FAIL: expected exactly 1 session (the placeholder) after Phase 1 with an empty snapshot" >&2
  echo "$out" >&2
  exit 1
}
echo "PASS: placeholder session is kept when nothing else exists yet"
