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
#   @necro_pane_first_seen — epoch seconds when this pane's agent was first
#                            observed. tmux has no true pane/window creation
#                            timestamp, so this is the closest proxy: used to
#                            reject cursor-pop candidates that predate the
#                            pane (a stale/unrelated transcript can't belong
#                            to a pane that didn't exist yet when it was
#                            written).
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents.sh"
necro_init_log "$0"
necro_load_agents

# Self-throttle: run at most once per second regardless of status-interval.
# Read-then-set is a TOCTOU: every attached client evaluates status-right, so
# two watchers can both pass this check before either writes the option. Two
# concurrent walks race the cursor files (double-popping UUIDs) and the pane
# option writes. Same hazard, and same fix, as the autosave lock (invariant 7).
LAST_WATCH_OPT="@necromancer_last_watch"
now="$(date +%s)"
last="$(necro_tmux_option "$LAST_WATCH_OPT" 0)"
[ "$(( now - last ))" -lt 1 ] && exit 0

# mkdir is the only POSIX-atomic primitive available here. Unlike autosave,
# this script does its work in the foreground, so a plain EXIT trap correctly
# holds the lock for the whole walk.
#
# Break a stale lock first: if a watcher is SIGKILLed its trap never runs, and
# a permanently-held lock would silently stop all UUID pinning — the plugin's
# core job — with no error anywhere. A tick is sub-second, so a lock older than
# 60s cannot be a live run.
WATCH_LOCK="$(necro_snapshot_dir)/.watch.lock"
mkdir -p "$(dirname "$WATCH_LOCK")" 2>/dev/null || true
if [ -d "$WATCH_LOCK" ]; then
  lock_mtime="$(stat -f %m "$WATCH_LOCK" 2>/dev/null || stat -c %Y "$WATCH_LOCK" 2>/dev/null)"
  if [ -n "$lock_mtime" ] && [ "$(( now - lock_mtime ))" -gt 60 ]; then
    rmdir "$WATCH_LOCK" 2>/dev/null || true
  fi
fi
mkdir "$WATCH_LOCK" 2>/dev/null || exit 0
trap 'rmdir "$WATCH_LOCK" 2>/dev/null' EXIT

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
    tmux set-option -pu -t "$pane_id" @necro_uuid            2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_cmd             2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent           2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent_exited    2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_pane_first_seen 2>/dev/null || true
    pinned_uuid=""; pinned_cmd=""; pinned_agent=""; exited=""
    # Falls through to Case 2 (pin fresh UUID).
  fi

  # ── Case 2: new agent pane detected, not yet pinned ───────────────────────
  if [ -n "$agent" ] && [ -z "$pinned_uuid" ]; then
    # Ground truth first: read --resume <uuid> straight from the running
    # process argv. Scrollback and cursor-pop are both guesses; argv isn't.
    uuid="$(necro_agent_scrape_ps_resume "$agent" "$pane_id" 2>/dev/null || true)"
    # Fall back to scrollback (resurrect edge case: pane started with --resume
    # but the process already exited/respawned before this tick).
    if [ -z "$uuid" ]; then
      uuid="$(necro_agent_scrape_resume_cmd "$agent" "$pane_id" 2>/dev/null || true)"
    fi
    # First-seen stamp: closest proxy tmux offers for pane creation time.
    # Written before the cursor-pop fallback so that fallback can reject
    # transcripts older than this pane.
    first_seen="$(tmux show-option -pqv -t "$pane_id" @necro_pane_first_seen 2>/dev/null || true)"
    if [ -z "$first_seen" ]; then
      first_seen="$now"
      tmux set-option -p -t "$pane_id" @necro_pane_first_seen "$first_seen" 2>/dev/null || true
    fi
    # Last resort: cursor pop. Only reached for fresh (non-resumed) sessions
    # where no ground truth exists yet. Filtered to transcripts no older than
    # this pane, so a stale/unrelated session can't be handed out.
    if [ -z "$uuid" ]; then
      uuid="$(necro_agent_pop_session_id "$agent" "$cwd" "$first_seen" 2>/dev/null || true)"
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
    continue
  fi

done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null)

exit 0
