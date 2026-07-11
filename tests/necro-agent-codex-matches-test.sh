#!/usr/bin/env bash
# necro-agent-codex-matches-test.sh — agent_codex_matches accepts the native
# binary's truncated basename (codex-aarch64-a…), not just the "codex" wrapper.
set -uo pipefail

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/agents/codex.sh
. "$SELF_DIR/../lib/agents/codex.sh"

fail=0
for cmd in codex codex-aarch64-apple-darwin codex-aarch64-a codex-x86_64-unknown-linux; do
  agent_codex_matches "$cmd" || { echo "FAIL: expected match: $cmd"; fail=1; }
done
for cmd in claude zsh codexify "" node; do
  agent_codex_matches "$cmd" && { echo "FAIL: expected no match: '$cmd'"; fail=1; }
done

[ "$fail" = 0 ] && echo "PASS: necro-agent-codex-matches-test" || exit 1
