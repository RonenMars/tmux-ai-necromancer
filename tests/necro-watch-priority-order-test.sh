#!/usr/bin/env bash
# necro-watch-priority-order-test.sh — necro-watch.sh's pinning priority
# (process argv > scrollback > cursor-pop) must hold end-to-end, not just in
# each helper function tested in isolation. Regression target: someone
# reorders/short-circuits the Case-2 if-chain in necro-watch.sh and every
# per-function unit test still passes because each only exercises one tier.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snapshots"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

CWD="$TMP/work"
ARGV_UUID="aaaaaaaa-0000-0000-0000-000000000001"
SCROLLBACK_UUID="bbbbbbbb-0000-0000-0000-000000000002"
CURSOR_UUID="cccccccc-0000-0000-0000-000000000003"
# Resolve the transcript dir via the adapter — Claude encodes '/', '.' and '_'
# all as '-', and a fixture that hardcodes only the '/' rule silently diverges
# from the code under test (mktemp paths contain underscores).
PROJ_DIR="$(
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/agents/claude.sh"
  agent_claude_project_dir "$CWD"
)"
mkdir -p "$CWD" "$PROJ_DIR"
# Only the cursor-pop candidate needs a real transcript file on disk. Its
# mtime must be >= the pane's first-seen time (necro-watch.sh stamps that as
# "now" when it first sees the pane) or the min_epoch filter — correctly —
# rejects it as a stale transcript; that behavior has its own dedicated test
# (necro-agent-min-epoch-filter-test.sh), so backdate first-seen instead of
# fighting the filter here.
printf '{"type":"user","message":{"content":"hi"}}\n' > "$PROJ_DIR/$CURSOR_UUID.jsonl"

# State file the stub tmux uses to report pane options across calls within one
# necro-watch.sh invocation (real tmux persists these server-side).
STATE="$TMP/pane-opts"
: > "$STATE"

# Args: which tiers should "succeed". Each test run configures via env.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
STATE="$STATE"
CWD="$CWD"
ARGV_UUID="$ARGV_UUID"
SCROLLBACK_UUID="$SCROLLBACK_UUID"
EOF
cat >> "$TMPBIN/tmux" <<'EOF'
case "$1" in
  show-option)
    if [ "$2" = "-gqv" ]; then
      opt="$3"
      case "$opt" in
        @necromancer_last_watch) printf '0\n' ;;
        @necromancer_agents) printf 'claude\n' ;;
        *) printf '\n' ;;
      esac
      exit 0
    fi
    # -pqv -t <pane> <opt> — pane option reads. $2=-pqv $3=-t $4=<pane> $5=<opt>
    opt="${5:-}"
    line="$(grep -F "|$opt=" "$STATE" 2>/dev/null | tail -1)"
    if [ -n "$line" ]; then
      printf '%s\n' "${line#*=}"
    fi
    exit 0
    ;;
  set-option)
    # -gq <opt> <val>            (global)
    # -p -t <pane> <opt> <val>   (per-pane set)
    # -pu -t <pane> <opt>        (per-pane unset)
    if [ "$2" = "-gq" ]; then exit 0; fi
    if [ "$2" = "-pu" ]; then
      pane="$4"; opt="$5"
      printf '%s|%s=\n' "$pane" "$opt" >> "$STATE"
      exit 0
    fi
    # $2=-p $3=-t $4=<pane> $5=<opt> $6=<val>
    pane="$4"; opt="$5"; val="${6:-}"
    printf '%s|%s=%s\n' "$pane" "$opt" "$val" >> "$STATE"
    exit 0
    ;;
  list-panes)
    printf '%%1\tclaude\t%s\n' "$CWD"
    exit 0
    ;;
  display-message)
    # pane_pid lookup for scrape_ps_resume
    printf '999\n'
    exit 0
    ;;
  capture-pane)
    if [ -n "${NECRO_TEST_SCROLLBACK_HIT:-}" ]; then
      printf -- "--resume %s\n" "$SCROLLBACK_UUID"
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"

# Stub pgrep/ps so scrape_ps_resume can find the "process argv" tier.
cat > "$TMPBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
[ -n "${NECRO_TEST_ARGV_HIT:-}" ] && echo "1234"
exit 0
EOF
chmod +x "$TMPBIN/pgrep"

cat > "$TMPBIN/ps" <<EOF
#!/usr/bin/env bash
[ -n "\${NECRO_TEST_ARGV_HIT:-}" ] && printf 'claude --resume %s\n' "$ARGV_UUID"
exit 0
EOF
chmod +x "$TMPBIN/ps"

export PATH="$TMPBIN:$PATH"

run_watch() {
  # Pre-seed first_seen to a time before the cursor-pop transcript's mtime so
  # the min_epoch filter (tested separately) doesn't reject a same-second
  # write purely on timing noise.
  printf '%%1|@necro_pane_first_seen=1\n' > "$STATE"
  bash "$ROOT/scripts/necro-watch.sh" >/dev/null 2>&1
  grep -F '%1|@necro_uuid=' "$STATE" | tail -1 | cut -d= -f2-
}

# Case A: all three tiers available — argv must win.
export NECRO_TEST_ARGV_HIT=1 NECRO_TEST_SCROLLBACK_HIT=1
got="$(run_watch)"
[ "$got" = "$ARGV_UUID" ] || {
  echo "FAIL: all tiers available, expected argv UUID ($ARGV_UUID), got '$got'" >&2
  exit 1
}
echo "PASS: argv wins when all three tiers are available"

# Case B: argv unavailable, scrollback + cursor-pop available — scrollback wins.
unset NECRO_TEST_ARGV_HIT
export NECRO_TEST_SCROLLBACK_HIT=1
got="$(run_watch)"
[ "$got" = "$SCROLLBACK_UUID" ] || {
  echo "FAIL: argv unavailable, expected scrollback UUID ($SCROLLBACK_UUID), got '$got'" >&2
  exit 1
}
echo "PASS: scrollback wins when argv is unavailable"

# Case C: only cursor-pop available — falls all the way through.
unset NECRO_TEST_SCROLLBACK_HIT
got="$(run_watch)"
[ "$got" = "$CURSOR_UUID" ] || {
  echo "FAIL: only cursor-pop available, expected $CURSOR_UUID, got '$got'" >&2
  exit 1
}
echo "PASS: cursor-pop fallback used only when both higher tiers are unavailable"
