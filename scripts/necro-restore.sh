#!/usr/bin/env bash
# necro-restore.sh — recreate AI-agent tmux sessions from the latest snapshot.
#
# Reads a snapshot .jsonl (default: most-recent autosave) and, for each record
# that has an agent + session id, ensures a tmux session/window exists at the
# right cwd and resumes the agent there.
#
# IDEMPOTENT BY DESIGN — safe to run on an already-populated server:
#   - reuses an existing session instead of erroring on "duplicate session"
#   - claims a pane already carrying its @necro_id marker instead of re-adding it
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
ONLY_SELECTORS=""
MENU=0
RESUME_DELAY_OPT=""
RESUME_BATCH_SIZE_OPT=""
RESUME_MESSAGE_OPT_SET=0
RESUME_MESSAGE_OPT=""
RESUME_MESSAGE_DELAY_OPT=""
RESUME_START_DELAY_OPT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force-large) FORCE_LARGE=1; shift ;;
    --allow-unsafe-cwd) ALLOW_UNSAFE_CWD=1; shift ;;
    --only) ONLY_SELECTORS="${2:-}"; shift 2 ;;
    --menu) MENU=1; shift ;;
    --resume-delay) RESUME_DELAY_OPT="${2:-}"; shift 2 ;;
    --resume-batch-size) RESUME_BATCH_SIZE_OPT="${2:-}"; shift 2 ;;
    --resume-message) RESUME_MESSAGE_OPT_SET=1; RESUME_MESSAGE_OPT="${2:-}"; shift 2 ;;
    --resume-message-delay) RESUME_MESSAGE_DELAY_OPT="${2:-}"; shift 2 ;;
    --resume-start-delay) RESUME_START_DELAY_OPT="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'H'
necro-restore.sh — recreate AI-agent tmux sessions from a snapshot.

Usage:
  necro-restore.sh                  use most-recent autosave snapshot
  necro-restore.sh <snapshot.jsonl> use a specific snapshot
  necro-restore.sh --dry-run        print the plan, change nothing
  necro-restore.sh --force-large    resume Claude transcripts over the size limit
  necro-restore.sh --allow-unsafe-cwd
  necro-restore.sh --only SEL[,SEL...]     restore only the matching records
  necro-restore.sh --menu                  pick the records interactively
  necro-restore.sh --resume-delay N        seconds between resume batches (default 5)
  necro-restore.sh --resume-batch-size N   resumes per batch before pausing (default 1)
  necro-restore.sh --resume-message STR    text sent to each pane after resume (default 'continue', '' disables)
  necro-restore.sh --resume-message-delay N  seconds to wait before that message (default 8)
  necro-restore.sh --resume-start-delay N  seconds to wait after creating a pane before the resume command (default 1)

Selectors (--only):
  Comma-separated. Each dispatches on its shape, and the three forms are
  syntactically disjoint so one flag stays unambiguous:
      %14                                    a pane id
      1ec9e206-5619-418f-8556-72433fb60181   a session uuid
      /path/to/project  or  *tb-mobile*      a cwd (glob allowed)
  A record matching ANY selector is restored; the rest are left alone. A window
  restored only in part does not get its saved layout replayed.

Config:
  NECROMANCER_MAX_CLAUDE_TRANSCRIPT_BYTES or @necromancer_max_claude_transcript_bytes
      Defaults to 52428800 (50 MiB).
  NECROMANCER_UNSAFE_CWD_PATTERNS or @necromancer_unsafe_cwd_patterns
      Space-separated shell globs. Defaults to:
      /private/tmp/claude-* *tmux-debug-build* *crashtest*
  NECROMANCER_RESUME_DELAY or @necromancer_resume_delay
      Seconds to pause after each resume batch (default 5). Restoring many
      sessions at once spikes CPU/memory enough to stall the machine —
      raise this if you still see that on a large restore. --resume-delay
      overrides both.
  NECROMANCER_RESUME_BATCH_SIZE or @necromancer_resume_batch_size
      How many resumes to launch before pausing for the delay (default 1 —
      pause after every single resume). Raise this to let a few launches
      fire back-to-back between pauses. --resume-batch-size overrides both.
  NECROMANCER_RESUME_MESSAGE or @necromancer_resume_message
      Text sent into each pane after its resume so the agent picks up its
      task (default 'continue'). Empty string disables it. --resume-message
      overrides both.
  NECROMANCER_RESUME_MESSAGE_DELAY or @necromancer_resume_message_delay
      Seconds to wait after resuming before sending that message, so it lands
      at the prompt not the boot screen (default 8). --resume-message-delay
      overrides both.
  NECROMANCER_RESUME_START_DELAY or @necromancer_resume_start_delay
      Seconds to wait after creating a fresh pane before sending the resume
      command itself (default 1). A pane spawned by new-window/split-window/
      new-session isn't immediately ready for input — its shell (zsh init,
      plugin managers, etc.) is still starting — and keystrokes sent too
      early are silently dropped rather than queued. Raise this if resumes
      land in an empty pane on a slow shell. --resume-start-delay overrides
      both.

Idempotent: reuses existing sessions/windows; resumes only into fresh panes.
H
      exit 0 ;;
    -*) necro_err "Unknown flag: $1"; exit 2 ;;
    *)  SNAPSHOT="$1"; shift ;;
  esac
done

command -v tmux >/dev/null || { necro_err "tmux not installed."; exit 1; }
command -v jq   >/dev/null || { necro_err "jq not installed (brew install jq)."; exit 1; }

stage() { necro_log_event "restore" "stage" "current=$1" "total=$2" "name=$3"; printf '[%d/%d] %s\n' "$1" "$2" "$3"; }

# --- --only record filter ----------------------------------------------------
# True when the record should be restored. With no --only, everything is.
#
# Selectors dispatch on shape rather than needing a flag each, which works
# because the three forms can't be confused for one another: a pane id starts
# with '%', a cwd starts with '/' or carries a glob, and anything else is a
# uuid. Matching is ANY-of, so `--only %1,*tb-mobile*` means "that pane, plus
# everything under tb-mobile".
record_selected() {
  local pane="$1" uuid="$2" cwd="$3" sel rest="$ONLY_SELECTORS"
  [ -z "$rest" ] && return 0
  while [ -n "$rest" ]; do
    sel="${rest%%,*}"
    case "$rest" in *,*) rest="${rest#*,}" ;; *) rest="" ;; esac
    [ -z "$sel" ] && continue
    case "$sel" in
      %*)       [ "$sel" = "$pane" ] && return 0 ;;
      # Unquoted $sel on purpose — it is matched as a glob against the cwd.
      /*|*'*'*) case "$cwd" in $sel) return 0 ;; esac ;;
      *)        [ "$sel" = "$uuid" ] && return 0 ;;
    esac
  done
  return 1
}

# --- --menu: interactive record picker ---------------------------------------
# Fills ONLY_SELECTORS by hand instead of from the command line. Deliberately
# not a second restore path: it produces the same selector list --only accepts
# and then falls through to the same loop, so there is one filter engine.
# Snapshot BROWSING stays in necro-menu.sh — this picks records within the
# snapshot already resolved.

# Show the resume command and conversation preview for the picked records.
# first_user/last_assistant are populated by necro-context.sh; empty otherwise.
menu_preview() {
  local picked="$1" pid ag uu cwd fu la
  printf '\n'
  jq -r '[.pane_id//"", .agent//"", .uuid//"", .cwd//"", .first_user//"", .last_assistant//""] | @tsv' \
    "$SNAPSHOT" 2>/dev/null |
  while IFS="$(printf '\t')" read -r pid ag uu cwd fu la; do
    case "$picked" in *" $pid "*) ;; *) continue ;; esac
    printf '  %-4s %-7s %s\n' "$pid" "${ag:--}" "$cwd"
    [ -n "$ag" ] && [ -n "$uu" ] && printf '       resume: %s\n' "$(necro_agent_resume_cmd "$ag" "$uu")"
    [ -n "$fu" ] && printf '       first: %.100s\n' "$fu"
    [ -n "$la" ] && printf '       last : %.100s\n' "$la"
  done
}

menu_pick_records() {
  # Verify a real controlling terminal by actually OPENING it (invariant 14).
  # `[ -t 0 ]` tests the wrong fd — necro_init_log pipes stdout through tee —
  # and `[ -r /dev/tty ]` false-passes where there is no controlling terminal,
  # since the permission bits satisfy access(2) even when open(2) would fail.
  # Restore is reachable from run-shell, display-popup, launchd and cron.
  if ! { : </dev/tty; } 2>/dev/null; then
    necro_err "--menu needs a real terminal (not run-shell/popup/cron). Use --only instead."
    exit 2
  fi

  local ids labels n=0 k pid sess widx wname ag uu cwd
  ids=(); labels=()
  while IFS="$(printf '\t')" read -r pid sess widx wname ag uu cwd; do
    [ -z "$pid" ] && continue
    n=$((n + 1))
    ids[$n]="$pid"
    labels[$n]="$(printf '%-4s %-9s %-24.24s %-7s %-8.8s %s' \
      "$pid" "${sess}:${widx}" "${wname:--}" "${ag:--}" "${uu:--}" "$cwd")"
  done <<EOF
$(jq -r '[.pane_id//"", (.session|tostring), (.window_index|tostring),
          .window_name//"", .agent//"", .uuid//"", .cwd//""] | @tsv' \
     "$SNAPSHOT" 2>/dev/null)
EOF

  [ "$n" -gt 0 ] || { necro_err "Snapshot has no usable records."; exit 1; }

  # Selection is a space-delimited string of pane ids, not an associative
  # array: macOS ships /bin/bash 3.2 (invariant 13). Starts with everything
  # selected, so Enter alone behaves like a plain restore.
  local picked=" " reply rebuilt x sel
  k=1; while [ "$k" -le "$n" ]; do picked="$picked${ids[$k]} "; k=$((k + 1)); done

  while :; do
    printf '\n'
    necro_say "Records in $(basename "$SNAPSHOT")"
    k=1; while [ "$k" -le "$n" ]; do
      case "$picked" in
        *" ${ids[$k]} "*) printf '  [x] %2d  %s\n' "$k" "${labels[$k]}" ;;
        *)                printf '  [ ] %2d  %s\n' "$k" "${labels[$k]}" ;;
      esac
      k=$((k + 1))
    done
    printf '\n  <number> toggle  ·  a=all  ·  c=clear  ·  p=preview  ·  Enter=restore  ·  q=abort\n  > '
    # EOF (a closed or vanished tty) must abort, never fall through to
    # restoring — the same failure the snapshot exit-prompt bug had.
    read -r reply </dev/tty || reply="q"
    case "$reply" in
      "")  break ;;
      q|Q) necro_say "Cancelled."; exit 0 ;;
      a|A) picked=" "; k=1; while [ "$k" -le "$n" ]; do picked="$picked${ids[$k]} "; k=$((k + 1)); done ;;
      c|C) picked=" " ;;
      p|P) menu_preview "$picked" ;;
      *[!0-9]*) necro_warn "Not a number: $reply" ;;
      *)
        if [ "$reply" -ge 1 ] && [ "$reply" -le "$n" ]; then
          case "$picked" in
            *" ${ids[$reply]} "*)
              rebuilt=" "
              for x in $picked; do [ "$x" = "${ids[$reply]}" ] || rebuilt="$rebuilt$x "; done
              picked="$rebuilt" ;;
            *) picked="$picked${ids[$reply]} " ;;
          esac
        else
          necro_warn "Out of range: $reply"
        fi ;;
    esac
  done

  sel=""
  k=1; while [ "$k" -le "$n" ]; do
    case "$picked" in *" ${ids[$k]} "*) sel="${sel:+$sel,}${ids[$k]}" ;; esac
    k=$((k + 1))
  done
  [ -n "$sel" ] || { necro_say "Nothing selected — nothing to do."; exit 0; }
  ONLY_SELECTORS="$sel"
}

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

resume_start_delay() {
  local val
  if [ -n "$RESUME_START_DELAY_OPT" ]; then
    val="$RESUME_START_DELAY_OPT"
  elif [ -n "${NECROMANCER_RESUME_START_DELAY:-}" ]; then
    val="$NECROMANCER_RESUME_START_DELAY"
  else
    val="$(necro_tmux_option @necromancer_resume_start_delay "1")"
  fi
  case "$val" in
    ''|*[!0-9.]*) printf '1' ;;
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

# Interactive picker runs before anything is read or touched; it only fills in
# ONLY_SELECTORS, so everything downstream is the plain --only path.
[ "$MENU" = "1" ] && menu_pick_records

stage 2 5 "reading snapshot"
total_records="$(grep -cve '^[[:space:]]*$' "$SNAPSHOT" 2>/dev/null || true)"
total_records="${total_records:-0}"
max_claude_bytes="$(max_claude_transcript_bytes)"
resume_delay="$(resume_delay_seconds)"
resume_batch="$(resume_batch_size)"
resume_batch_count=0
resume_message="$(resume_message)"
resume_message_delay="$(resume_message_delay)"
resume_start_delay="$(resume_start_delay)"

necro_hr
necro_say "Necromancer restore"
echo "  Snapshot: $SNAPSHOT"
echo "  Records:  $total_records"
echo "  Dry-run:  $DRY_RUN"
echo "  Max Claude transcript: $(format_bytes "$max_claude_bytes") ($max_claude_bytes bytes)"
echo "  Resume pacing: ${resume_delay}s pause every ${resume_batch} resume(s)"
echo "  Pane readiness wait before resume: ${resume_start_delay}s"
if [ -n "$resume_message" ]; then
  echo "  Post-resume message: '$resume_message' after ${resume_message_delay}s"
else
  echo "  Post-resume message: (none)"
fi
[ -n "$ONLY_SELECTORS" ] && echo "  Only: $ONLY_SELECTORS"
echo "  Force large Claude transcripts: $FORCE_LARGE"
echo "  Allow unsafe cwd paths: $ALLOW_UNSAFE_CWD"
echo "  Unsafe cwd patterns: $(unsafe_cwd_patterns || true)"
necro_hr

run() { necro_log_event "restore" "command" "dry_run=$DRY_RUN" "command=$*"; if [ "$DRY_RUN" = "1" ]; then echo "  DRY: $*"; else "$@"; fi; }

# Idempotency is keyed on a stable per-PANE marker we set ourselves: the pane
# option @necro_id = "<cwd>|<uuid>". Marking panes (not windows) lets several
# records that shared one window restore as splits in that window while each
# stays independently idempotent. Window names auto-rename and pane_current_path
# is unreliable right after creation, so neither is safe to match on across
# runs. The marker is set once when we create/claim a pane and survives.
NECRO_MARK="@necro_id"

# Does a pane already carry this marker in this session?
window_marked() {
  local session="$1" mark="$2"
  tmux list-panes -s -t "=$session:" -F "#{$NECRO_MARK}" 2>/dev/null \
    | grep -qxF "$mark"
}

# Pane id (%N) of the pane carrying this marker ("" if none).
window_id_for_mark() {
  local session="$1" mark="$2"
  tmux list-panes -s -t "=$session:" -F "#{$NECRO_MARK}	#{pane_id}" 2>/dev/null \
    | awk -F'\t' -v m="$mark" '$1==m {print $2; exit}'
}

unmarked_window_id_for_record() {
  local session="$1" win_idx="$2" win_name="$3" safe_name="$4" cwd="$5"
  tmux list-panes -s -t "=$session:" \
      -F "#{window_index}	#{window_name}	#{pane_id}	#{pane_current_path}	#{$NECRO_MARK}" 2>/dev/null \
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
restored=0; reused=0; resumed=0; skipped=0; resume_skipped=0; invalid=0; filtered=0; i=0
# Window created/claimed for each (session, window_index) THIS run. Later records
# in the same group split into that window instead of adding a new one.
#
# Backed by dynamically-named scalars, not `declare -A`: macOS ships /bin/bash
# 3.2, where associative arrays don't exist. `declare -A` there errors, the
# group key then arithmetic-evaluates as an indexed subscript, and `set -u`
# aborts the loop on the first record — a silent 0-session restore.
#
# Keys are arbitrary strings ("session|win_idx"); each is hex-encoded into the
# var-name suffix so distinct keys can never collide (a lossy collapse would
# cross-wire sessions differing only in punctuation, e.g. my.app vs my-app —
# the same class of bug as invariant 11). Seen keys are recorded newline-
# delimited in GROUP_KEYS so post-loop iteration survives keys with spaces.
GROUP_KEYS=""  # newline-separated group keys seen this run
group_var() { printf 'GRP_%s_%s' "$2" "$(printf '%s' "$1" | od -An -tx1 | tr -d ' \n')"; }
group_get() { eval "printf '%s' \"\${$(group_var "$1" "$2"):-${3:-}}\""; }  # $3 = default
group_set() {
  case "
$GROUP_KEYS" in *"
$1"*) ;; *) GROUP_KEYS="$GROUP_KEYS
$1" ;; esac
  eval "$(group_var "$1" "$2")=\$3"
}

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
  layout=$(jq -r '.window_layout // empty' <<<"$line")
  # 0/1 flags; absent in pre-flag snapshots, so default 0 (no-op on replay).
  zoomed=$(jq -r '.zoomed // 0' <<<"$line")
  pactive=$(jq -r '.pane_active // 0' <<<"$line")
  wactive=$(jq -r '.window_active // 0' <<<"$line")

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

  # Group bookkeeping runs BEFORE the --only filter: the layout replay has to
  # know how many panes the window had in the snapshot, not just how many were
  # selected, so a partially-restored window can be told apart from a whole one.
  group="${session}|${win_idx}"
  group_set "$group" full_count "$(( $(group_get "$group" full_count 0) + 1 ))"

  if ! record_selected "$pane_id" "$uuid" "$cwd"; then
    progress_record "$i" "$total_records" "filtered out $session/${win_name:-?} (--only)"
    filtered=$((filtered + 1))
    continue
  fi

  # Sanitize window name: tmux disallows '/' in -t targets; trim noise.
  safe_name="${win_name%%:*}"
  safe_name="$(printf '%s' "$safe_name" | sed -e 's/[[:space:]⚡]*$//' -e 's#/#-#g')"
  [ -z "$safe_name" ] && safe_name="$(basename "$cwd")"

  progress_record "$i" "$total_records" "restoring $session/$safe_name  (agent=${agent:-none} cwd=$cwd)"

  # Conversation preview, dry-run only — that is where the question is "is this
  # the session I meant?", and it is what necro-menu.sh shows before asking you
  # to confirm. Both fields are filled by necro-context.sh; empty otherwise, in
  # which case nothing is printed rather than a blank label.
  if [ "$DRY_RUN" = "1" ]; then
    first_user=$(jq -r '.first_user // empty' <<<"$line")
    last_assistant=$(jq -r '.last_assistant // empty' <<<"$line")
    [ -n "$first_user" ]      && printf '  first: %.100s\n' "$first_user"
    [ -n "$last_assistant" ]  && printf '  last : %.100s\n' "$last_assistant"
  fi

  # Per-record stable marker. Falls back to pane_id when there's no uuid.
  mark="${cwd}|${uuid:-$pane_id}"

  # Track saved pane count + layout per group for the post-loop layout replay.
  group_set "$group" count "$(( $(group_get "$group" count 0) + 1 ))"
  [ -n "$layout" ] && [ -z "$(group_get "$group" layout)" ] && group_set "$group" layout "$layout"

  session_fresh="$(ensure_session "$session" "$cwd" "$safe_name")"

  # Idempotency: claim matching unmarked panes first (tmux-resurrect creates
  # layout-only shells with no @necro_id), then fall back to existing markers.
  # On a freshly-created session, claim its initial pane for this record
  # instead of adding a second window.
  claim_id=""
  if [ "$session_fresh" = "0" ]; then
    claim_id="$(unmarked_window_id_for_record "$session" "$win_idx" "$win_name" "$safe_name" "$cwd")"
  fi

  if [ -n "$claim_id" ]; then
    echo "  existing pane matches snapshot — claiming marker"
    pane_target="$claim_id"
    [ "$DRY_RUN" = "1" ] || tmux set-option -p -t "$pane_target" "$NECRO_MARK" "$mark" 2>/dev/null || true
    # Register the claimed pane's window for this group, exactly as the
    # create paths do. Without this, a later record in the same
    # (session, window_index) finds no group `win` entry and falls through
    # to `new-window` — flattening a multi-pane window into separate windows
    # (the invariant-2 regression) and skipping the layout replay, which
    # requires the group `win` entry to be set.
    if [ "$DRY_RUN" = "0" ] && [ -z "$(group_get "$group" win)" ]; then
      claimed_win="$(tmux display-message -p -t "$pane_target" '#{window_id}' 2>/dev/null || true)"
      [ -n "$claimed_win" ] && group_set "$group" win "$claimed_win"
    fi
    reused=$((reused + 1))
    cur_cmd="$(window_current_command "$pane_target")"
    if necro_is_idle_shell "$cur_cmd"; then
      fresh=1
    else
      echo "  claimed pane is busy ($cur_cmd) — not resuming"
      fresh=0
    fi
  elif window_marked "$session" "$mark"; then
    echo "  already restored (marker) — reusing"
    reused=$((reused + 1))
    fresh=0
    pane_target="$(window_id_for_mark "$session" "$mark")"
  elif [ -n "$(group_get "$group" win)" ]; then
    # A window for this (session, window_index) was already created this run —
    # this record was another pane in that window, so split into it.
    #
    # Split from the group's PREVIOUS pane, not the window. `split-window -t
    # <window>` splits that window's active pane, and `-d` stops the new pane
    # becoming active, so every split would hit the same pane and insert after
    # it — reversing records 2..N. The layout replay assigns geometry by pane
    # index, so that reversal lands each agent in the wrong pane.
    split_from="$(group_get "$group" lastpane "$(group_get "$group" win)")"
    necro_say "  splitting into window for '$safe_name'"
    if [ "$DRY_RUN" = "1" ]; then
      echo "  DRY: tmux split-window -t $split_from -c $cwd (mark=$mark)"
      pane_target=""
    else
      pane_target="$(tmux split-window -d -t "$split_from" -c "$cwd" -P -F '#{pane_id}' 2>/dev/null || true)"
      [ -n "$pane_target" ] && tmux set-option -p -t "$pane_target" "$NECRO_MARK" "$mark" 2>/dev/null || true
    fi
    restored=$((restored + 1))
    fresh=1
  elif [ "$session_fresh" = "1" ]; then
    # Claim the session's initial window's pane for this record.
    if [ "$DRY_RUN" = "1" ]; then
      pane_target=""; group_set "$group" win "=$session:dry"
    else
      pane_target="$(tmux list-panes -t "=$session:" -F '#{pane_id}' 2>/dev/null | head -1)"
      tmux set-option -p -t "$pane_target" "$NECRO_MARK" "$mark" 2>/dev/null || true
      group_set "$group" win "$(tmux list-windows -t "=$session" -F '#{window_id}' 2>/dev/null | head -1)"
    fi
    restored=$((restored + 1))
    fresh=1
  else
    necro_say "  adding window '$safe_name'"
    if [ "$DRY_RUN" = "1" ]; then
      echo "  DRY: tmux new-window -t =$session: -c $cwd -n $safe_name (mark=$mark)"
      pane_target=""; group_set "$group" win "=$session:dry"
    else
      window_id="$(tmux new-window -d -t "=$session:" -c "$cwd" -n "$safe_name" -P -F '#{window_id}' 2>/dev/null || true)"
      if [ -n "$window_id" ]; then
        group_set "$group" win "$window_id"
        pane_target="$(tmux list-panes -t "$window_id" -F '#{pane_id}' 2>/dev/null | head -1)"
        tmux set-option -p -t "$pane_target" "$NECRO_MARK" "$mark" 2>/dev/null || true
      else
        pane_target=""
      fi
    fi
    restored=$((restored + 1))
    fresh=1
  fi

  # Remember this record's pane so the group's next split lands after it,
  # preserving snapshot record order (see the split path above).
  [ -n "$pane_target" ] && group_set "$group" lastpane "$pane_target"

  # Track active-pane / zoom / active-window flags for the post-loop replay.
  # apane only lands for panes resolved this run; the marker-reuse path never
  # sets the group's `win`, so its flags are ignored downstream (same rule as
  # the layout replay — a live window's focus/zoom is the user's, not ours).
  [ "$pactive" = "1" ] && [ -n "$pane_target" ] && group_set "$group" apane "$pane_target"
  [ "$zoomed" = "1" ] && group_set "$group" zoom 1
  [ "$wactive" = "1" ] && group_set "$group" wactive 1

  # Target for send-keys: the pane id (stable) we just resolved.
  target="${pane_target:-${session}:${safe_name}}"

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
      # A pane just created by new-window/split-window/new-session isn't
      # immediately ready for input — its shell is still starting — and
      # keystrokes sent too early are dropped, not queued, leaving the pane
      # empty with the agent never resumed. Give it a beat first.
      [ "$DRY_RUN" = "0" ] && sleep "$resume_start_delay"
      run tmux send-keys -t "$target" "$resume_cmd" Enter
      # Nudge the freshly-resumed agent to pick up its task. Wait first so the
      # message lands at the prompt, not on the agent's boot screen.
      if [ -n "$resume_message" ]; then
        [ "$DRY_RUN" = "0" ] && sleep "$resume_message_delay"
        run tmux send-keys -t "$target" "$resume_message" Enter
      fi
      resumed=$((resumed + 1))
      resume_batch_count=$((resume_batch_count + 1))
      # Pace launches in batches — each resume reads a transcript + hits the
      # API for initial context; firing them all back-to-back spikes
      # CPU/memory enough to stall the machine on a multi-session restore.
      # Pause only every Nth resume (resume_batch), not after every single one.
      if [ "$DRY_RUN" = "0" ] && [ "$((resume_batch_count % resume_batch))" -eq 0 ]; then
        sleep "$resume_delay"
      fi
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

# Replay saved pane layouts onto windows this run created. Only when the live
# pane count matches the saved count — never stomp a window whose shape changed.
while IFS= read -r group; do
  [ -z "$group" ] && continue
  layout="$(group_get "$group" layout)"
  [ -z "$layout" ] && continue
  win="$(group_get "$group" win)"
  [ -z "$win" ] && continue
  case "$win" in *:dry) continue ;; esac
  saved="$(group_get "$group" count 0)"
  full="$(group_get "$group" full_count 0)"
  # A window restored only in part must not get its saved layout replayed: that
  # string describes the WHOLE window, so applying it to a subset would either
  # fail outright or squeeze the survivors into cells meant for panes that
  # aren't there. The live-count guard below can't catch this on its own —
  # restore 1 of 2 panes and live == saved == 1 looks like a perfect match.
  if [ "$full" != "$saved" ]; then
    echo "  layout skipped for $group: partial selection ($saved of $full panes)"
    continue
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "  DRY: select-layout -t $win $layout"
    continue
  fi
  live="$(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | grep -c . || true)"
  if [ "$live" = "$saved" ]; then
    tmux select-layout -t "$win" "$layout" 2>/dev/null || true
  else
    echo "  layout skipped for $group: pane count $live != $saved"
  fi
done <<EOF
$GROUP_KEYS
EOF

# Re-apply active pane, zoom, and active window for windows this run
# created/claimed. Runs AFTER the layout replay: select-layout unzooms a
# window, so zoom must be restored last. #{window_layout} stores the saved
# (unzoomed) layout even while zoomed, so the two never conflict. Zoom is
# only re-applied when the active pane's record made it through the loop —
# with no known target pane, zooming would enlarge an arbitrary one.
while IFS= read -r group; do
  [ -z "$group" ] && continue
  win="$(group_get "$group" win)"
  [ -z "$win" ] && continue
  case "$win" in *:dry) continue ;; esac
  apane="$(group_get "$group" apane)"
  if [ -n "$apane" ]; then
    tmux select-pane -t "$apane" 2>/dev/null || true
    if [ "$(group_get "$group" zoom)" = "1" ]; then
      tmux resize-pane -Z -t "$apane" 2>/dev/null || true
    fi
  fi
  if [ "$(group_get "$group" wactive)" = "1" ]; then
    tmux select-window -t "$win" 2>/dev/null || true
  fi
done <<EOF
$GROUP_KEYS
EOF

stage 5 5 "cleanup"
necro_hr
necro_ok "Done. windows added: $restored, reused: $reused, agents resumed: $resumed, resume skipped: $resume_skipped, records skipped: $skipped, filtered out: $filtered, invalid: $invalid"
necro_log_event "restore" "complete" "restored=$restored" "reused=$reused" "resumed=$resumed" "skipped=$skipped" "filtered=$filtered"
[ "$DRY_RUN" = "1" ] || tmux list-sessions 2>/dev/null || true
