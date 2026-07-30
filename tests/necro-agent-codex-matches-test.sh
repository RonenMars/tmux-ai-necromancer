#!/usr/bin/env bash
# necro-agent-codex-matches-test.sh — agent_codex_matches reads
# @necromancer_codex_commands, whose entries are glob patterns. The default
# ("codex codex-*") must still accept the native binary's truncated basename
# (codex-aarch64-a…) as well as the "codex" wrapper.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stubbed tmux: returns whatever OPT_LINE we set, so the option tiers are
# exercised without a live server. Must be defined before common.sh caches.
OPT_LINE=""
tmux() { [ "${1:-}" = "show-options" ] && printf '%s\n' "$OPT_LINE"; return 0; }

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/agents/codex.sh
. "$ROOT/lib/agents/codex.sh"

reload_opts() { _NECRO_TMUX_OPTS_G_LOADED=""; _NECRO_TMUX_OPTS_G_CACHE=""; }

fail=0
expect_match()    { agent_codex_matches "$1" || { echo "FAIL: expected match: '$1'"; fail=1; }; }
expect_no_match() { agent_codex_matches "$1" && { echo "FAIL: expected NO match: '$1'"; fail=1; }; }

# --- default (option unset) -------------------------------------------------
reload_opts
for cmd in codex codex-aarch64-apple-darwin codex-aarch64-a codex-x86_64-unknown-linux; do
  expect_match "$cmd"
done
for cmd in claude zsh codexify "" node; do
  expect_no_match "$cmd"
done

# --- a user-configured alias ------------------------------------------------
OPT_LINE='@necromancer_codex_commands codex codex-* cx'
reload_opts
expect_match "cx"
expect_match "codex"
expect_match "codex-aarch64-a"
expect_no_match "cxx"

# --- a narrowed list drops the prefix pattern -------------------------------
OPT_LINE='@necromancer_codex_commands codex'
reload_opts
expect_match "codex"
expect_no_match "codex-aarch64-a"

# --- the glob must not be pathname-expanded against the cwd -----------------
# Splitting the unquoted list inside the matcher would expand `codex-*` to the
# filenames below, so `codex-aarch64-a` would stop matching and the unrelated
# file name would start matching.
mkdir -p "$TMP/globtrap" && : > "$TMP/globtrap/codex-decoy"
OPT_LINE='@necromancer_codex_commands codex codex-*'
reload_opts
(
  cd "$TMP/globtrap" || exit 1
  agent_codex_matches "codex-aarch64-a" || { echo "FAIL: glob expanded against cwd — prefix stopped matching"; exit 1; }
  agent_codex_matches "codex-decoy"     || { echo "FAIL: codex-decoy should match codex-* on its own merits"; exit 1; }
  agent_codex_matches "totally-unrelated" && { echo "FAIL: matched an unrelated command"; exit 1; }
  exit 0
) || fail=1

# --- globbing state must be restored for the caller -------------------------
case "$-" in *f*) echo "FAIL: matcher left noglob (set -f) enabled"; fail=1 ;; esac

[ "$fail" = 0 ] && echo "PASS: necro-agent-codex-matches-test" || exit 1
