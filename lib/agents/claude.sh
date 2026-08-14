#!/usr/bin/env bash
# lib/agents/claude.sh — Claude Code adapter for tmux-ai-necromancer.
#
# Claude Code stores one transcript per conversation as a .jsonl file under
#   ~/.claude/projects/<cwd-with-/-.-and-_-all-as-dashes>/<uuid>.jsonl
# and resumes with `claude --resume <uuid>`. On clean exit it prints a farewell
# line containing `claude --resume <uuid>` which the snapshotter can scrape.

CLAUDE_UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# Does this pane's foreground command belong to Claude Code?
# Checks against @necromancer_claude_commands (space-separated, default
# "claude"). Entries are glob patterns, matching agent_codex_matches — a plain
# name like `claude` or `cc` has no metacharacters and behaves as an exact
# match, so this is backward compatible.
agent_claude_matches() {
  local cmd="$1" name cmds matched=1
  cmds="$(necro_tmux_option @necromancer_claude_commands claude)"
  # See agent_codex_matches: splitting the unquoted list would pathname-expand
  # any pattern against the cwd. `case` matching is unaffected by `set -f`.
  set -f
  for name in $cmds; do
    # shellcheck disable=SC2254
    case "$cmd" in $name) matched=0; break ;; esac
  done
  set +f
  return "$matched"
}

# Per-project transcript directory for a cwd ("" if none).
# Claude encodes '/', '.' and '_' all as '-' (verified against every project
# dir on disk). Encoding only '/' misses any cwd with a dot or underscore —
# e.g. a `.worktrees/` checkout — and the lookup silently finds nothing.
agent_claude_project_dir() {
  local cwd="$1"
  local enc="$cwd"
  enc="${enc//\//-}"
  enc="${enc//./-}"
  enc="${enc//_/-}"
  printf '%s' "$HOME/.claude/projects/$enc"
}

agent_claude_transcript_path() {
  local uuid="$1" cwd="$2"
  printf '%s/%s.jsonl' "$(agent_claude_project_dir "$cwd")" "$uuid"
}

agent_claude_transcript_size() {
  local uuid="$1" cwd="$2" path
  path="$(agent_claude_transcript_path "$uuid" "$cwd")"
  [ -f "$path" ] || return 0
  wc -c < "$path" | tr -d ' '
}

# Most-recent session id (UUID) for a cwd via filesystem fallback ("" if none).
agent_claude_latest_session_id() {
  local cwd="$1"
  agent_claude_all_session_ids "$cwd" | head -1
}

# All session ids for a cwd, newest-first, one per line.
# Excludes teammate/subagent transcripts (first line is a <teammate-message>
# from the Agent/SendMessage subagent harness) — those are never a pane's
# primary interactive session and must not be handed out by the cursor pop.
#
# Optional 2nd arg: min_epoch. When given, a transcript is only a candidate
# if its mtime is >= min_epoch — a transcript last touched before the pane
# existed can't be that pane's session. This is a proxy filter, not proof
# (mtime is "last write", not "created"), but it's enough to reject sessions
# that are days/weeks stale relative to the pane, which is the failure mode
# this guards against.
agent_claude_all_session_ids() {
  local cwd="$1" min_epoch="${2:-}" proj_dir f mtime
  proj_dir="$(agent_claude_project_dir "$cwd")"
  [ -d "$proj_dir" ] || return 0
  # Read the listing line-by-line: `for f in $(ls ...)` word-splits on spaces,
  # so a cwd containing a space yields a project dir whose files are chopped
  # into fragments and the lookup silently returns nothing.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -n "$min_epoch" ]; then
      mtime="$(necro_file_mtime "$f")"
      [ -n "$mtime" ] && [ "$mtime" -lt "$min_epoch" ] && continue
    fi
    head -c 400 "$f" 2>/dev/null | grep -q '<teammate-message' && continue
    basename "$f" | sed -nE "s/^($CLAUDE_UUID_RE)\.jsonl\$/\\1/p"
  done <<EOF
$(/bin/ls -t "$proj_dir"/*.jsonl 2>/dev/null)
EOF
}

# Scrape a session id from pane scrollback near a "resume" marker ("" if none).
agent_claude_scrape_session_id() {
  local pane="$1"
  tmux capture-pane -p -t "$pane" -S -200 2>/dev/null \
    | grep -iE "resume.*$CLAUDE_UUID_RE|$CLAUDE_UUID_RE.*resume" \
    | tail -1 \
    | grep -oE "$CLAUDE_UUID_RE" \
    | head -1
}

# Scrape a UUID from a startup "--resume <uuid>" line in scrollback.
# Used by the watcher when a pane is first detected (resurrect edge case).
agent_claude_scrape_resume_cmd() {
  local pane="$1"
  tmux capture-pane -p -t "$pane" -S -50 2>/dev/null \
    | grep -oE -- "--resume $CLAUDE_UUID_RE" \
    | tail -1 \
    | grep -oE "$CLAUDE_UUID_RE" \
    | head -1
}

# Ground-truth UUID from the actual running process argv (not a guess).
# Reads `ps` for the pane's foreground child and extracts `--resume <uuid>`
# if present. Returns "" for a fresh (non-resumed) session — that's not a
# failure, it just means this pane has no prior session id to report yet.
agent_claude_scrape_ps_resume() {
  local pane="$1" pane_pid child
  pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)"
  [ -n "$pane_pid" ] || return 0
  for child in $(pgrep -P "$pane_pid" 2>/dev/null); do
    ps -o command= -p "$child" 2>/dev/null
  done | grep -oE -- "--resume $CLAUDE_UUID_RE" \
    | grep -oE "$CLAUDE_UUID_RE" \
    | head -1
}

# Shell command that resumes a given session id.
agent_claude_resume_cmd() {
  printf 'claude --resume %s' "$1"
}

# Return 0 if this pane's recent scrollback shows Claude's session-limit
# banner ("You've hit your session limit · resets …"). Used by
# necro-snapshot.sh --rate-limited and the watcher's auto limit-save.
agent_claude_hit_limit() {
  local pane="$1"
  tmux capture-pane -p -t "$pane" -S -50 2>/dev/null \
    | grep -qiE 'hit your session limit'
}

# Keys to send for a clean exit when capturing a live session.
agent_claude_exit_keys() {
  printf '/exit'
}
