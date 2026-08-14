#!/usr/bin/env bash
# The snapshot's latest-jsonl fallback must honor @necro_pane_first_seen.
#
# Regression: resolve_fallback_id popped a session id with no min_epoch, so a
# pane with no pinned UUID adopted the newest transcript in its cwd even when
# that transcript's last write predated the pane. The pop's other two filters
# don't cover it — the per-run cursor only knows ids it handed out this run, and
# the live-pin set stops covering an id as soon as the pane holding it releases
# it (a /clear abandons the old session id). Observed in production: a pane's
# first snapshot recorded a conversation last written 13 minutes before the pane
# existed, which restore would then resume into the wrong pane.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

# Resolve project dirs through the adapter, never a hand-rolled ${cwd//\//-} —
# Claude encodes '.' and '_' as '-' too, and a mktemp path has both.
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/agents/claude.sh
. "$ROOT/lib/agents/claude.sh"

NOW="$(date +%s)"
FIRST_SEEN=$((NOW - 300))     # pane's agent first seen 5 min ago

# Set a file's mtime from an epoch. BSD spells it `date -r EPOCH`, GNU spells
# it `date -d @EPOCH` and reads -r as a reference FILE, so the bare BSD form
# fails on Linux/WSL2 and the touch then silently stamps "now" instead.
touch_epoch() { # touch_epoch <epoch> <file>
  touch -t "$(date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S)" "$2"
}

STALE_CWD="$TMP/stale"
STALE_UUID="11111111-1111-1111-1111-111111111111"
mkdir -p "$STALE_CWD" "$(agent_claude_project_dir "$STALE_CWD")"
STALE_FILE="$(agent_claude_project_dir "$STALE_CWD")/$STALE_UUID.jsonl"
printf '{"role":"user"}\n' > "$STALE_FILE"
touch_epoch $((FIRST_SEEN - 600)) "$STALE_FILE"

FRESH_CWD="$TMP/fresh"
FRESH_UUID="22222222-2222-2222-2222-222222222222"
mkdir -p "$FRESH_CWD" "$(agent_claude_project_dir "$FRESH_CWD")"
FRESH_FILE="$(agent_claude_project_dir "$FRESH_CWD")/$FRESH_UUID.jsonl"
printf '{"role":"user"}\n' > "$FRESH_FILE"
touch_epoch $((FIRST_SEEN + 60)) "$FRESH_FILE"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes)
    # Two live claude panes, neither pinned. %1 is in the stale cwd, %2 fresh.
    printf '%%1\ts\t1\tw\t$STALE_CWD\tclaude\tlayout\t0\t1\t1\n'
    printf '%%2\ts\t2\tw\t$FRESH_CWD\tclaude\tlayout\t0\t0\t0\n'
    ;;
  show-option)
    for a in "\$@"; do
      [ "\$a" = "@necro_pane_first_seen" ] && { printf '%s\n' "$FIRST_SEEN"; exit 0; }
    done
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null

SNAP="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.idle-only.jsonl | head -1)"

got_stale="$(jq -r 'select(.pane_id=="%1") | .uuid' "$SNAP")"
[ -z "$got_stale" ] || {
  echo "FAIL: pane %1 adopted a transcript older than the pane: $got_stale" >&2
  exit 1
}

got_fresh="$(jq -r 'select(.pane_id=="%2") | .uuid' "$SNAP")"
[ "$got_fresh" = "$FRESH_UUID" ] || {
  echo "FAIL: pane %2 should resolve its own fresh transcript, got: '$got_fresh'" >&2
  exit 1
}

echo "PASS: snapshot fallback rejects pre-pane transcripts, keeps fresh ones"
