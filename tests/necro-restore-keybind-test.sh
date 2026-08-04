#!/usr/bin/env bash
# necro-restore-keybind-test.sh — entrypoint binds prefix+ai via a key-table
# chord by default, and still accepts a classic single-key override.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin"
CALLS="$TMP/tmux-calls"

run_entrypoint() {
  local restore_val="$1"
  : > "$CALLS"
  cat > "$TMP/bin/tmux" <<TMUX_STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${CALLS:?}"
case "\$1" in
  show-option)
    case "\${3:-}" in
      status-right) printf '' ;;
      @necromancer_debug) printf 'off' ;;
      @necromancer_restore_key) printf '%s' "$restore_val" ;;
      *) printf '' ;;
    esac
    ;;
  run-shell|set-option|bind-key) exit 0 ;;
  *) exit 0 ;;
esac
TMUX_STUB
  chmod +x "$TMP/bin/tmux"
  export CALLS PATH="$TMP/bin:$PATH"
  bash "$ROOT/tmux-ai-necromancer.tmux"
}

# Default / two-letter chord: prefix a → necro-restore table, then i runs restore.
run_entrypoint "ai"
grep -F 'bind-key -T prefix a switch-client -T necro-restore' "$CALLS" >/dev/null || {
  echo 'FAIL: chord did not bind prefix+a to necro-restore table' >&2
  cat "$CALLS" >&2
  exit 1
}
grep -E 'bind-key -T necro-restore i run-shell .*necro-restore\.sh' "$CALLS" >/dev/null || {
  echo 'FAIL: chord did not bind necro-restore+i to restore popup' >&2
  cat "$CALLS" >&2
  exit 1
}
if grep -E '^bind-key [^ ]+ run-shell' "$CALLS" | grep -v -- '-T' >/dev/null; then
  echo 'FAIL: chord path also emitted a single-key bind-key' >&2
  cat "$CALLS" >&2
  exit 1
fi

# Spaced form of the same chord.
run_entrypoint "a i"
grep -F 'bind-key -T prefix a switch-client -T necro-restore' "$CALLS" >/dev/null || {
  echo 'FAIL: spaced chord did not bind prefix+a' >&2
  exit 1
}
grep -E 'bind-key -T necro-restore i run-shell .*necro-restore\.sh' "$CALLS" >/dev/null || {
  echo 'FAIL: spaced chord did not bind necro-restore+i' >&2
  exit 1
}

# Classic single-key override still works.
run_entrypoint "R"
grep -E '^bind-key R run-shell .*necro-restore\.sh' "$CALLS" >/dev/null || {
  echo 'FAIL: single-key override did not bind prefix+R' >&2
  cat "$CALLS" >&2
  exit 1
}
if grep -F 'switch-client -T necro-restore' "$CALLS" >/dev/null; then
  echo 'FAIL: single-key override still opened the chord table' >&2
  cat "$CALLS" >&2
  exit 1
fi

echo 'PASS: restore keybind supports prefix+ai chord and single-key override'
