#!/usr/bin/env bash
# Test: reboot resume asks about idle-window cleanup and honors yes in dry-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
export NECROMANCER_LOG_DIR="$TMP/logs"
unset TMUX
mkdir -p "$NECROMANCER_SNAPSHOT_DIR" "$NECROMANCER_LOG_DIR"

SNAPSHOT="$NECROMANCER_SNAPSHOT_DIR/reboot.idle-only.jsonl"
printf '{"session":"alpha","window_name":"work","cwd":"%s","agent":"codex","uuid":"11111111-1111-1111-1111-111111111111"}\n' "$TMP" > "$SNAPSHOT"
ln -sfn "$SNAPSHOT" "$NECROMANCER_SNAPSHOT_DIR/latest-for-reboot"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
cat > "$TMPBIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  show-option)
    exit 0
    ;;
  list-sessions)
    echo "existing: 1 windows"
    exit 0
    ;;
  list-panes)
    echo "@1 999999"
    exit 0
    ;;
  list-windows)
    case "$*" in
      *"#{window_id} #{session_name}:#{window_index}"*)
        echo "@1 existing:0"
        ;;
      *"#{@necro_id}"*)
        :
        ;;
      *"#{window_id}"*)
        echo "@2"
        ;;
    esac
    exit 0
    ;;
  has-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

export PATH="$TMPBIN:$PATH"

out="$(printf 'y\n' | bash "$ROOT/scripts/necro-reboot-resume.sh" --dry-run 2>&1)"

grep -F "Clean up idle tmux windows before resuming? [y/N]" <<<"$out" >/dev/null || {
  echo "FAIL: missing cleanup prompt" >&2
  echo "$out" >&2
  exit 1
}

grep -F "[dry-run] would kill idle window: existing:0 (@1)" <<<"$out" >/dev/null || {
  echo "FAIL: cleanup dry-run did not preview idle window kill" >&2
  echo "$out" >&2
  exit 1
}

grep -F "Phase 2: necro-restore.sh" <<<"$out" >/dev/null || {
  echo "FAIL: restore did not run after cleanup prompt" >&2
  echo "$out" >&2
  exit 1
}

echo "PASS: reboot resume cleanup prompt previews idle-window pruning"
