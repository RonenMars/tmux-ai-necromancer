#!/usr/bin/env bash
# necro-doctor.sh — read-only health check for tmux-ai-necromancer.
#
# Answers the question a user actually has when sessions don't come back:
# "is this thing working on my machine?" It inspects the SNAPSHOT (what restore
# will actually replay) and the live pane pins, not the debug logs — debug
# logging is off by default, so a log-based check reports nothing useful in the
# configuration almost everyone runs.
#
# STRICTLY READ-ONLY. It never sends keys, never kills a window, never writes a
# snapshot, and never touches a lock. Safe to run against a live server at any
# time, including from inside tmux.
#
# Exit status: 0 when no problems were found, 1 when at least one ✗ was
# reported, so it can gate a script. Warnings alone do not fail.
#
# NOTE: `set -uo pipefail`, not `set -e` — the checks below use pipelines that
# legitimately exit non-zero (grep with no match), and a doctor that aborts on
# its first clean check would be worse than useless (invariant 1).
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

case "${1:-}" in
  -h|--help)
    cat <<'H'
necro-doctor.sh — read-only health check for tmux-ai-necromancer.

Usage:
  necro-doctor.sh          run every check and print a report

Reports on dependencies, effective configuration, both daemons, lock state,
agent adapters, live pane pins, the newest snapshot, and the reboot pointer.

Read-only: sends no keys, kills nothing, writes nothing. Exits 1 if any check
reported a problem (✗); warnings (⚠) alone exit 0.
H
    exit 0 ;;
  "") ;;
  *) necro_err "Unknown flag: $1"; exit 2 ;;
esac

PROBLEMS=0
WARNINGS=0

section() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }
ok()      { printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
warn()    { printf '  \033[1;33m⚠\033[0m %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
bad()     { printf '  \033[1;31m✗\033[0m %s\n' "$1"; PROBLEMS=$((PROBLEMS + 1)); }
note()    { printf '      %s\n' "$1"; }

file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# Seconds -> "4d 3h" / "2h 5m" / "45s". Keeps report lines scannable.
human_age() {
  local s="${1:-0}"
  if   [ "$s" -ge 86400 ]; then printf '%dd %dh' "$((s / 86400))" "$(((s % 86400) / 3600))"
  elif [ "$s" -ge 3600  ]; then printf '%dh %dm' "$((s / 3600))"  "$(((s % 3600) / 60))"
  elif [ "$s" -ge 60    ]; then printf '%dm'     "$((s / 60))"
  else                          printf '%ds'     "$s"
  fi
}

SNAP_DIR="$(necro_snapshot_dir)"
NOW="$(date +%s)"
HAVE_SERVER=0
tmux list-sessions >/dev/null 2>&1 && HAVE_SERVER=1

necro_hr
necro_say "Necromancer doctor"
echo "  Plugin root:  $PLUGIN_ROOT"
echo "  Snapshot dir: $SNAP_DIR"
necro_hr

# ── Dependencies ─────────────────────────────────────────────────────────────
section "Dependencies"
if command -v tmux >/dev/null 2>&1; then
  ok "tmux $(tmux -V 2>/dev/null | awk '{print $2}')"
else
  bad "tmux not found — nothing in this plugin works without it"
fi
command -v jq      >/dev/null 2>&1 && ok "jq"      || bad "jq not found — restore and apply cannot parse snapshots (brew install jq)"
command -v python3 >/dev/null 2>&1 && ok "python3" || bad "python3 not found — snapshots cannot be JSON-escaped"

# ── Effective configuration ──────────────────────────────────────────────────
# Resolved through necro_tmux_option, so this reports what the CODE sees, not
# what tmux.conf says. That difference is the whole point: editing tmux.conf
# without re-sourcing it changes nothing, and this is where you notice.
section "Effective configuration"
if [ "$HAVE_SERVER" = "1" ]; then
  echo "  agents             $(necro_tmux_option @necromancer_agents 'claude codex')"
  echo "  interval           $(necro_tmux_option @necromancer_interval 5) min"
  echo "  max_snapshots      $(necro_tmux_option @necromancer_max_snapshots 288)"
  echo "  autosave_tick      $(necro_tmux_option @necromancer_autosave_tick 60) s"
  echo "  watch_tick         $(necro_tmux_option @necromancer_watch_tick 1) s"
  echo "  claude_commands    $(necro_tmux_option @necromancer_claude_commands 'claude')"
  echo "  codex_commands     $(necro_tmux_option @necromancer_codex_commands 'codex codex-*')"
  echo "  debug              $(necro_tmux_option @necromancer_debug off)"
else
  warn "no tmux server — showing built-in defaults, not your live configuration"
fi

# ── Daemons ──────────────────────────────────────────────────────────────────
# Both must be up. Checking only one is how the predecessor tooling missed a
# dead watcher while happily reporting the autosave daemon alive.
section "Daemons"
check_daemon() {
  local label="$1" script="$2" lock="$SNAP_DIR/$3"
  local live lock_pid
  live="$(pgrep -f "$script" 2>/dev/null | head -1)"
  lock_pid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [ -z "$live" ]; then
    bad "$label daemon is NOT running"
    note "start it with: tmux run-shell -b $SCRIPTS_DIR/$script"
    [ -n "$lock_pid" ] && note "a stale lock records pid $lock_pid; the next daemon start reclaims it"
    return
  fi
  ok "$label daemon running (pid $live)"
  if [ -n "$lock_pid" ] && [ "$lock_pid" != "$live" ]; then
    warn "$label lock records pid $lock_pid but the live process is $live"
    note "harmless if you just restarted it; persistent mismatch means a second daemon was blocked"
  fi
}
if [ "$HAVE_SERVER" = "1" ]; then
  check_daemon "autosave" "necro-autosave-daemon.sh" ".autosave-daemon.lock"
  check_daemon "watcher"  "necro-watch-daemon.sh"    ".watch-daemon.lock"
else
  warn "no tmux server — daemons cannot be running"
fi

# ── Work locks ───────────────────────────────────────────────────────────────
# A wedged lock is silent: UUID pinning simply stops, with no error anywhere.
section "Work locks"
check_lock() {
  local label="$1" path="$SNAP_DIR/$2" stale_after="$3" age m now
  if [ ! -d "$path" ]; then
    ok "$label lock free"
    return
  fi
  m="$(file_mtime "$path")"
  if [ -z "$m" ]; then
    warn "$label lock held (age unknown)"
    return
  fi
  # Re-sample the clock rather than reusing $NOW from startup. The watcher
  # ticks every second, so its lock is routinely created AFTER this run began
  # and NOW - mtime goes negative — reported as "held for -1s". Clamp too, so
  # clock skew or a filesystem with coarse timestamps can't reintroduce it.
  now="$(date +%s)"
  age=$((now - m))
  [ "$age" -lt 0 ] && age=0
  if [ "$age" -gt "$stale_after" ]; then
    bad "$label lock held for $(human_age "$age") — stale, blocking work"
    note "remove it with: rmdir '$path'"
  else
    ok "$label lock held for $(human_age "$age") (a run is in progress)"
  fi
}
# 60s mirrors the watcher's own self-heal threshold; a tick is sub-second.
check_lock "watcher"  ".watch.lock"    60
# Autosave holds its lock for the whole snapshot, so allow a generous window.
check_lock "autosave" ".autosave.lock" 600

# ── Agent adapters ───────────────────────────────────────────────────────────
section "Agent adapters"
necro_load_agents >/dev/null 2>&1
for agent_name in $(necro_enabled_agents); do
  if [ ! -f "$LIB_DIR/agents/${agent_name}.sh" ]; then
    bad "'$agent_name' is enabled but lib/agents/${agent_name}.sh does not exist"
    note "remove it from @necromancer_agents, or add the adapter (see docs/agents.md)"
    continue
  fi
  missing=""
  for fn in matches resume_cmd; do
    declare -f "agent_${agent_name}_${fn}" >/dev/null 2>&1 || missing="$missing agent_${agent_name}_${fn}"
  done
  if [ -n "$missing" ]; then
    bad "'$agent_name' adapter loaded but is missing:$missing"
  else
    ok "'$agent_name' adapter loaded"
  fi
done

# ── Live panes ───────────────────────────────────────────────────────────────
# The watcher's whole job is pinning a UUID to every agent pane. An agent pane
# with no pin falls back to a filesystem guess at snapshot time, which is
# exactly the path that used to hand out stale transcripts.
section "Live agent panes"
# Hoisted: the snapshot section below compares against it, and `set -u` would
# abort there if no server had ever set it.
agent_total=0
if [ "$HAVE_SERVER" = "1" ]; then
  pane_total=0; agent_total=0; pinned_total=0; unpinned_list=""
  while IFS=$'\t' read -r pane_id pane_cmd; do
    [ -n "$pane_id" ] || continue
    pane_total=$((pane_total + 1))
    necro_is_idle_shell "$pane_cmd" && continue
    this_agent="$(necro_agent_for_cmd "$pane_cmd")"
    [ -n "$this_agent" ] || continue
    agent_total=$((agent_total + 1))
    if [ -n "$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)" ]; then
      pinned_total=$((pinned_total + 1))
    else
      unpinned_list="$unpinned_list $pane_id($this_agent)"
    fi
  done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}' 2>/dev/null)

  echo "  $pane_total pane(s), $agent_total running a known agent"
  if [ "$agent_total" = "0" ]; then
    ok "no agent panes to pin"
  elif [ "$pinned_total" = "$agent_total" ]; then
    ok "all $agent_total agent pane(s) have a pinned UUID"
  else
    warn "$pinned_total of $agent_total agent pane(s) have a pinned UUID"
    note "unpinned:$unpinned_list"
    note "a just-started agent pins within a tick; if this persists the watcher is not resolving an id"
  fi
else
  warn "no tmux server — skipping pane checks"
fi

# ── Newest snapshot ──────────────────────────────────────────────────────────
# This is the money check: restore replays these records, so a snapshot whose
# records carry no uuid will resurrect nothing no matter how healthy the rest.
section "Newest snapshot"
latest="$(/bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null | head -1)"
[ -n "$latest" ] || latest="$(/bin/ls -t "$SNAP_DIR"/*.jsonl 2>/dev/null | grep -v enriched | head -1)"
if [ -z "$latest" ] || [ ! -f "$latest" ]; then
  warn "no snapshot found in $SNAP_DIR"
  note "expected on a fresh install; otherwise run: $SCRIPTS_DIR/necro-snapshot.sh"
else
  echo "  $(basename "$latest")"
  snap_m="$(file_mtime "$latest")"
  if [ -n "$snap_m" ]; then
    snap_age=$((NOW - snap_m))
    interval_min="$(necro_tmux_option @necromancer_interval 5)"
    case "$interval_min" in ''|*[!0-9]*) interval_min=5 ;; esac
    if [ "$snap_age" -gt $((interval_min * 60 * 3)) ]; then
      warn "last written $(human_age "$snap_age") ago — more than 3x the ${interval_min}m interval"
      note "autosave may be stalled; check the daemon and lock sections above"
    else
      ok "last written $(human_age "$snap_age") ago"
    fi
  fi
  records="$(grep -cve '^[[:space:]]*$' "$latest" 2>/dev/null || true)"; records="${records:-0}"
  with_agent="$(grep -c '"agent":"[^"]' "$latest" 2>/dev/null || true)"; with_agent="${with_agent:-0}"
  with_uuid="$(grep -c '"uuid":"[^"]' "$latest" 2>/dev/null || true)";  with_uuid="${with_uuid:-0}"
  echo "  $records record(s), $with_agent with an agent, $with_uuid with a UUID"
  if [ "$records" = "0" ]; then
    bad "snapshot is empty — restore would rebuild nothing"
  elif [ "$with_agent" = "0" ]; then
    warn "no record names an agent — restore will recreate panes but resume nothing"
    note "if you do have agents running, they are not being recognised: check @necromancer_agents"
  elif [ "$with_uuid" -lt "$with_agent" ]; then
    warn "$((with_agent - with_uuid)) agent record(s) carry no UUID and cannot be resumed"
  else
    ok "every agent record carries a UUID"
  fi

  # Every check above asks whether the records are well-formed, never whether
  # they cover the server. A snapshot written while the server was collapsing —
  # or mid-restore, before the panes exist — is perfectly well-formed and
  # resurrects only the fraction it saw. That is what makes it dangerous:
  # `necro-reboot-resume.sh` with no pinned pointer takes the NEWEST file, so an
  # unrepresentative newest snapshot silently restores less than you had.
  # Only under-coverage matters; more records than live panes just means agents
  # exited since, which costs restore nothing.
  if [ "$HAVE_SERVER" = "1" ] && [ "$with_agent" -lt "$agent_total" ]; then
    warn "snapshot names $with_agent agent(s) but $agent_total are running — it does not represent the server"
    note "a restore from this file would resurrect $with_agent of $agent_total; do not run a bare necro-resume until the next autosave"
    note "expected briefly after an agent starts or during a restore; it heals on the next tick"
  fi
fi

# ── Reboot pointer ───────────────────────────────────────────────────────────
section "Reboot pointer"
pointer="$SNAP_DIR/latest-for-reboot"
# -L before -e: `-e` follows the link, so a DANGLING pointer — the one case
# worth reporting — tests false and would be misread as "no pointer at all".
if [ -L "$pointer" ]; then
  target="$(readlink "$pointer" 2>/dev/null || true)"
  if [ -f "$target" ]; then
    ok "pinned -> $(basename "$target")"
  else
    bad "pointer is dangling (-> ${target:-?})"
    note "necro-reboot-resume.sh falls back to the newest autosave; re-pin with necro-reboot-prep.sh or delete it"
  fi
elif [ -e "$pointer" ]; then
  warn "pointer exists but is not a symlink"
  note "necro-reboot-prep.sh writes it with 'ln -sfn'; something else created this"
else
  ok "no pinned reboot snapshot (normal outside a reboot cycle)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
necro_hr
if [ "$PROBLEMS" -gt 0 ]; then
  necro_err "$PROBLEMS problem(s), $WARNINGS warning(s)"
elif [ "$WARNINGS" -gt 0 ]; then
  necro_warn "$WARNINGS warning(s), no problems"
else
  necro_ok "all checks passed"
fi
necro_log_event "doctor" "complete" "problems=$PROBLEMS" "warnings=$WARNINGS"
[ "$PROBLEMS" -eq 0 ]
