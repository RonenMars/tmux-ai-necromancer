#!/usr/bin/env bash
# Invariant 9: process argv is ground truth for pane UUID pinning.
# Codex resumes via the subcommand form `codex resume [OPTIONS] <SESSION_ID>`
# (positional, no --resume flag), so the Claude flag-based scrape doesn't
# transfer. Verify the codex scrape reads a positional UUID out of argv.
set -uo pipefail

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents/codex.sh"

UUID="dddddddd-1111-2222-3333-eeeeeeeeeeee"
fails=0

# Stub tmux/pgrep/ps so no live server or codex process is needed.
tmux() { echo 12345; }
pgrep() { echo 999; }
export -f tmux pgrep 2>/dev/null || true

run_case() { # run_case <label> <argv-line> <expected>
  local label="$1" argv="$2" want="$3" got
  ps() { printf '%s\n' "$argv"; }
  got="$(agent_codex_scrape_ps_resume '%1' 2>/dev/null)"
  if [ "$got" = "$want" ]; then
    echo "  ok: $label"
  else
    echo "  FAIL: $label"
    echo "        argv: $argv"
    echo "        want: '$want'  got: '$got'"
    fails=$((fails + 1))
  fi
}

echo "codex scrape_ps_resume"
run_case "plain resume <uuid>"        "codex resume $UUID"                  "$UUID"
run_case "resume with options"        "codex resume --yolo $UUID"           "$UUID"
run_case "native binary basename"     "codex-aarch64-apple-darwin resume $UUID" "$UUID"
run_case "fresh session (no resume)"  "codex"                               ""
run_case "resume --last (no uuid)"    "codex resume --last"                 ""

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS"
