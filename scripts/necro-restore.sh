#!/usr/bin/env bash
# necro-restore.sh — recreate AI-agent tmux sessions from the latest snapshot.
#
# Reads a snapshot .jsonl (default: most-recent autosave) and, for each record
# that has an agent + session id, ensures a tmux session/window exists at the
# right cwd and resumes the agent there.
#
# IDEMPOTENT BY DESIGN — safe to run on an already-populated server:
#   - reuses an existing session instead of erroring on "duplicate session"
#   - skips a window whose (name+cwd) already exists in the target session
#   - only sends the resume command into a freshly-created idle pane
#   - never `set -e`-aborts on a tmux call; guards with `|| true` + warn
#
# This is the explicit fix for the old restore-today-sessions.sh, which ran
# `set -euo pipefail` and died with `duplicate session: <name>` the moment a
# target session already existed.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SELF_DIR/../lib/common.sh"
necro_init_log "$0"
# shellcheck source=../lib/agents.sh
. "$SELF_DIR/../lib/agents.sh"
necro_load_agents

SNAP_DIR="$(necro_snapshot_dir)"
SNAPSHOT=""
DRY_RUN=0
FORCE_LARGE=0
ALLOW_UNSAFE_CWD=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force-large) FORCE_LARGE=1; shift ;;
    --allow-unsafe-cwd) ALLOW_UNSAFE_CWD=1; shift ;;
    -h|--help)
      cat <<'H'
necro-restore.sh — recreate AI-agent tmux sessions from a snapshot.

Usage:
  necro-restore.sh                  use most-recent autosave snapshot
  necro-restore.sh <snapshot.jsonl> use a specific snapshot
  necro-restore.sh --dry-run        print the plan, change nothing
  necro-restore.sh --force-large    resume Claude transcripts over the size limit
  necro-restore.sh --allow-unsafe-cwd

Config:
  NECROMANCER_MAX_CLAUDE_TRANSCRIPT_BYTES or @necromancer_max_claude_transcript_bytes
      Defaults to 52428800 (50 MiB).
  NECROMANCER_UNSAFE_CWD_PATTERNS or @necromancer_unsafe_cwd_patterns
      Space-separated shell globs. Defaults to:
      /private/tmp/claude-* *tmux-debug-build* *crashtest*

Idempotent: reuses existing sessions/windows; resumes only into fresh panes.
H
      exit 0 ;;
    -*) necro_err "Unknown flag: $1"; exit 2 ;;
    *)  SNAPSHOT="$1"; shift ;;
  esac
done

command -v tmux >/dev/null || { necro_err "tmux not installed."; exit 1; }
command -v jq   >/dev/null || { necro_err "jq not installed (brew install jq)."; exit 1; }

stage() { printf '[%d/%d] %s\n' "$1" "$2" "$3"; }

progress_record() {
  local current="$1" total="$2" message="$3"
  local pct=0 width=20 filled empty bar
  [ "$total" -gt 0 ] && pct=$((current * 100 / total))
  if [ "$DRY_RUN" = "0" ] && [ -t 1 ]; then
    filled=$((pct * width / 100))
    empty=$((width - filled))
    bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
    bar="$bar$(printf '%*s' "$empty" '' | tr ' ' '-')"
    printf '[%s] %3d%%  [%d/%d] %s\n' "$bar" "$pct" "$current" "$total" "$message"
  else
    printf '[%d/%d %3d%%] %s\n' "$current" "$total" "$pct" "$message"
  fi
}

format_bytes() {
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN {
    if (b >= 1048576) printf "%.1f MiB", b / 1048576;
    else if (b >= 1024) printf "%.1f KiB", b / 1024;
    else printf "%d B", b;
  }'
}

max_claude_transcript_bytes() {
  local val
  if [ -n "${NECROMANCER_MAX_CLAUDE_TRANSCRIPT_BYTES:-}" ]; then
    val="$NECROMANCER_MAX_CLAUDE_TRANSCRIPT_BYTES"
  else
    val="$(necro_tmux_option @necromancer_max_claude_transcript_bytes "52428800")"
  fi
  case "$val" in
    ''|*[!0-9]*) printf '52428800' ;;
    *) printf '%s' "$val" ;;
  esac
}

unsafe_cwd_patterns() {
  local val
  if [ "${NECROMANCER_UNSAFE_CWD_PATTERNS+x}" = "x" ]; then
    val="$NECROMANCER_UNSAFE_CWD_PATTERNS"
  else
    val="$(necro_tmux_option @necromancer_unsafe_cwd_patterns "")"
    [ -n "$val" ] || val="/private/tmp/claude-* *tmux-debug-build* *crashtest*"
  fi
  [ "$val" = "none" ] && return 0
  printf '%s' "$val"
}

unsafe_cwd_reason() {
  local cwd="$1" pattern patterns
  patterns="$(unsafe_cwd_patterns)"
  for pattern in $patterns; do
    case "$cwd" in
      $pattern) printf 'unsafe cwd matches %s' "$pattern"; return 0 ;;
    esac
  done
  return 1
}

claude_resume_skip_reason() {
  local uuid="$1" cwd="$2" max_bytes="$3" path size
  path="$(necro_agent_transcript_path claude "$uuid" "$cwd")"
  if [ -n "$path" ]; then
    echo "  claude transcript: $path" >&2
  fi
  size="$(necro_agent_transcript_size claude "$uuid" "$cwd")"
  if [ -n "$size" ]; then
    echo "  claude transcript size: $(format_bytes "$size") ($size bytes)" >&2
    if [ "$FORCE_LARGE" = "0" ] && [ "$size" -gt "$max_bytes" ]; then
      printf 'Claude transcript is larger than %s; pass --force-large to resume' "$(format_bytes "$max_bytes")"
      return 0
    fi
  else
    echo "  claude transcript size: unknown or missing" >&2
  fi
  return 1
}

# Resolve snapshot: explicit arg, else newest autosave, else newest of any.
stage 1 5 "resolving snapshot"
if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT="$(/bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null | head -1)"
  [ -z "$SNAPSHOT" ] && SNAPSHOT="$(/bin/ls -t "$SNAP_DIR"/*.jsonl 2>/dev/null | grep -v enriched | head -1)"
fi
[ -f "$SNAPSHOT" ] || { necro_err "No snapshot found (looked in $SNAP_DIR)."; exit 1; }

stage 2 5 "reading snapshot"
total_records="$(grep -cve '^[[:space:]]*$' "$SNAPSHOT" 2>/dev/null || true)"
total_records="${total_records:-0}"
max_claude_bytes="$(max_claude_transcript_bytes)"

necro_hr
necro_say "Necromancer restore"
echo "  Snapshot: $SNAPSHOT"
echo "  Records:  $total_records"
echo "  Dry-run:  $DRY_RUN"
echo "  Max Claude transcript: $(format_bytes "$max_claude_bytes") ($max_claude_bytes bytes)"
echo "  Force large Claude transcripts: $FORCE_LARGE"
echo "  Allow unsafe cwd paths: $ALLOW_UNSAFE_CWD"
echo "  Unsafe cwd patterns: $(unsafe_cwd_patterns || true)"
necro_hr

run() { if [ "$DRY_RUN" = "1" ]; then echo "  DRY: $*"; else "$@"; fi; }

# Idempotency is keyed on a stable per-window marker we set ourselves:
# the window option @necro_id = "<cwd>|<uuid>". Window names auto-rename and
# pane_current_path is unreliable right after creation, so neither is safe to
# match on across runs. The marker is set once when we create/claim a window
# and survives everything.
NECRO_MARK="@necro_id"

# Does a window already carry this marker in this session?
window_marked() {
  local session="$1" mark="$2"
  tmux list-windows -t "=$session" -F "#{$NECRO_MARK}" 2>/dev/null \
    | grep -qxF "$mark"
}

# Window id (@N) of the window carrying this marker ("" if none).
window_id_for_mark() {
  local session="$1" mark="$2"
  tmux list-windows -t "=$session" -F "#{$NECRO_MARK}	#{window_id}" 2>/dev/null \
    | awk -F'\t' -v m="$mark" '$1==m {print $2; exit}'
}

unmarked_window_id_for_record() {
  local session="$1" win_idx="$2" win_name="$3" safe_name="$4" cwd="$5"
  tmux list-windows -t "=$session" -F "#{window_index}	#{window_name}	#{window_id}	#{pane_current_path}	#{$NECRO_MARK}" 2>/dev/null \
    | awk -F'\t' -v idx="$win_idx" -v name="$win_name" -v safe="$safe_name" -v cwd="$cwd" \
        '$5 == "" && $4 == cwd && ($1 == idx || $2 == name || $2 == safe) { print $3; exit }'
}

window_current_command() {
  local target="$1"
  tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null || true
}

ensure_session() {
  local session="$1" cwd="$2" name="$3"
  if tmux has-session -t "=$session" 2>/dev/null; then
    printf '0'  # session pre-existed
    return 0
  fi
  {
    necro_say "creating session '$session' (cwd=$cwd)"
    run tmux new-session -d -s "$session" -c "$cwd" -n "$name" || \
      necro_warn "could not create session '$session'"
  } >&2
  printf '1'  # session freshly created
}

stage 3 5 "validating records"
restored=0; reused=0; resumed=0; skipped=0; resume_skipped=0; invalid=0; i=0

stage 4 5 "restoring windows and resuming agents"

while IFS= read -r line; do
  [ -z "$line" ] && continue
  i=$((i + 1))

  if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
    progress_record "$i" "$total_records" "skipping invalid JSON record"
    invalid=$((invalid + 1))
    skipped=$((skipped + 1))
    continue
  fi

  session=$(jq -r '.session // empty' <<<"$line")
  pane_id=$(jq -r '.pane_id // empty' <<<"$line")
  win_idx=$(jq -r '.window_index // empty' <<<"$line")
  win_name=$(jq -r '.window_name // empty' <<<"$line")
  cwd=$(jq -r '.cwd // empty' <<<"$line")
  agent=$(jq -r '.agent // empty' <<<"$line")
  uuid=$(jq -r '.uuid // empty' <<<"$line")

  if [ -z "$session" ] || [ -z "$cwd" ]; then
    progress_record "$i" "$total_records" "skipping record: missing session or cwd"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$ALLOW_UNSAFE_CWD" = "0" ] && reason="$(unsafe_cwd_reason "$cwd")"; then
    progress_record "$i" "$total_records" "skipping $session/${win_name:-?}: $reason (cwd=$cwd)"
    skipped=$((skipped + 1))
    continue
  fi

  # Sanitize window name: tmux disallows '/' in -t targets; trim noise.
  safe_name="${win_name%%:*}"
  safe_name="$(printf '%s' "$safe_name" | sed -e 's/[[:space:]⚡]*$//' -e 's#/#-#g')"
  [ -z "$safe_name" ] && safe_name="$(basename "$cwd")"

  progress_record "$i" "$total_records" "restoring $session/$safe_name  (agent=${agent:-none} cwd=$cwd)"

  # Per-record stable marker. Falls back to pane_id when there's no uuid.
  mark="${cwd}|${uuid:-$pane_id}"

  session_fresh="$(ensure_session "$session" "$cwd" "$safe_name")"

  # Idempotency: claim matching unmarked windows first (tmux-resurrect creates
  # layout-only shells with no @necro_id), then fall back to existing markers.
  # On a freshly-created session, claim its initial window for this record
  # instead of adding a second.
  claim_id=""
  if [ "$session_fresh" = "0" ]; then
    claim_id="$(unmarked_window_id_for_record "$session" "$win_idx" "$win_name" "$safe_name" "$cwd")"
  fi

  if [ -n "$claim_id" ]; then
    echo "  existing window matches snapshot — claiming marker"
    window_id="$claim_id"
    [ "$DRY_RUN" = "1" ] || tmux set-option -w -t "$window_id" "$NECRO_MARK" "$mark" 2>/dev/null || true
    reused=$((reused + 1))
    cur_cmd="$(window_current_command "$window_id")"
    if necro_is_idle_shell "$cur_cmd"; then
      fresh=1
    else
      echo "  claimed window is busy ($cur_cmd) — not resuming"
      fresh=0
    fi
  elif window_marked "$session" "$mark"; then
    echo "  already restored (marker) — reusing"
    reused=$((reused + 1))
    fresh=0
    window_id="$(window_id_for_mark "$session" "$mark")"
  elif [ "$session_fresh" = "1" ]; then
    # Claim the session's initial window for this record.
    window_id="$(tmux list-windows -t "=$session" -F '#{window_id}' 2>/dev/null | head -1)"
    [ "$DRY_RUN" = "1" ] || tmux set-option -w -t "$window_id" "$NECRO_MARK" "$mark" 2>/dev/null || true
    restored=$((restored + 1))
    fresh=1
  else
    necro_say "  adding window '$safe_name'"
    if [ "$DRY_RUN" = "1" ]; then
      echo "  DRY: tmux new-window -t =$session -c $cwd -n $safe_name (mark=$mark)"
      window_id=""
    else
      window_id="$(tmux new-window -d -t "=$session" -c "$cwd" -n "$safe_name" -P -F '#{window_id}' 2>/dev/null || true)"
      [ -n "$window_id" ] && tmux set-option -w -t "$window_id" "$NECRO_MARK" "$mark" 2>/dev/null || true
    fi
    restored=$((restored + 1))
    fresh=1
  fi

  # Target for send-keys: the window id (stable) we just resolved.
  target="${window_id:-${session}:${safe_name}}"

  # Resume only into a freshly-created window with an agent + id. A reused
  # window already has its agent running (or the user's own work) — don't
  # double-resume, which would violate one-client-per-conversation.
  if [ "$fresh" = "1" ] && [ -n "$agent" ] && [ -n "$uuid" ]; then
    echo "  uuid: $uuid"
    if [ "$agent" = "claude" ] && reason="$(claude_resume_skip_reason "$uuid" "$cwd" "$max_claude_bytes")"; then
      echo "  skip resume: $reason"
      resume_skipped=$((resume_skipped + 1))
      skipped=$((skipped + 1))
      continue
    fi
    resume_cmd="$(necro_agent_resume_cmd "$agent" "$uuid")"
    if [ -n "$resume_cmd" ]; then
      echo "  resume: $resume_cmd"
      run tmux send-keys -t "$target" "$resume_cmd" Enter
      resumed=$((resumed + 1))
    else
      echo "  skip resume: no resume command for agent '$agent'"
      resume_skipped=$((resume_skipped + 1))
    fi
  elif [ "$fresh" = "0" ]; then
    echo "  reused — leaving running agent untouched"
  elif [ -z "$agent" ] || [ -z "$uuid" ]; then
    echo "  skip resume: missing agent or uuid"
    resume_skipped=$((resume_skipped + 1))
  fi
done < "$SNAPSHOT"

stage 5 5 "cleanup"
necro_hr
necro_ok "Done. windows added: $restored, reused: $reused, agents resumed: $resumed, resume skipped: $resume_skipped, records skipped: $skipped, invalid: $invalid"
[ "$DRY_RUN" = "1" ] || tmux list-sessions 2>/dev/null || true
