#!/usr/bin/env bash
# Cursor adapter: (1) `node` panes match only when argv shows the Cursor bundle,
# (2) --resume <uuid> is read from argv, (3) chats resolve via md5(cwd), skip
# empty chats, and honor min_epoch.
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
. "$ROOT/lib/agents/cursor.sh"
reload_opts() { _NECRO_TMUX_OPTS_G_LOADED=""; _NECRO_TMUX_OPTS_G_CACHE=""; }

UUID="aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
BUNDLE="/Users/x/.local/bin/agent --use-system-ca /Users/x/.local/share/cursor-agent/versions/2026.10.22-27dcf5f/index.js"
fail=0
check() { # label want got
  [ "$2" = "$3" ] && echo "  ok: $1" || { echo "  FAIL: $1 (want '$2' got '$3')"; fail=1; }
}
matches() { agent_cursor_matches "$@" && echo y || echo n; }

reload_opts
echo "matches"
PS_ARGV="$BUNDLE"
check "node + cursor argv"            y "$(matches node %1)"
check "cursor-agent needs no argv"    y "$(matches cursor-agent)"
check "node without a pane id"        n "$(matches node)"
PS_ARGV="node /app/vite.js"
check "node running something else"   n "$(matches node %1)"
PS_ARGV="$BUNDLE"
check "zsh is never cursor"           n "$(matches zsh %1)"
check "claude is never cursor"        n "$(matches claude %1)"

echo "scrape_ps_resume"
scrape() { PS_ARGV="$1"; agent_cursor_scrape_ps_resume %1; }
check "--resume <uuid>"   "$UUID" "$(scrape "$BUNDLE --resume $UUID")"
check "--resume=<uuid>"   "$UUID" "$(scrape "$BUNDLE --resume=$UUID")"
check "fresh chat"        ""      "$(scrape "$BUNDLE")"
check "--resume no id"    ""      "$(scrape "$BUNDLE --resume")"

echo "all_session_ids"
HOME="$TMP"; CURSOR_CHATS_DIR="$TMP/chats"
CWD="/work/proj"
H="$(printf '%s' "$CWD" | md5 -q 2>/dev/null || printf '%s' "$CWD" | md5sum | cut -d' ' -f1)"
mk() { mkdir -p "$CURSOR_CHATS_DIR/$H/$1"; printf '{"hasConversation":%s,"cwd":"%s"}' "$2" "$CWD" > "$CURSOR_CHATS_DIR/$H/$1/meta.json"; touch -t "$3" "$CURSOR_CHATS_DIR/$H/$1/meta.json"; }
mk old  true  202601010000
mk new  true  202602010000
mk blank false 202603010000
check "newest first, skips empty chat" "new
old" "$(agent_cursor_all_session_ids "$CWD")"
check "latest" "new" "$(agent_cursor_latest_session_id "$CWD")"
floor="$(date -j -f %Y%m%d%H%M 202601150000 +%s 2>/dev/null || date -d 2026-01-15 +%s)"
check "min_epoch drops older chat" "new" "$(agent_cursor_all_session_ids "$CWD" "$floor")"
check "unknown cwd" "" "$(agent_cursor_all_session_ids /nope)"
check "resume cmd" "cursor-agent --resume $UUID" "$(agent_cursor_resume_cmd "$UUID")"

[ "$fail" = 0 ] && echo PASS || { echo FAILED; exit 1; }
