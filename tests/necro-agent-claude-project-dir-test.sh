#!/usr/bin/env bash
# Claude encodes '/', '.' and '_' as '-' in ~/.claude/projects/<encoded-cwd>.
# The adapter must reproduce that encoding exactly or every filesystem lookup
# (latest id, cursor pop, transcript size guard) silently finds nothing.
set -uo pipefail

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents/claude.sh"

fails=0
check() {
  local cwd="$1" want="$2" got
  got="$(basename "$(agent_claude_project_dir "$cwd")")"
  if [ "$got" = "$want" ]; then
    echo "  ok: $cwd"
  else
    echo "  FAIL: $cwd"
    echo "        want: $want"
    echo "        got:  $got"
    fails=$((fails + 1))
  fi
}

echo "claude project-dir encoding"
check "/Users/x/dev/proj" "-Users-x-dev-proj"
check "/Users/x/repo/.claude/worktrees/wt" "-Users-x-repo--claude-worktrees-wt"
check "/Users/x/repo/.worktrees/feat/thing" "-Users-x-repo--worktrees-feat-thing"
check "/private/var/folders/9r/c18379_13_q6tl6x/T" "-private-var-folders-9r-c18379-13-q6tl6x-T"
check "/Users/x/a.b_c/d" "-Users-x-a-b-c-d"

if [ "$fails" -gt 0 ]; then
  echo "FAILED ($fails)"; exit 1
fi
echo "PASS"
