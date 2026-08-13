#!/usr/bin/env bash
# necro-snapshot.sh — capture every tmux pane's AI-agent session to a snapshot.
#
# NOTE: intentionally NOT using `set -e`/pipefail. The loop has pipelines
# (grep | tail | grep) that legitimately exit non-zero on no-match. With
# pipefail the first no-match silently kills the loop. Each fallible call is
# guarded with `|| true` instead.
set -uo pipefail

# --- Load libs (path-agnostic) ----------------------------------------------
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

# --- Flags ------------------------------------------------------------------
# --idle-only     : never send exit keys to a live agent; capture via fallback only.
#                   (Used by autosave — zero pane disruption.) DEFAULT.
# --interactive   : prompt per live agent before sending exit keys. Requires a tty.
# --yes/-y        : auto-answer 'y' to every per-agent exit prompt. Requires a tty.
# --rate-limited  : idle-only capture of panes whose scrollback shows a
#                   session/usage-limit banner (Claude/Codex). Writes
#                   *.rate-limited.jsonl and stamps @necro_limit_saved on saves.
# --auto          : with --rate-limited only; skip panes already stamped
#                   @necro_limit_saved=1, clear the stamp when the banner is gone,
#                   and write no file when nothing new is found. Used by the
#                   watcher so a stuck limit doesn't re-snapshot every tick.
IDLE_ONLY=1
INTERACTIVE=0
ASSUME_YES=0
RATE_LIMITED=0
AUTO_LIMIT=0
SAW_IDLE=0
SAW_MODE_FLAG=0
for arg in "$@"; do
  case "$arg" in
    --idle-only)     IDLE_ONLY=1; SAW_IDLE=1; SAW_MODE_FLAG=1 ;;
    --interactive)   INTERACTIVE=1; IDLE_ONLY=0; SAW_MODE_FLAG=1 ;;
    --yes|-y)        ASSUME_YES=1; IDLE_ONLY=0; SAW_MODE_FLAG=1 ;;
    --rate-limited)  RATE_LIMITED=1; IDLE_ONLY=1; SAW_MODE_FLAG=1 ;;
    --auto)          AUTO_LIMIT=1 ;;
    --help|-h)
      cat <<'H'
necro-snapshot.sh — capture tmux AI-agent sessions to a JSONL snapshot.

Usage:
  necro-snapshot.sh                 idle-only (default): record without disturbing any live agent
  necro-snapshot.sh --idle-only     same as bare invocation, explicit
  necro-snapshot.sh --interactive   prompt per live agent before exiting it (needs a real tty)
  necro-snapshot.sh --yes           auto-exit every live agent and capture (needs a real tty)
  necro-snapshot.sh --rate-limited  idle-only capture of panes showing a rate/session limit
  necro-snapshot.sh --rate-limited --auto
                                    same, but skip panes already saved for this limit event
                                    (watcher auto-save); write nothing if none are new

Exit-capture (--interactive / --yes) requires a real controlling terminal.
Without one, it is refused and downgraded to --idle-only automatically.

Output: <snapshot-dir>/<timestamp>.jsonl
        (or .idle-only.jsonl / .rate-limited.jsonl)
H
      exit 0 ;;
    *) necro_err "Unknown flag: $arg"; exit 2 ;;
  esac
done

modes_set=0
(( SAW_IDLE )) && modes_set=$((modes_set + 1))
(( INTERACTIVE )) && modes_set=$((modes_set + 1))
(( ASSUME_YES )) && modes_set=$((modes_set + 1))
(( RATE_LIMITED )) && modes_set=$((modes_set + 1))
if (( modes_set > 1 )); then
  necro_err "--idle-only, --interactive, --yes and --rate-limited are mutually exclusive."
  exit 2
fi
if [ "$AUTO_LIMIT" = "1" ] && [ "$RATE_LIMITED" != "1" ]; then
  necro_err "--auto requires --rate-limited."
  exit 2
fi

# Exit-capture needs a real controlling terminal. NOTE: [ -r /dev/tty ] is NOT
# sufficient — /dev/tty is 0666, so access(2) passes in cron/launchd/scripted
# contexts where open(2) fails ENXIO. Attempt the actual open.
if [ "$IDLE_ONLY" != "1" ] && ! { : </dev/tty; } 2>/dev/null; then
  necro_warn "No controlling terminal — refusing exit-capture; downgrading to --idle-only."
  necro_warn "No keys will be sent to any pane."
  tmux display-message "necromancer: refused exit-capture (no tty) — idle-only snapshot taken" 2>/dev/null || true
  IDLE_ONLY=1; INTERACTIVE=0; ASSUME_YES=0
fi

SNAP_DIR="$(necro_snapshot_dir)"
mkdir -p "$SNAP_DIR"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
suffix=""
if [ "$RATE_LIMITED" = "1" ]; then
  suffix=".rate-limited"
elif [ "$IDLE_ONLY" = "1" ]; then
  suffix=".idle-only"
fi
OUT="$SNAP_DIR/${TS}${suffix}.jsonl"
# Did $OUT already exist before this run? TS has one-second resolution, so a
# save from the same second resolves to the very same path. The rate-limited
# cleanup at the end of this script deletes $OUT when it saved nothing — and
# without this flag it would delete that earlier save instead of its own empty
# file. The watcher runs --rate-limited --auto on a timer, so the collision is
# reachable in normal use, not just in tests.
OUT_PRE_EXISTING=0
[ -e "$OUT" ] && OUT_PRE_EXISTING=1
necro_log_event "snapshot" "start" "idle_only=$IDLE_ONLY" "assume_yes=$ASSUME_YES" "rate_limited=$RATE_LIMITED" "auto_limit=$AUTO_LIMIT" "output=$OUT"
RATE_LIMITED_SAVED=0

# --- Record emitter ---------------------------------------------------------
# uuid_source: "scrollback" | "latest-jsonl" | "" (none)
emit_record() {
  local pane_id="$1" session="$2" window_index="$3" window_name="$4" \
        cwd="$5" prev_cmd="$6" agent="$7" uuid="$8" uuid_source="${9:-}" \
        window_layout="${10:-}" zoomed="${11:-0}" pane_active="${12:-0}" \
        window_active="${13:-0}"
  # Flags are 0/1 straight from tmux; anything else (old callers, empty read
  # fields) collapses to 0 so the JSON stays valid.
  case "$zoomed" in 1) ;; *) zoomed=0 ;; esac
  case "$pane_active" in 1) ;; *) pane_active=0 ;; esac
  case "$window_active" in 1) ;; *) window_active=0 ;; esac
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"pane_id":%s,"session":%s,"window_index":%d,"window_name":%s,"cwd":%s,"prev_cmd":%s,"agent":%s,"uuid":%s,"uuid_source":%s,"window_layout":%s,"zoomed":%s,"pane_active":%s,"window_active":%s,"captured_at":%s,"first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' \
    "$(necro_json_escape "$pane_id")" \
    "$(necro_json_escape "$session")" \
    "$window_index" \
    "$(necro_json_escape "$window_name")" \
    "$(necro_json_escape "$cwd")" \
    "$(necro_json_escape "$prev_cmd")" \
    "$(necro_json_escape "$agent")" \
    "$(necro_json_escape "$uuid")" \
    "$(necro_json_escape "$uuid_source")" \
    "$(necro_json_escape "$window_layout")" \
    "$zoomed" \
    "$pane_active" \
    "$window_active" \
    "$(necro_json_escape "$now")" \
    >> "$OUT"
  necro_log_event "snapshot" "record" "pane=$pane_id" "agent=${agent:-none}" "uuid_source=${uuid_source:-none}"
}

# Wait for a pane to drop back to an idle shell. Echoes the new command.
wait_for_shell() {
  local pane="$1" timeout="${2:-15}" elapsed=0 cmd
  while [ $elapsed -lt $timeout ]; do
    cmd="$(tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || echo "?")"
    if necro_is_idle_shell "$cmd"; then printf '%s' "$cmd"; return 0; fi
    sleep 1; elapsed=$((elapsed + 1))
  done
  printf '%s' "$cmd"; return 1
}

# Resolve a session id for a pane via the filesystem fallback.
#
# Always pop, never "latest": pop hands out each id at most once per run, so
# two agents sharing a cwd get different UUIDs. `latest` returns the same
# newest id to every caller, so a second same-cwd pane would be recorded
# pointing at the first pane's session — and restore would then resume one
# conversation twice while losing the other entirely.
#
# The cursor dir is per-run here (mktemp'd in Main), so the first caller for a
# cwd still gets the newest id, exactly as `latest` did.
resolve_fallback_id() {
  local agent="$1" cwd="$2"
  necro_agent_pop_session_id "$agent" "$cwd" 2>/dev/null || true
}

# --- Main -------------------------------------------------------------------
# Temp dir for per-cwd UUID cursors (file-based so they survive subshells).
NECRO_CURSOR_DIR="$(mktemp -d)"
trap 'rm -rf "$NECRO_CURSOR_DIR"' EXIT
export NECRO_CURSOR_DIR

echo "Snapshot will be written to: $OUT"
(( SAW_MODE_FLAG == 0 )) && echo "No mode flag given — defaulting to --idle-only. Pass --interactive to prompt per pane for exit-capture."
[ "$RATE_LIMITED" = "1" ] && echo "Mode: --rate-limited — only panes showing a session/usage-limit banner."
echo

snapshot=$(tmux list-panes -a -F \
  '#{pane_id}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_path}	#{pane_current_command}	#{window_layout}	#{window_zoomed_flag}	#{pane_active}	#{window_active}')
total=$(printf '%s\n' "$snapshot" | wc -l | tr -d ' ')
i=0

while IFS=$'\t' read -r pane_id session win_idx win_name cwd cmd layout zoomed pactive wactive; do
  [ -z "$pane_id" ] && continue
  i=$((i + 1))
  printf '\n[%d/%d] %s  %s:%s  %s  (cmd=%s)\n' \
    "$i" "$total" "$pane_id" "$session" "$win_idx" "$win_name" "$cmd"

  agent="$(necro_agent_for_cmd "$cmd")"

  # --rate-limited: only live agent panes whose scrollback shows a limit
  # banner. Idle shells / non-agents are skipped (a limited Claude/Codex is
  # still the foreground command — the banner sits above an empty prompt).
  if [ "$RATE_LIMITED" = "1" ]; then
    if [ -z "$agent" ]; then
      echo "  skip — not a live AI agent"
      continue
    fi
    already="$(tmux show-option -pqv -t "$pane_id" @necro_limit_saved 2>/dev/null || true)"
    if necro_agent_hit_limit "$agent" "$pane_id"; then
      if [ "$AUTO_LIMIT" = "1" ] && [ "$already" = "1" ]; then
        echo "  rate-limited ($agent) — already saved this limit event, skip"
        continue
      fi
      fb="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
      fb_source="pane-option"
      if [ -z "$fb" ]; then
        fb="$(resolve_fallback_id "$agent" "$cwd")"
        fb_source="latest-jsonl"
      fi
      if [ -n "$fb" ]; then
        echo "  rate-limited ($agent) — ${fb_source}: $fb"
        emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$fb" "$fb_source" "$layout" "$zoomed" "$pactive" "$wactive"
      else
        echo "  rate-limited ($agent) — no session id, recording without id"
        emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "" "" "$layout" "$zoomed" "$pactive" "$wactive"
      fi
      tmux set-option -p -t "$pane_id" @necro_limit_saved "1" 2>/dev/null || true
      RATE_LIMITED_SAVED=1
    else
      if [ "$AUTO_LIMIT" = "1" ] && [ "$already" = "1" ]; then
        tmux set-option -pu -t "$pane_id" @necro_limit_saved 2>/dev/null || true
        echo "  limit banner gone ($agent) — cleared @necro_limit_saved"
      else
        echo "  skip — $agent not showing a limit banner"
      fi
    fi
    continue
  fi

  # Idle shell — only trust pane-local watcher state. A cwd-only latest-jsonl
  # lookup can attach the same stale UUID to every shell in that directory.
  if necro_is_idle_shell "$cmd"; then
    found_uuid="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
    found_agent="$(tmux show-option -pqv -t "$pane_id" @necro_agent 2>/dev/null || true)"
    if [ -n "$found_uuid" ] && [ -n "$found_agent" ]; then
      echo "  idle shell — pane-option id ($found_agent): $found_uuid"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$found_agent" "$found_uuid" "pane-option" "$layout" "$zoomed" "$pactive" "$wactive"
    else
      echo "  idle shell — no session found, recording without id"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "" "" "" "$layout" "$zoomed" "$pactive" "$wactive"
    fi
    continue
  fi

  # Not a known agent (node, vim, etc.) — record location only.
  if [ -z "$agent" ]; then
    echo "  not an AI agent (cmd=$cmd) — recording without id"
    emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "" "" "" "$layout" "$zoomed" "$pactive" "$wactive"
    continue
  fi

  # Live agent + --idle-only: read watcher-pinned UUID first, then cursor pop.
  if [ "$IDLE_ONLY" = "1" ]; then
    fb="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
    fb_source="pane-option"
    if [ -z "$fb" ]; then
      fb="$(resolve_fallback_id "$agent" "$cwd")"
      fb_source="latest-jsonl"
    fi
    if [ -n "$fb" ]; then
      echo "  --idle-only ($agent) — ${fb_source}: $fb"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$fb" "$fb_source" "$layout" "$zoomed" "$pactive" "$wactive"
    else
      echo "  --idle-only ($agent) — no session found, recording without id"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "" "" "$layout" "$zoomed" "$pactive" "$wactive"
    fi
    continue
  fi

  # Live agent, interactive capture: show pane, confirm, send exit keys.
  tmux switch-client -t "$pane_id" 2>/dev/null \
    || tmux select-window -t "$pane_id" 2>/dev/null || true
  echo "  Switched view to $pane_id. Make sure $agent is idle (not mid-response)."
  if (( ASSUME_YES )); then
    echo "  --yes: sending exit keys to $agent"; ans="y"
  else
    printf "  Exit this %s? [Y/n/s=skip/q=quit] " "$agent"
    read -r ans </dev/tty || ans="q"
  fi
  case "$ans" in
    q|Q) echo "  aborted by user"; break ;;
    s|S|n|N)
      fb="$(resolve_fallback_id "$agent" "$cwd")"
      if [ -n "$fb" ]; then
        echo "  skipped — fallback id: $fb"
        emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$fb" "latest-jsonl" "$layout" "$zoomed" "$pactive" "$wactive"
      else
        echo "  skipped — no session found, recording without id"
        emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "" "" "$layout" "$zoomed" "$pactive" "$wactive"
      fi
      continue ;;
  esac

  # Send the agent's exit keys, wait for the shell, scrape then fallback.
  exit_keys="$(necro_agent_exit_keys "$agent")"
  [ -n "$exit_keys" ] && tmux send-keys -t "$pane_id" "$exit_keys" Enter
  new_cmd="$(wait_for_shell "$pane_id" 20 || true)"
  necro_is_idle_shell "$new_cmd" && echo "  exit complete (cmd=$new_cmd)" \
    || echo "  WARN: pane still shows cmd=$new_cmd after timeout — scraping anyway"
  sleep 1

  uuid="$(necro_agent_scrape_session_id "$agent" "$pane_id" || true)"
  uuid_source=""
  if [ -n "$uuid" ]; then
    echo "  captured id from scrollback: $uuid"; uuid_source="scrollback"
  else
    uuid="$(resolve_fallback_id "$agent" "$cwd")"
    if [ -n "$uuid" ]; then
      echo "  WARN: no id in scrollback; using fallback: $uuid"; uuid_source="latest-jsonl"
    else
      echo "  WARN: no id found in scrollback or filesystem"
    fi
  fi
  emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$uuid" "$uuid_source" "$layout" "$zoomed" "$pactive" "$wactive"
done <<<"$snapshot"

echo
if [ "$RATE_LIMITED" = "1" ] && [ "$RATE_LIMITED_SAVED" != "1" ]; then
  # Only remove a file this run created. See OUT_PRE_EXISTING above.
  if [ "$OUT_PRE_EXISTING" = "0" ]; then
    rm -f "$OUT"
  else
    echo "Kept existing snapshot from this second: $OUT"
  fi
  echo "No rate-limited panes to save."
  necro_log_event "snapshot" "complete" "output=" "rate_limited=1" "saved=0"
  exit 0
fi
echo "Snapshot written: $OUT"
echo "Records: $(wc -l < "$OUT" | tr -d ' ')"
necro_log_event "snapshot" "complete" "output=$OUT"
