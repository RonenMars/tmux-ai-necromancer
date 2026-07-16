#!/usr/bin/env bash
# necro-apply.sh — move panes into destination sessions, then resume agents.
#
# Like necro-restore.sh, but operates on LIVE panes recorded in a snapshot:
# it relocates each pane's window into a destination session (from the record's
# dest_session, else a cwd-glob routing rule) and resumes the agent in place.
# Use this to reorganize a sprawling server; use necro-restore.sh to rebuild a
# fresh/empty one.
#
# Usage: necro-apply.sh <snapshot.jsonl> [--dry-run] [--resume-delay N] [--resume-batch-size N] [--resume-message STR]
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

[ $# -ge 1 ] || { necro_err "Usage: $0 <snapshot.jsonl> [--dry-run] [--resume-delay N] [--resume-batch-size N] [--resume-message STR]"; exit 2; }
IN=""; DRY_RUN=0; RESUME_DELAY_OPT=""; RESUME_BATCH_SIZE_OPT=""
RESUME_MESSAGE_OPT_SET=0; RESUME_MESSAGE_OPT=""; RESUME_MESSAGE_DELAY_OPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --resume-delay) RESUME_DELAY_OPT="${2:-}"; shift 2 ;;
    --resume-batch-size) RESUME_BATCH_SIZE_OPT="${2:-}"; shift 2 ;;
    --resume-message) RESUME_MESSAGE_OPT_SET=1; RESUME_MESSAGE_OPT="${2:-}"; shift 2 ;;
    --resume-message-delay) RESUME_MESSAGE_DELAY_OPT="${2:-}"; shift 2 ;;
    -*) necro_err "Unknown flag: $1"; exit 2 ;;
    *)  IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { necro_err "Usage: $0 <snapshot.jsonl> [--dry-run] [--resume-delay N] [--resume-batch-size N] [--resume-message STR]"; exit 2; }
[ -f "$IN" ] || { necro_err "Not found: $IN"; exit 1; }
command -v jq >/dev/null || { necro_err "jq not installed."; exit 1; }

# Routing rules — `GLOB | SESSION | SESSION_ROOT`, first match wins. Override by
# setting dest_session in the snapshot record. Customize for your own projects.
ROUTING_TABLE="$(cat <<'EOF'
*/ai-tools/*|ai-tools|$HOME/Desktop/dev/ai-tools
*/dotfiles*|dotfiles|$HOME/dotfiles
EOF
)"

run() { if [ "$DRY_RUN" = "1" ]; then echo "  DRY: $*"; else "$@"; fi; }

# Pacing between resume launches. Firing every `claude --resume` back-to-back
# spikes CPU/memory (transcript read + initial API call) enough to stall the
# machine on a multi-pane apply. Same knobs as necro-restore.sh.
resume_delay_seconds() {
  local val
  if [ -n "$RESUME_DELAY_OPT" ]; then
    val="$RESUME_DELAY_OPT"
  elif [ -n "${NECROMANCER_RESUME_DELAY:-}" ]; then
    val="$NECROMANCER_RESUME_DELAY"
  else
    val="$(necro_tmux_option @necromancer_resume_delay "5")"
  fi
  case "$val" in
    ''|*[!0-9.]*) printf '5' ;;
    *) printf '%s' "$val" ;;
  esac
}

resume_batch_size() {
  local val
  if [ -n "$RESUME_BATCH_SIZE_OPT" ]; then
    val="$RESUME_BATCH_SIZE_OPT"
  elif [ -n "${NECROMANCER_RESUME_BATCH_SIZE:-}" ]; then
    val="$NECROMANCER_RESUME_BATCH_SIZE"
  else
    val="$(necro_tmux_option @necromancer_resume_batch_size "1")"
  fi
  case "$val" in
    ''|*[!0-9]*|0) printf '1' ;;
    *) printf '%s' "$val" ;;
  esac
}

# Message sent into each pane after a resume. Default 'continue'. Empty string
# is an explicit off-switch at every tier (flag/env/tmux option).
resume_message() {
  if [ "$RESUME_MESSAGE_OPT_SET" = "1" ]; then
    printf '%s' "$RESUME_MESSAGE_OPT"; return
  fi
  if [ -n "${NECROMANCER_RESUME_MESSAGE+x}" ]; then
    printf '%s' "$NECROMANCER_RESUME_MESSAGE"; return
  fi
  local val; val="$(necro_tmux_option @necromancer_resume_message "__unset__")"
  if [ "$val" = "__unset__" ]; then printf 'continue'; else printf '%s' "$val"; fi
}

resume_message_delay() {
  local val
  if [ -n "$RESUME_MESSAGE_DELAY_OPT" ]; then
    val="$RESUME_MESSAGE_DELAY_OPT"
  elif [ -n "${NECROMANCER_RESUME_MESSAGE_DELAY:-}" ]; then
    val="$NECROMANCER_RESUME_MESSAGE_DELAY"
  else
    val="$(necro_tmux_option @necromancer_resume_message_delay "8")"
  fi
  case "$val" in
    ''|*[!0-9.]*) printf '8' ;;
    *) printf '%s' "$val" ;;
  esac
}

RESUME_DELAY="$(resume_delay_seconds)"
RESUME_BATCH="$(resume_batch_size)"
RESUME_BATCH_COUNT=0
RESUME_MESSAGE="$(resume_message)"
RESUME_MESSAGE_DELAY="$(resume_message_delay)"

match_route() {
  local cwd="$1" glob session root
  while IFS='|' read -r glob session root; do
    [ -z "$glob" ] && continue
    # shellcheck disable=SC2254
    case "$cwd" in
      $glob) eval printf '%s' "$session\|$root"; return 0 ;;
    esac
  done <<<"$ROUTING_TABLE"
  return 1
}

ensure_session() {
  local session="$1" root="$2"
  tmux has-session -t "=$session" 2>/dev/null && return 0
  run tmux new-session -d -s "$session" -c "$root" -n scratch || true
}

while IFS= read -r line; do
  [ -z "$line" ] && continue
  pane_id=$(jq -r '.pane_id' <<<"$line")
  session=$(jq -r '.session' <<<"$line")
  win_name=$(jq -r '.window_name' <<<"$line")
  cwd=$(jq -r '.cwd' <<<"$line")
  agent=$(jq -r '.agent // empty' <<<"$line")
  uuid=$(jq -r '.uuid // empty' <<<"$line")
  dest=$(jq -r '.dest_session // empty' <<<"$line")

  echo "[$pane_id] from $session '$win_name' (agent=${agent:-none})"

  window_id="$(tmux list-panes -a -F '#{pane_id} #{window_id}' 2>/dev/null | awk -v p="$pane_id" '$1==p {print $2; exit}')"
  [ -z "$window_id" ] && { echo "  SKIP: pane gone"; continue; }

  if [ -n "$dest" ]; then target="$dest"; root="$cwd"
  elif route="$(match_route "$cwd")"; then target="${route%%|*}"; root="${route#*|}"
  else echo "  no route — leaving in place"; target=""; fi

  if [ -n "$target" ] && [ "$target" != "$session" ]; then
    ensure_session "$target" "$root"
    run tmux move-window -d -s "$window_id" -t "${target}:" || { echo "  WARN: move failed"; continue; }
  fi

  if [ -n "$agent" ] && [ -n "$uuid" ]; then
    cur="$(tmux display-message -p -t "$window_id" '#{pane_current_command}' 2>/dev/null || echo '?')"
    if necro_is_idle_shell "$cur"; then
      resume_cmd="$(necro_agent_resume_cmd "$agent" "$uuid")"
      if [ -n "$resume_cmd" ]; then
        echo "  $resume_cmd"
        run tmux send-keys -t "$window_id" "$resume_cmd" Enter
        # Nudge the freshly-resumed agent to pick up its task. Wait first so the
        # message lands at the prompt, not on the agent's boot screen.
        if [ -n "$RESUME_MESSAGE" ]; then
          [ "$DRY_RUN" = "0" ] && sleep "$RESUME_MESSAGE_DELAY"
          run tmux send-keys -t "$window_id" "$RESUME_MESSAGE" Enter
        fi
        RESUME_BATCH_COUNT=$((RESUME_BATCH_COUNT + 1))
        if [ "$DRY_RUN" = "0" ] && [ "$((RESUME_BATCH_COUNT % RESUME_BATCH))" -eq 0 ]; then
          sleep "$RESUME_DELAY"
        fi
      fi
    else
      echo "  pane busy ($cur) — not resuming"
    fi
  fi
done < "$IN"

echo; necro_ok "Apply complete."
[ "$DRY_RUN" = "1" ] || tmux list-sessions 2>/dev/null || true
