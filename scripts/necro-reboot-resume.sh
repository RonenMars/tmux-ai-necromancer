#!/usr/bin/env bash
# =============================================================================
# necro-reboot-resume.sh — re-open AI agents in each pane after a reboot.
#
# Pairs with necro-reboot-prep.sh. Flow:
#   1. Resolve the pinned snapshot (latest-for-reboot) or an explicit arg.
#   2. Ensure the tmux server is up (trigger tmux-continuum restore if present).
#   3. Run necro-restore.sh against the snapshot — idempotently recreates
#      sessions/windows and resumes each agent.
#
# Run from OUTSIDE tmux (fresh terminal).
#
# Usage:
#   necro-reboot-resume.sh                  use pinned snapshot
#   necro-reboot-resume.sh <snapshot.jsonl> use a specific snapshot
#   necro-reboot-resume.sh --dry-run        show plan, change nothing
#   necro-reboot-resume.sh --keep-pointer   don't delete pointer on success
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

SNAP_DIR="$(necro_snapshot_dir)"
POINTER="$SNAP_DIR/latest-for-reboot"
RESURRECT_RESTORE="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

SNAPSHOT=""; DRY_RUN=0; KEEP_POINTER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1; shift ;;
    --keep-pointer) KEEP_POINTER=1; shift ;;
    -h|--help)      sed -n '/^# =\{3,\}/,/^# =\{3,\}/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) necro_err "Unknown flag: $1"; exit 2 ;;
    *)  SNAPSHOT="$1"; shift ;;
  esac
done

if [ -n "${TMUX:-}" ]; then
  necro_err "You're inside tmux. Run from a fresh terminal."; exit 1
fi
command -v tmux >/dev/null || { necro_err "tmux not installed."; exit 1; }

if [ -z "$SNAPSHOT" ]; then
  if [ ! -e "$POINTER" ]; then
    necro_err "No pointer at $POINTER. Pass a snapshot path explicitly, or run"
    necro_err "necro-restore.sh which auto-picks the latest autosave."
    exit 1
  fi
  SNAPSHOT="$(readlink -f "$POINTER" 2>/dev/null || cat "$POINTER")"
fi
[ -f "$SNAPSHOT" ] || { necro_err "Snapshot not found: $SNAPSHOT"; exit 1; }

necro_hr
necro_say "Necromancer reboot resume"
echo "  Snapshot: $SNAPSHOT"
echo "  Dry-run:  $DRY_RUN"
necro_hr

# ── Phase 1: ensure tmux server + layout ────────────────────────────────────
server_up() { tmux list-sessions >/dev/null 2>&1; }
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
necro_hr

# ── Phase 2: restore ────────────────────────────────────────────────────────
necro_say "Phase 2: necro-restore.sh"
restore_flags=(); (( DRY_RUN )) && restore_flags+=(--dry-run)
"$SELF_DIR/necro-restore.sh" "${restore_flags[@]}" "$SNAPSHOT"
necro_hr

if [ "$DRY_RUN" = "0" ] && [ "$KEEP_POINTER" = "0" ] && [ -e "$POINTER" ]; then
  rm -f "$POINTER" && necro_ok "Cleared pointer (snapshot file kept)."
fi
necro_ok "Reboot resume complete."
