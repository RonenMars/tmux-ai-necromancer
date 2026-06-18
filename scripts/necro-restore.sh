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
# shellcheck source=../lib/agents.sh
. "$SELF_DIR/../lib/agents.sh"
necro_load_agents

SNAP_DIR="$(necro_snapshot_dir)"
SNAPSHOT=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      cat <<'H'
necro-restore.sh — recreate AI-agent tmux sessions from a snapshot.

Usage:
  necro-restore.sh                  use most-recent autosave snapshot
  necro-restore.sh <snapshot.jsonl> use a specific snapshot
  necro-restore.sh --dry-run        print the plan, change nothing

Idempotent: reuses existing sessions/windows; resumes only into fresh panes.
H
      exit 0 ;;
    -*) necro_err "Unknown flag: $1"; exit 2 ;;
    *)  SNAPSHOT="$1"; shift ;;
  esac
done

command -v tmux >/dev/null || { necro_err "tmux not installed."; exit 1; }
command -v jq   >/dev/null || { necro_err "jq not installed (brew install jq)."; exit 1; }

# Resolve snapshot: explicit arg, else newest autosave, else newest of any.
if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT="$(/bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null | head -1)"
  [ -z "$SNAPSHOT" ] && SNAPSHOT="$(/bin/ls -t "$SNAP_DIR"/*.jsonl 2>/dev/null | grep -v enriched | head -1)"
fi
[ -f "$SNAPSHOT" ] || { necro_err "No snapshot found (looked in $SNAP_DIR)."; exit 1; }

necro_hr
necro_say "Necromancer restore"
echo "  Snapshot: $SNAPSHOT"
echo "  Records:  $(wc -l < "$SNAPSHOT" | tr -d ' ')"
echo "  Dry-run:  $DRY_RUN"
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

ensure_session() {
  local session="$1" cwd="$2" name="$3"
  if tmux has-session -t "=$session" 2>/dev/null; then
    printf '0'  # session pre-existed
    return 0
  fi
  necro_say "creating session '$session' (cwd=$cwd)"
  run tmux new-session -d -s "$session" -c "$cwd" -n "$name" || \
    necro_warn "could not create session '$session'"
  printf '1'  # session freshly created
}

restored=0; skipped=0; resumed=0

while IFS= read -r line; do
  [ -z "$line" ] && continue

  session=$(jq -r '.session // empty' <<<"$line")
  win_name=$(jq -r '.window_name // empty' <<<"$line")
  cwd=$(jq -r '.cwd // empty' <<<"$line")
  agent=$(jq -r '.agent // empty' <<<"$line")
  uuid=$(jq -r '.uuid // empty' <<<"$line")

  # Sanitize window name: tmux disallows '/' in -t targets; trim noise.
  safe_name="${win_name%%:*}"
  safe_name="$(printf '%s' "$safe_name" | sed -e 's/[[:space:]⚡]*$//' -e 's#/#-#g')"
  [ -z "$safe_name" ] && safe_name="$(basename "$cwd")"

  echo "[$session] $safe_name  (agent=${agent:-none} cwd=$cwd)"

  # Per-record stable marker. Falls back to cwd alone when there's no uuid.
  mark="${cwd}|${uuid}"

  session_fresh="$(ensure_session "$session" "$cwd" "$safe_name")"

  # Idempotency: if a window already carries this marker, reuse it. Otherwise
  # add one. On a freshly-created session, claim its initial window for the
  # first record instead of adding a second.
  if window_marked "$session" "$mark"; then
    echo "  already restored (marker) — reusing"
    skipped=$((skipped + 1))
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
    resume_cmd="$(necro_agent_resume_cmd "$agent" "$uuid")"
    if [ -n "$resume_cmd" ]; then
      echo "  resume: $resume_cmd"
      run tmux send-keys -t "$target" "$resume_cmd" Enter
      resumed=$((resumed + 1))
    fi
  elif [ "$fresh" = "0" ]; then
    echo "  reused — leaving running agent untouched"
  fi
done < "$SNAPSHOT"

necro_hr
necro_ok "Done. windows added: $restored, reused: $skipped, agents resumed: $resumed"
[ "$DRY_RUN" = "1" ] || tmux list-sessions 2>/dev/null || true
