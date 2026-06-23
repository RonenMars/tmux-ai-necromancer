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
# shellcheck source=../lib/agents.sh
. "$SELF_DIR/../lib/agents.sh"
necro_load_agents

# --- Flags ------------------------------------------------------------------
# --idle-only : never send exit keys to a live agent; capture via fallback only.
#               (Used by autosave — zero pane disruption.)
# --yes/-y    : auto-answer 'y' to every per-agent exit prompt.
IDLE_ONLY=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --idle-only) IDLE_ONLY=1 ;;
    --yes|-y)    ASSUME_YES=1 ;;
    --help|-h)
      cat <<'H'
necro-snapshot.sh — capture tmux AI-agent sessions to a JSONL snapshot.

Usage:
  necro-snapshot.sh                 walk panes, prompt per live agent, capture ids
  necro-snapshot.sh --idle-only     record without disturbing any live agent
  necro-snapshot.sh --yes           auto-exit every live agent and capture

Output: <snapshot-dir>/<timestamp>.jsonl (or .idle-only.jsonl)
H
      exit 0 ;;
    *) necro_err "Unknown flag: $arg"; exit 2 ;;
  esac
done

if (( IDLE_ONLY )) && (( ASSUME_YES )); then
  necro_err "--idle-only and --yes are mutually exclusive."
  exit 2
fi

SNAP_DIR="$(necro_snapshot_dir)"
mkdir -p "$SNAP_DIR"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
suffix=""; [ "$IDLE_ONLY" = "1" ] && suffix=".idle-only"
OUT="$SNAP_DIR/${TS}${suffix}.jsonl"

# --- Record emitter ---------------------------------------------------------
# uuid_source: "scrollback" | "latest-jsonl" | "" (none)
emit_record() {
  local pane_id="$1" session="$2" window_index="$3" window_name="$4" \
        cwd="$5" prev_cmd="$6" agent="$7" uuid="$8" uuid_source="${9:-}"
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"pane_id":%s,"session":%s,"window_index":%d,"window_name":%s,"cwd":%s,"prev_cmd":%s,"agent":%s,"uuid":%s,"uuid_source":%s,"captured_at":%s,"first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' \
    "$(necro_json_escape "$pane_id")" \
    "$(necro_json_escape "$session")" \
    "$window_index" \
    "$(necro_json_escape "$window_name")" \
    "$(necro_json_escape "$cwd")" \
    "$(necro_json_escape "$prev_cmd")" \
    "$(necro_json_escape "$agent")" \
    "$(necro_json_escape "$uuid")" \
    "$(necro_json_escape "$uuid_source")" \
    "$(necro_json_escape "$now")" \
    >> "$OUT"
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

# Resolve a session id for an idle/skipped/idle-only pane.
# For live agents uses pop (advances cursor so duplicate cwds get different UUIDs).
# For idle shells falls back to latest (no cursor needed — agent is gone).
resolve_fallback_id() {
  local agent="$1" cwd="$2" live="${3:-0}"
  if [ "$live" = "1" ]; then
    necro_agent_pop_session_id "$agent" "$cwd" 2>/dev/null || true
  else
    necro_agent_latest_session_id "$agent" "$cwd" 2>/dev/null || true
  fi
}

# --- Main -------------------------------------------------------------------
# Temp dir for per-cwd UUID cursors (file-based so they survive subshells).
NECRO_CURSOR_DIR="$(mktemp -d)"
trap 'rm -rf "$NECRO_CURSOR_DIR"' EXIT
export NECRO_CURSOR_DIR

echo "Snapshot will be written to: $OUT"
echo

snapshot=$(tmux list-panes -a -F \
  '#{pane_id}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_path}	#{pane_current_command}')
total=$(printf '%s\n' "$snapshot" | wc -l | tr -d ' ')
i=0

while IFS=$'\t' read -r pane_id session win_idx win_name cwd cmd; do
  [ -z "$pane_id" ] && continue
  i=$((i + 1))
  printf '\n[%d/%d] %s  %s:%s  %s  (cmd=%s)\n' \
    "$i" "$total" "$pane_id" "$session" "$win_idx" "$win_name" "$cmd"

  agent="$(necro_agent_for_cmd "$cmd")"

  # Idle shell — agent may have just exited; try fallback for every agent.
  if necro_is_idle_shell "$cmd"; then
    found_uuid=""; found_agent=""
    for a in $(necro_enabled_agents); do
      fb="$(resolve_fallback_id "$a" "$cwd")"
      if [ -n "$fb" ]; then found_uuid="$fb"; found_agent="$a"; break; fi
    done
    if [ -n "$found_uuid" ]; then
      echo "  idle shell — fallback id ($found_agent): $found_uuid"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$found_agent" "$found_uuid" "latest-jsonl"
    else
      echo "  idle shell — no session found, recording without id"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "" "" ""
    fi
    continue
  fi

  # Not a known agent (node, vim, etc.) — record location only.
  if [ -z "$agent" ]; then
    echo "  not an AI agent (cmd=$cmd) — recording without id"
    emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "" "" ""
    continue
  fi

  # Live agent + --idle-only: pop next UUID for this cwd (handles multiple panes).
  if [ "$IDLE_ONLY" = "1" ]; then
    fb="$(resolve_fallback_id "$agent" "$cwd" 1)"
    if [ -n "$fb" ]; then
      echo "  --idle-only ($agent) — fallback id: $fb"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$fb" "latest-jsonl"
    else
      echo "  --idle-only ($agent) — no session found, recording without id"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "" ""
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
    read -r ans </dev/tty || ans=""
  fi
  case "$ans" in
    q|Q) echo "  aborted by user"; break ;;
    s|S|n|N)
      fb="$(resolve_fallback_id "$agent" "$cwd" 1)"
      if [ -n "$fb" ]; then
        echo "  skipped — fallback id: $fb"
        emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$fb" "latest-jsonl"
      else
        echo "  skipped — no session found, recording without id"
        emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "" ""
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
  emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$uuid" "$uuid_source"
done <<<"$snapshot"

echo
echo "Snapshot written: $OUT"
echo "Records: $(wc -l < "$OUT" | tr -d ' ')"
