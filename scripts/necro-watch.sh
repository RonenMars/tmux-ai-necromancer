#!/usr/bin/env bash
# necro-watch.sh — per-tick pane watcher; pins @necro_uuid on agent panes.
#
# Runs every status-interval seconds via status-right. Self-throttles to
# avoid running more than once per second. Zero pane disruption.
#
# Pane options set:
#   @necro_uuid         — confirmed UUID for this pane's agent session
#   @necro_cmd          — the command name that matched (e.g. "claude", "cc")
#   @necro_agent        — the adapter name that matched (e.g. "claude")
#   @necro_agent_exited — "1" when the agent has exited cleanly
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents.sh"
necro_load_agents

# Self-throttle: run at most once per second regardless of status-interval.
LAST_WATCH_OPT="@necromancer_last_watch"
now="$(date +%s)"
last="$(necro_tmux_option "$LAST_WATCH_OPT" 0)"
[ "$(( now - last ))" -lt 1 ] && exit 0
tmux set-option -gq "$LAST_WATCH_OPT" "$now"

# Persistent cursor dir (survives across ticks).
export NECRO_CURSOR_DIR
NECRO_CURSOR_DIR="$(necro_watch_cursor_dir)"

# Walk every pane.
while IFS=$'\t' read -r pane_id cmd cwd; do
  [ -z "$pane_id" ] && continue

  pinned_uuid="$(tmux show-option -pqv -t "$pane_id" @necro_uuid          2>/dev/null || true)"
  pinned_cmd="$(tmux show-option  -pqv -t "$pane_id" @necro_cmd           2>/dev/null || true)"
  pinned_agent="$(tmux show-option -pqv -t "$pane_id" @necro_agent        2>/dev/null || true)"
  exited="$(tmux show-option      -pqv -t "$pane_id" @necro_agent_exited  2>/dev/null || true)"

  agent="$(necro_agent_for_cmd "$cmd")"

  # ── Case 1: agent restarted in a pane that previously exited ──────────────
  if [ -n "$agent" ] && [ "$exited" = "1" ]; then
    tmux set-option -pu -t "$pane_id" @necro_uuid          2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_cmd           2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent         2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent_exited  2>/dev/null || true
    pinned_uuid=""; pinned_cmd=""; pinned_agent=""; exited=""
    # Falls through to Case 2 (pin fresh UUID).
  fi

  # ── Case 2: new agent pane detected, not yet pinned ───────────────────────
  if [ -n "$agent" ] && [ -z "$pinned_uuid" ]; then
    # Try scrollback first (resurrect edge case: pane started with --resume).
    uuid="$(necro_agent_scrape_resume_cmd "$agent" "$pane_id" 2>/dev/null || true)"
    # Fall back to cursor pop.
    if [ -z "$uuid" ]; then
      uuid="$(necro_agent_pop_session_id "$agent" "$cwd" 2>/dev/null || true)"
    fi
    if [ -n "$uuid" ]; then
      tmux set-option -p -t "$pane_id" @necro_uuid  "$uuid"  2>/dev/null || true
      tmux set-option -p -t "$pane_id" @necro_cmd   "$cmd"   2>/dev/null || true
      tmux set-option -p -t "$pane_id" @necro_agent "$agent" 2>/dev/null || true
    fi
    continue
  fi

  # ── Case 3: agent exited (had @necro_cmd set, current cmd no longer matches) ─
  if [ -n "$pinned_cmd" ] && [ -z "$agent" ] && [ "$exited" != "1" ]; then
    # Use the stored adapter name for scraping (not the raw command name).
    scrape_agent="${pinned_agent:-$pinned_cmd}"
    # Scrape farewell UUID from scrollback — more reliable than what we popped.
    farewell="$(necro_agent_scrape_session_id "$scrape_agent" "$pane_id" 2>/dev/null || true)"
    if [ -n "$farewell" ] && [ "$farewell" != "$pinned_uuid" ]; then
      tmux set-option -p -t "$pane_id" @necro_uuid "$farewell" 2>/dev/null || true
    fi
    tmux set-option -p  -t "$pane_id" @necro_agent_exited "1" 2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_cmd               2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent             2>/dev/null || true
    continue
  fi

done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null)

exit 0
