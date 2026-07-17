#!/usr/bin/env bash
# Invariant 9: the cursor-pop fallback must reject transcripts older than the
# pane. agent_codex_all_session_ids took only $1 (cwd) and ignored the
# min_epoch $2 that necro_agent_pop_session_id passes — so for codex panes the
# stale-transcript filter did nothing at all.
set -uo pipefail

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP"
. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents/codex.sh"

CWD="/tmp/project-x"
SESS="$TMP/.codex/sessions/2026/07/17"
mkdir -p "$SESS"

mk() { # mk <uuid> <mtime-epoch>
  local f="$SESS/rollout-2026-07-17T00-00-00-$1.jsonl"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s"}}\n' "$1" "$CWD" > "$f"
  touch -t "$(date -r "$2" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$2" +%Y%m%d%H%M.%S)" "$f"
}

NOW="$(date +%s)"
OLD_ID="aaaaaaaa-1111-2222-3333-444444444444"
NEW_ID="bbbbbbbb-5555-6666-7777-888888888888"
mk "$OLD_ID" "$(( NOW - 7 * 86400 ))"   # a week stale
mk "$NEW_ID" "$(( NOW - 10 ))"          # fresh

fails=0

echo "codex all_session_ids honors min_epoch"
got="$(agent_codex_all_session_ids "$CWD" "$(( NOW - 3600 ))" | tr '\n' ' ')"
case "$got" in
  *"$OLD_ID"*) echo "  FAIL: stale transcript survived min_epoch filter: $got"; fails=$((fails+1)) ;;
  *"$NEW_ID"*) echo "  ok: only the fresh transcript returned" ;;
  *) echo "  FAIL: expected fresh id, got: '$got'"; fails=$((fails+1)) ;;
esac

echo "codex all_session_ids without min_epoch returns both"
got_all="$(agent_codex_all_session_ids "$CWD" | tr '\n' ' ')"
case "$got_all" in
  *"$OLD_ID"*) echo "  ok: unfiltered listing still includes stale id" ;;
  *) echo "  FAIL: unfiltered listing lost the stale id: '$got_all'"; fails=$((fails+1)) ;;
esac

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS"
