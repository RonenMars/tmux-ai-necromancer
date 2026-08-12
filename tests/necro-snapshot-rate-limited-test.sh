#!/usr/bin/env bash
# --rate-limited snapshots only panes whose scrollback shows a rate/session
# limit banner. Idle-only (no exit keys). Writes *.rate-limited.jsonl.
# --auto skips panes already marked @necro_limit_saved=1 and clears the mark
# when the limit banner is gone.
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
mkdir -p "$CWD"

STATE="$TMP/pane-opts"
: > "$STATE"
CALLS="$TMP/tmux-calls.log"
: > "$CALLS"

# Three panes: limited claude, unlimited claude, limited codex.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS"
STATE="$STATE"
CWD="$CWD"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  list-panes)
    printf '%%1\tsess\t1\tw1\t%s\tclaude\tlayout\t0\t1\t1\n' "$CWD"
    printf '%%2\tsess\t2\tw2\t%s\tclaude\tlayout\t0\t0\t0\n' "$CWD"
    printf '%%3\tsess\t3\tw3\t%s\tcodex\tlayout\t0\t0\t0\n' "$CWD"
    ;;
  capture-pane)
    # -t %N somewhere in argv
    target=""
    prev=""
    for a in "$@"; do
      if [ "$prev" = "-t" ]; then target="$a"; fi
      prev="$a"
    done
    case "$target" in
      %1) printf "You've hit your session limit · resets 12:40pm\n" ;;
      %2) printf "Working on the next step…\n" ;;
      %3) printf "You've hit your usage limit. Upgrade to Pro\n" ;;
      *) printf "\n" ;;
    esac
    ;;
  show-option)
    if [ "$2" = "-gqv" ] || [ "$2" = "-gq" ]; then exit 0; fi
    # show-option -pqv -t %N @necro_*
    pane=""; opt=""
    prev=""
    for a in "$@"; do
      case "$prev" in -t) pane="$a" ;; esac
      prev="$a"
    done
    opt="${@: -1}"
    line="$(grep -F "${pane}|${opt}=" "$STATE" 2>/dev/null | tail -1)"
    if [ -n "$line" ]; then printf '%s\n' "${line#*=}"; fi
    exit 0
    ;;
  set-option)
    if [ "$2" = "-gq" ] || [ "$2" = "-g" ]; then exit 0; fi
    if [ "$2" = "-pu" ]; then
      pane="$4"; opt="$5"
      printf '%s|%s=\n' "$pane" "$opt" >> "$STATE"
      exit 0
    fi
    # set-option -p -t %N @opt val
    pane="$4"; opt="$5"; val="${6:-}"
    printf '%s|%s=%s\n' "$pane" "$opt" "$val" >> "$STATE"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

# Seed pane options with UUIDs so idle-only capture has ids.
printf '%%1|@necro_uuid=11111111-1111-1111-1111-111111111111\n' >> "$STATE"
printf '%%2|@necro_uuid=22222222-2222-2222-2222-222222222222\n' >> "$STATE"
printf '%%3|@necro_uuid=33333333-3333-3333-3333-333333333333\n' >> "$STATE"

bash "$ROOT/scripts/necro-snapshot.sh" --rate-limited >/dev/null 2>&1 </dev/null

if grep -q '^send-keys' "$CALLS"; then
  echo "FAIL: send-keys called under --rate-limited" >&2
  exit 1
fi

SNAP="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.rate-limited.jsonl 2>/dev/null | head -1)"
if [ -z "$SNAP" ]; then
  echo "FAIL: no *.rate-limited.jsonl written" >&2
  exit 1
fi

n="$(wc -l < "$SNAP" | tr -d ' ')"
if [ "$n" != "2" ]; then
  echo "FAIL: expected 2 rate-limited records, got $n:" >&2
  cat "$SNAP" >&2
  exit 1
fi

grep -q '"pane_id":"%1"' "$SNAP" || { echo "FAIL: missing limited claude %1" >&2; exit 1; }
grep -q '"pane_id":"%3"' "$SNAP" || { echo "FAIL: missing limited codex %3" >&2; exit 1; }
grep -q '"pane_id":"%2"' "$SNAP" && { echo "FAIL: unlimited %2 should be excluded" >&2; exit 1; }

grep -q '%1|@necro_limit_saved=1' "$STATE" || { echo "FAIL: %1 not marked limit_saved" >&2; exit 1; }
grep -q '%3|@necro_limit_saved=1' "$STATE" || { echo "FAIL: %3 not marked limit_saved" >&2; exit 1; }

# --auto: already-marked panes are skipped → no new file (or empty skipped).
: > "$CALLS"
before_count="$(/bin/ls "$NECROMANCER_SNAPSHOT_DIR"/*.rate-limited.jsonl 2>/dev/null | wc -l | tr -d ' ')"
bash "$ROOT/scripts/necro-snapshot.sh" --rate-limited --auto >/dev/null 2>&1 </dev/null
after_count="$(/bin/ls "$NECROMANCER_SNAPSHOT_DIR"/*.rate-limited.jsonl 2>/dev/null | wc -l | tr -d ' ')"
if [ "$after_count" != "$before_count" ]; then
  echo "FAIL: --auto re-wrote a snapshot when all limited panes were already saved ($before_count → $after_count)" >&2
  exit 1
fi

echo "PASS: necro-snapshot-rate-limited-test"
