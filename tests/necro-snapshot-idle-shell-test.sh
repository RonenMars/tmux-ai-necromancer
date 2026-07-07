#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
UUID="11111111-1111-1111-1111-111111111111"
mkdir -p "$CWD" "$HOME/.claude/projects/${CWD//\//-}"
printf 'stale transcript\n' > "$HOME/.claude/projects/${CWD//\//-}/$UUID.jsonl"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes)
    printf '%%1\ts\t1\tw\t$CWD\tzsh\n'
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

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null

SNAP="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.idle-only.jsonl | head -1)"
agent="$(jq -r '.agent' "$SNAP")"
uuid="$(jq -r '.uuid' "$SNAP")"
source="$(jq -r '.uuid_source' "$SNAP")"

[ "$agent" = "" ] || {
  echo "expected idle shell agent to be empty, got: $agent" >&2
  exit 1
}

[ "$uuid" = "" ] || {
  echo "expected idle shell uuid to be empty, got: $uuid" >&2
  exit 1
}

[ "$source" = "" ] || {
  echo "expected idle shell uuid_source to be empty, got: $source" >&2
  exit 1
}
