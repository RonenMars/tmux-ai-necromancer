#!/usr/bin/env bash
# =============================================================================
# necro-reboot-resume.sh — re-open AI agents in each pane after a reboot.
#
# Pairs with necro-reboot-prep.sh. Flow:
#   1. Ask whether to clean up idle tmux windows first.
#   2. Resolve the pinned snapshot (latest-for-reboot) or an explicit arg.
#   3. Ensure the tmux server is up (trigger tmux-continuum restore if present).
#   4. Run necro-restore.sh against the snapshot — idempotently recreates
#      sessions/windows and resumes each agent.
#
# Run from OUTSIDE tmux (fresh terminal).
#
# Usage:
#   necro-reboot-resume.sh                  use pinned snapshot
#   necro-reboot-resume.sh <snapshot.jsonl> use a specific snapshot
#   necro-reboot-resume.sh --dry-run        show plan, change nothing
#   necro-reboot-resume.sh --keep-pointer   don't delete pointer on success
#   necro-reboot-resume.sh --force-large    resume large Claude transcripts
#   necro-reboot-resume.sh --allow-unsafe-cwd
# =============================================================================
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

SNAP_DIR="$(necro_snapshot_dir)"
POINTER="$SNAP_DIR/latest-for-reboot"
RESURRECT_RESTORE="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

SNAPSHOT=""; DRY_RUN=0; KEEP_POINTER=0; FORCE_LARGE=0; ALLOW_UNSAFE_CWD=0; CLEANUP_EXISTING=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1; shift ;;
    --keep-pointer) KEEP_POINTER=1; shift ;;
    --force-large)  FORCE_LARGE=1; shift ;;
    --allow-unsafe-cwd) ALLOW_UNSAFE_CWD=1; shift ;;
    -h|--help)      sed -n '/^# =\{3,\}/,/^# =\{3,\}/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) necro_err "Unknown flag: $1"; exit 2 ;;
    *)  SNAPSHOT="$1"; shift ;;
  esac
done

stage() { printf '[%d/%d] %s\n' "$1" "$2" "$3"; }

cleanup_empty_windows() {
  local dry_run="${1:-0}"
  local busy_file child_count
  busy_file="$(mktemp "${TMPDIR:-/tmp}/necro-busy-windows.XXXXXX")" || return 1

  while read -r wid pid; do
    [ -n "$wid" ] || continue
    child_count="$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$child_count" -gt 0 ]; then
      printf '%s\n' "$wid" >> "$busy_file"
    else
      echo "  idle pane: wid=$wid pid=$pid"
    fi
  done < <(tmux list-panes -a -F '#{window_id} #{pane_pid}' 2>/dev/null)

  while read -r wid label; do
    [ -n "$wid" ] || continue
    if grep -Fxq "$wid" "$busy_file"; then
      echo "  keeping active window: $label ($wid)"
    else
      if [ "$dry_run" = "1" ]; then
        echo "[dry-run] would kill idle window: $label ($wid)"
      else
        echo "Killing idle window: $label ($wid)"
        tmux kill-window -t "$wid" 2>/dev/null || true
      fi
    fi
  done < <(tmux list-windows -a -F '#{window_id} #{session_name}:#{window_index}' 2>/dev/null)

  rm -f "$busy_file"
}

if [ -n "${TMUX:-}" ]; then
  necro_err "You're inside tmux. Run from a fresh terminal."; exit 1
fi
command -v tmux >/dev/null || { necro_err "tmux not installed."; exit 1; }

stage 1 5 "cleanup prompt"
printf 'Clean up idle tmux windows before resuming? [y/N] '
read -r cleanup_confirm
case "$cleanup_confirm" in
  y|Y) CLEANUP_EXISTING=1 ;;
  *) CLEANUP_EXISTING=0 ;;
esac

stage 2 5 "resolving snapshot"
if [ -z "$SNAPSHOT" ]; then
  if [ -e "$POINTER" ]; then
    SNAPSHOT="$(readlink -f "$POINTER" 2>/dev/null || readlink "$POINTER")"
  else
    necro_warn "No reboot pointer found — falling back to latest autosave."
    SNAPSHOT="$(/bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null | head -1)"
    [ -n "$SNAPSHOT" ] || { necro_err "No autosave snapshots found in $SNAP_DIR."; exit 1; }
  fi
fi
[ -f "$SNAPSHOT" ] || { necro_err "Snapshot not found: $SNAPSHOT"; exit 1; }

necro_hr
necro_say "Necromancer reboot resume"
echo "  Snapshot: $SNAPSHOT"
echo "  Dry-run:  $DRY_RUN"
echo "  Cleanup idle tmux windows: $CLEANUP_EXISTING"
echo "  Force large Claude transcripts: $FORCE_LARGE"
echo "  Allow unsafe cwd paths: $ALLOW_UNSAFE_CWD"
necro_hr

# ── Phase 1: ensure tmux server + layout ────────────────────────────────────
server_up() { tmux list-sessions >/dev/null 2>&1; }
stage 3 5 "ensuring tmux server"
necro_say "Phase 1: ensure tmux server is up"
if server_up; then
  necro_ok "Server already up ($(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ') session(s))."
elif (( DRY_RUN )); then
  necro_say "DRY-RUN: would start server / trigger continuum restore"
else
  tmux start-server
  for _ in $(seq 1 20); do sleep 0.5; server_up && break; done
  if ! server_up && [ -x "$RESURRECT_RESTORE" ]; then
    necro_warn "Continuum didn't auto-restore — running resurrect restore."
    "$RESURRECT_RESTORE" >/dev/null || true
  fi
  necro_ok "Server up ($(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ') session(s))."
fi
if [ "$CLEANUP_EXISTING" = "1" ]; then
  necro_say "Cleaning up idle tmux windows"
  cleanup_empty_windows "$DRY_RUN"
fi
necro_hr

# ── Phase 2: restore ────────────────────────────────────────────────────────
stage 4 5 "running restore"
necro_say "Phase 2: necro-restore.sh"
restore_flags=(); (( DRY_RUN )) && restore_flags+=(--dry-run)
(( FORCE_LARGE )) && restore_flags+=(--force-large)
(( ALLOW_UNSAFE_CWD )) && restore_flags+=(--allow-unsafe-cwd)
"$SELF_DIR/necro-restore.sh" ${restore_flags[@]+"${restore_flags[@]}"} "$SNAPSHOT"
necro_hr

stage 5 5 "cleanup"
if [ "$DRY_RUN" = "0" ] && [ "$KEEP_POINTER" = "0" ] && [ -e "$POINTER" ]; then
  rm -f "$POINTER" && necro_ok "Cleared pointer (snapshot file kept)."
fi
necro_ok "Reboot resume complete."
