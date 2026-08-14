#!/usr/bin/env bash
# necro-watch.sh — per-tick pane watcher; pins @necro_uuid on agent panes.
#
# Runs once per watcher-daemon tick. Self-throttles to
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
#   @necro_limit_saved     — "1" after a rate-limited snapshot recorded this
#                            pane for the current limit event. Cleared on
#                            agent restart (and by --rate-limited --auto when
#                            the limit banner disappears).
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents.sh"

# Prime the global-option cache HERE, in the top-level shell.
#
# necro_tmux_option() memoizes `tmux show-options -g`, but every caller invokes
# it as `$(necro_tmux_option ...)` — a subshell — so the memo dies with the
# subshell and the next call dumps every global option again. Each pane costs
# one such dump per agent adapter (@necromancer_<agent>_commands), so the tick
# scaled at panes x adapters: measured at 28 full dumps for a 10-pane server.
# Priming in the parent means the subshells inherit a warm cache and skip it.
# Nothing here mutates a global option before the walk, so the cache can't go
# stale within a tick, and each tick is a fresh process that re-primes.
_necro_load_tmux_options_g

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
if [ "$(( now - last ))" -lt 1 ]; then
  necro_log_event "watch" "skip" "reason=throttled"
  exit 0
fi

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
necro_log_event "watch" "start" "cursor_dir=$WATCH_LOCK"

tmux set-option -gq "$LAST_WATCH_OPT" "$now"

# Persistent cursor dir (survives across ticks).
export NECRO_CURSOR_DIR
NECRO_CURSOR_DIR="$(necro_watch_cursor_dir)"

# Walk every pane.
#
# The pane's @necro_* options come straight out of the list-panes format rather
# than a `show-options -p` per pane: at @necromancer_watch_tick 1 that per-pane
# read was one tmux round-trip per pane per second, forever. One format string
# makes a tick exactly one tmux invocation regardless of pane count.
# pane_current_path is read LAST so that a separator inside a path
# (pathological, but free to defend against) lands in the final field instead
# of shifting every option one column over.
#
# The separator is ASCII Unit Separator, NOT tab: bash collapses a run of IFS
# *whitespace* into a single delimiter, so with tabs a pane whose @necro_uuid
# is unset would read its @necro_cmd into pinned_uuid and shift every field
# after it. A non-whitespace IFS char delimits exactly one field, preserving
# empties — which is the normal case here, since an unpinned pane has all five
# options unset.
#
# tmux 3.5a escapes control bytes in format output, so the separator comes
# back as the four literal characters \037 and IFS never matches: the whole
# line lands in pane_id, cmd is empty, no pane is ever recognised as an agent,
# and UUID pinning is silently dead. Measured on binaries built from source:
# 3.5a emits zero raw 0x1f bytes; 3.6 and 3.7b emit the byte.
# _necro_unescape_fs below restores the byte so both behaviours parse; the
# substitution is bash 3.2 pattern replacement, not a fork per tick.
NECRO_FS=$'\037'

# Restore separators that tmux escaped to the literal string \037.
_necro_unescape_fs() {
  local text
  text="$(cat)"
  printf '%s\n' "${text//\\037/$NECRO_FS}"
}

while IFS="$NECRO_FS" read -r pane_id cmd pinned_uuid pinned_cmd pinned_agent exited first_seen cwd; do
  [ -z "$pane_id" ] && continue

  agent="$(necro_agent_for_cmd "$cmd")"

  # ── Case 1: agent restarted in a pane that previously exited ──────────────
  if [ -n "$agent" ] && [ "$exited" = "1" ]; then
    necro_log_event "watch" "agent_restart" "pane=$pane_id" "agent=$agent"
    tmux set-option -pu -t "$pane_id" @necro_uuid            2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_cmd             2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent           2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent_exited    2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_pane_first_seen 2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_limit_saved     2>/dev/null || true
    # first_seen is cleared too: it was read before the unset above, and Case 2
    # re-stamps it. Leaving the pre-unset value here would keep the OLD stamp,
    # and the min_epoch filter would then reject the relaunched agent's own
    # (newer) transcript. limit_saved clears so a later quota hit can be
    # auto-saved again for the new launch.
    pinned_uuid=""; pinned_cmd=""; pinned_agent=""; exited=""; first_seen=""
    # Falls through to Case 2 (pin fresh UUID).
  fi

  # ── Case 2: new agent pane detected, not yet pinned ───────────────────────
  if [ -n "$agent" ] && [ -z "$pinned_uuid" ]; then
    # Ground truth first: read --resume <uuid> straight from the running
    # process argv. Scrollback and cursor-pop are both guesses; argv isn't.
    uuid="$(necro_agent_scrape_ps_resume "$agent" "$pane_id" 2>/dev/null || true)"
    uuid_src="argv"
    # Fall back to scrollback (resurrect edge case: pane started with --resume
    # but the process already exited/respawned before this tick).
    if [ -z "$uuid" ]; then
      uuid="$(necro_agent_scrape_resume_cmd "$agent" "$pane_id" 2>/dev/null || true)"
      uuid_src="scrollback"
    fi
    # First-seen stamp: closest proxy tmux offers for pane creation time.
    # Written before the cursor-pop fallback so that fallback can reject
    # transcripts older than this pane.
    if [ -z "$first_seen" ]; then
      first_seen="$now"
      tmux set-option -p -t "$pane_id" @necro_pane_first_seen "$first_seen" 2>/dev/null || true
    fi
    # Last resort: cursor pop. Only reached for fresh (non-resumed) sessions
    # where no ground truth exists yet. Filtered to transcripts no older than
    # this pane, so a stale/unrelated session can't be handed out.
    if [ -z "$uuid" ]; then
      uuid="$(necro_agent_pop_session_id "$agent" "$cwd" "$first_seen" 2>/dev/null || true)"
      uuid_src="cursor-pop"
    fi
    if [ -n "$uuid" ]; then
      necro_log_event "watch" "pin_uuid" "pane=$pane_id" "agent=$agent" \
        "source=$uuid_src" "min_epoch=${first_seen:-}"
      tmux set-option -p -t "$pane_id" @necro_uuid  "$uuid"  2>/dev/null || true
      tmux set-option -p -t "$pane_id" @necro_cmd   "$cmd"   2>/dev/null || true
      tmux set-option -p -t "$pane_id" @necro_agent "$agent" 2>/dev/null || true
    fi
    continue
  fi

  # ── Case 3: agent exited (had @necro_cmd set, current cmd no longer matches) ─
  if [ -n "$pinned_cmd" ] && [ -z "$agent" ] && [ "$exited" != "1" ]; then
    # pane_current_command follows the tty foreground pgrp leader, which flips
    # to the shell when the agent is merely SUSPENDED (codex honors Ctrl-Z and
    # stops; claude ignores it). Marking such a pane "exited" is wrong: the next
    # tick's Case 1 would wipe the pin AND @necro_pane_first_seen, and the reset
    # (later) first_seen then makes cursor-pop reject the pane's own transcript
    # via the min_epoch filter — permanently losing the UUID for a fresh
    # (non-resumed) session. So only treat it as exited when no agent process
    # survives among the pane's children; a suspended agent is still there.
    if [ -n "$(necro_agent_alive_in_pane "$pane_id")" ]; then
      continue
    fi
    necro_log_event "watch" "agent_exit" "pane=$pane_id" "agent=${pinned_agent:-$pinned_cmd}"
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

done < <(tmux list-panes -a -F "#{pane_id}${NECRO_FS}#{pane_current_command}${NECRO_FS}#{@necro_uuid}${NECRO_FS}#{@necro_cmd}${NECRO_FS}#{@necro_agent}${NECRO_FS}#{@necro_agent_exited}${NECRO_FS}#{@necro_pane_first_seen}${NECRO_FS}#{pane_current_path}" 2>/dev/null | _necro_unescape_fs)

# Throttled rate-limit auto-save. capture-pane is O(agent panes), so this must
# NOT run every watch tick (invariant 15). Default interval is 60s. The snapshot
# runs in a backgrounded subshell behind its own mkdir lock so the watch lock
# is released immediately and concurrent ticks cannot stack captures.
#
# NECROMANCER_LIMIT_CHECK_INTERVAL overrides the tmux option (0 disables).
# Watcher unit tests that assert tick cost / lock behaviour export 0 so a
# background snapshot cannot pollute their call counts.
if [ -n "${NECROMANCER_LIMIT_CHECK_INTERVAL+x}" ]; then
  LIMIT_INTERVAL="$NECROMANCER_LIMIT_CHECK_INTERVAL"
else
  LIMIT_INTERVAL="$(necro_tmux_option @necromancer_limit_check_interval 60)"
fi
case "$LIMIT_INTERVAL" in
  ''|*[!0-9]*) LIMIT_INTERVAL=60 ;;
esac
LAST_LIMIT_OPT="@necromancer_last_limit_check"
if [ "$LIMIT_INTERVAL" -gt 0 ]; then
  last_limit="$(necro_tmux_option "$LAST_LIMIT_OPT" 0)"
  case "$last_limit" in
    ''|*[!0-9]*) last_limit=0 ;;
  esac
  if [ "$(( now - last_limit ))" -ge "$LIMIT_INTERVAL" ]; then
    tmux set-option -gq "$LAST_LIMIT_OPT" "$now"
    necro_log_event "watch" "limit_check_due" "interval=$LIMIT_INTERVAL"
    _necro_limit_save_work() {
      LIMIT_LOCK="$(necro_snapshot_dir)/.limit-save.lock"
      mkdir "$LIMIT_LOCK" 2>/dev/null || return 0
      trap 'rmdir "$LIMIT_LOCK" 2>/dev/null' EXIT
      "$SELF_DIR/necro-snapshot.sh" --rate-limited --auto >/dev/null 2>&1 || true
    }
    # Always run in a subshell so the limit-lock EXIT trap cannot overwrite the
    # watch lock's trap. Sync mode (tests) waits; production backgrounds.
    if [ "${NECROMANCER_LIMIT_SAVE_SYNC:-0}" = "1" ]; then
      ( _necro_limit_save_work )
    else
      ( _necro_limit_save_work ) &
    fi
  fi
fi

exit 0
