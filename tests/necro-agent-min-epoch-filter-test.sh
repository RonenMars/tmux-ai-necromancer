#!/usr/bin/env bash
# necro-agent-min-epoch-filter-test.sh — the cursor-pop fallback must not hand
# out a transcript that predates the pane it's being pinned to. Regression
# target: a stale session from days/weeks ago getting silently pinned to a
# freshly-created pane (see PR discussion following a terminal-crash restore).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
CWD="$TMP/workspace"
mkdir -p "$CWD"
PROJ_DIR="$HOME/.claude/projects/${CWD//\//-}"
mkdir -p "$PROJ_DIR"

STALE_UUID="aaaaaaaa-1111-1111-1111-111111111111"
FRESH_UUID="bbbbbbbb-2222-2222-2222-222222222222"

echo '{"type":"user","message":{"content":"old work"}}' > "$PROJ_DIR/$STALE_UUID.jsonl"
echo '{"type":"user","message":{"content":"new work"}}' > "$PROJ_DIR/$FRESH_UUID.jsonl"

# Stale transcript: touched well before the pane's first-seen time.
touch -t 202001010000 "$PROJ_DIR/$STALE_UUID.jsonl"
# Fresh transcript: touched after.
touch -t 203001010000 "$PROJ_DIR/$FRESH_UUID.jsonl"

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/agents/claude.sh
. "$ROOT/lib/agents/claude.sh"

# Pane "first seen" between the two file mtimes.
MIN_EPOCH="$(date -j -f "%Y%m%d%H%M" "202501010000" +%s 2>/dev/null || date -d "2025-01-01" +%s)"

ids="$(agent_claude_all_session_ids "$CWD" "$MIN_EPOCH")"

echo "$ids" | grep -q "$STALE_UUID" && {
  echo "FAIL: stale transcript was NOT filtered out" >&2
  exit 1
}
echo "$ids" | grep -q "$FRESH_UUID" || {
  echo "FAIL: fresh transcript was incorrectly filtered out" >&2
  exit 1
}
echo "PASS: min_epoch filter excludes stale transcripts, keeps fresh ones"

# No min_epoch given: both must still be candidates (backward compatible).
ids_unfiltered="$(agent_claude_all_session_ids "$CWD")"
echo "$ids_unfiltered" | grep -q "$STALE_UUID" || {
  echo "FAIL: omitting min_epoch should not filter anything" >&2
  exit 1
}
echo "PASS: omitting min_epoch preserves old (unfiltered) behavior"
