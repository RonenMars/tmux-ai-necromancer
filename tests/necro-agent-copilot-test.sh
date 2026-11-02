#!/usr/bin/env bash
# Copilot adapter: (1) only `copilot` (or @necromancer_copilot_commands globs)
# matches, (2) --resume <uuid> is read from argv, (3) sessions resolve by the
# cwd in workspace.yaml, skip sessions with no events.jsonl, and honor min_epoch.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OPT_LINE=""
tmux() {
  case "${1:-}" in
    show-options) printf '%s\n' "$OPT_LINE" ;;
    display-message) echo 4242 ;;
  esac
  return 0
}
pgrep() { echo 4343; }
PS_ARGV=""
ps() { printf '%s\n' "$PS_ARGV"; }

. "$ROOT/lib/common.sh"
. "$ROOT/lib/agents/copilot.sh"
reload_opts() { _NECRO_TMUX_OPTS_G_LOADED=""; _NECRO_TMUX_OPTS_G_CACHE=""; }

UUID="aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
fail=0
check() { # label want got
  if [ "$2" = "$3" ]; then echo "  ok: $1"; else echo "  FAIL: $1 (want '$2' got '$3')"; fail=1; fi
}
matches() { agent_copilot_matches "$1" && echo y || echo n; }

echo "matches"
reload_opts
check "copilot"            y "$(matches copilot)"
check "node is not copilot" n "$(matches node)"
check "gh is not copilot"   n "$(matches gh)"
check "claude is not copilot" n "$(matches claude)"
check "empty"               n "$(matches "")"
OPT_LINE='@necromancer_copilot_commands copilot copilot-*'
reload_opts
check "glob copilot-beta"   y "$(matches copilot-beta)"
OPT_LINE=""; reload_opts

echo "scrape_ps_resume"
scrape() { PS_ARGV="$1"; agent_copilot_scrape_ps_resume %1; }
check "--resume <uuid>" "$UUID" "$(scrape "copilot --resume $UUID")"
check "--resume=<uuid>" "$UUID" "$(scrape "copilot --resume=$UUID")"
check "fresh session"   ""      "$(scrape "copilot")"
check "--resume no id"  ""      "$(scrape "copilot --resume")"

echo "all_session_ids"
COPILOT_SESSIONS_DIR="$TMP/state"
CWD="$TMP/proj"; mkdir -p "$CWD"; PHYS="$(cd -P "$CWD" && pwd -P)"
mk() { # id cwd has_events touch-stamp
  mkdir -p "$COPILOT_SESSIONS_DIR/$1"
  printf 'id: %s\ncwd: %s\nclient_name: github/cli\n' "$1" "$2" > "$COPILOT_SESSIONS_DIR/$1/workspace.yaml"
  if [ "$3" = 1 ]; then : > "$COPILOT_SESSIONS_DIR/$1/events.jsonl"; touch -t "$4" "$COPILOT_SESSIONS_DIR/$1/events.jsonl"; fi
}
mk old   "$PHYS" 1 202601010000
mk new   "$PHYS" 1 202602010000
mk blank "$PHYS" 0 202603010000
mk other "$TMP/elsewhere" 1 202603010000
check "newest first, skips unprompted + other cwd" "new
old" "$(agent_copilot_all_session_ids "$CWD")"
check "latest" "new" "$(agent_copilot_latest_session_id "$CWD")"
floor="$(date -j -f %Y%m%d%H%M 202601150000 +%s 2>/dev/null || date -d 2026-01-15 +%s)"
check "min_epoch drops older session" "new" "$(agent_copilot_all_session_ids "$CWD" "$floor")"
ln -s "$PHYS" "$TMP/link"
check "symlinked cwd resolves to the physical path" "new
old" "$(agent_copilot_all_session_ids "$TMP/link")"
mk quoted "\"$PHYS\"" 1 202604010000
check "quoted cwd in yaml still matches" "quoted" "$(agent_copilot_latest_session_id "$CWD")"
check "unknown cwd" "" "$(agent_copilot_all_session_ids /nope)"
check "no exit keys function (unverified quit command)" n "$(declare -f agent_copilot_exit_keys >/dev/null && echo y || echo n)"
check "resume cmd" "copilot --resume $UUID" "$(agent_copilot_resume_cmd "$UUID")"

[ "$fail" = 0 ] && echo PASS || { echo FAILED; exit 1; }
