#!/usr/bin/env bash
# necro-agent-claude-matches-test.sh — agent_claude_matches reads
# @necromancer_claude_commands and treats entries as glob patterns, matching
# agent_codex_matches. A plain name must still behave as an exact match, so
# existing `claude cc` config keeps working unchanged.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OPT_LINE=""
tmux() { [ "${1:-}" = "show-options" ] && printf '%s\n' "$OPT_LINE"; return 0; }

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/agents/claude.sh
. "$ROOT/lib/agents/claude.sh"

reload_opts() { _NECRO_TMUX_OPTS_G_LOADED=""; _NECRO_TMUX_OPTS_G_CACHE=""; }

fail=0
expect_match()    { agent_claude_matches "$1" || { echo "FAIL: expected match: '$1'"; fail=1; }; }
expect_no_match() { agent_claude_matches "$1" && { echo "FAIL: expected NO match: '$1'"; fail=1; }; }

# --- default (option unset) -------------------------------------------------
reload_opts
expect_match "claude"
for cmd in cc codex zsh "" claudex; do
  expect_no_match "$cmd"
done

# --- the documented alias list stays an exact match -------------------------
OPT_LINE='@necromancer_claude_commands claude cc'
reload_opts
expect_match "claude"
expect_match "cc"
expect_no_match "ccx"
expect_no_match "claudex"

# --- patterns work here too, same semantics as codex ------------------------
OPT_LINE='@necromancer_claude_commands claude claude-*'
reload_opts
expect_match "claude-wrapper"
expect_no_match "notclaude"

# --- globbing state must be restored for the caller -------------------------
case "$-" in *f*) echo "FAIL: matcher left noglob (set -f) enabled"; fail=1 ;; esac

[ "$fail" = 0 ] && echo "PASS: necro-agent-claude-matches-test" || exit 1
