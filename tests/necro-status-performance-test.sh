#!/usr/bin/env bash
# necro-status-performance-test.sh — status rendering must batch pane options.
# Regression target: two tmux show-option forks per pane on every refresh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin"

CALLS="$TMP/tmux-calls"
STATE="$TMP/pane-options"
: > "$CALLS"

cat > "$TMP/bin/tmux" <<'TMUX_STUB'
#!/usr/bin/env bash
set -u
CALLS="${CALLS:?}"
STATE="${STATE:?}"
printf '%s\n' "$*" >> "$CALLS"

case "$1" in
  show-options)
    if [ "${2:-}" = "-g" ]; then
      printf '%s\n' '@necromancer_status on' '@necromancer_status_label "necro"' '@necromancer_agents "claude codex"'
      exit 0
    fi
    pane="${4:-}"
    while IFS='|' read -r saved_pane option value; do
      [ "$saved_pane" = "$pane" ] || continue
      printf '%s %s\n' "$option" "$value"
    done < "$STATE"
    exit 0
    ;;
  show-option)
    exit 1
    ;;
  list-panes)
    printf '%%1\tclaude\n%%2\tcodex\n%%3\tzsh\n'
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUX_STUB
chmod +x "$TMP/bin/tmux"

printf '%%1|@necro_uuid|claude-uuid\n%%1|@necro_agent_exited|0\n' >> "$STATE"
printf '%%2|@necro_uuid|codex-uuid\n%%2|@necro_agent_exited|1\n' >> "$STATE"
export CALLS STATE PATH="$TMP/bin:$PATH"

output="$(bash "$ROOT/scripts/necro-status.sh")"
[ "$output" = ' necro:2/2+1 ' ] || {
  printf 'FAIL: unexpected status output: %s\n' "$output" >&2
  exit 1
}

batched="$(grep -c '^show-options -p -t ' "$CALLS" || true)"
[ "$batched" -eq 3 ] || {
  printf 'FAIL: expected one batched pane-options query per pane, got %s\n' "$batched" >&2
  exit 1
}

legacy="$(grep -c '^show-option ' "$CALLS" || true)"
[ "$legacy" -eq 0 ] || {
  printf 'FAIL: legacy per-option tmux queries remain: %s\n' "$legacy" >&2
  exit 1
}

echo 'PASS: status output is correct and pane options are batched'
