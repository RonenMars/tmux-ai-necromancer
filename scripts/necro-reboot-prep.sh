#!/usr/bin/env bash
# =============================================================================
# necro-reboot-prep.sh — capture live AI-agent state + force tmux save before reboot.
#
# Composes the pipeline (orchestration only):
#   1. necro-snapshot.sh   — walk panes, capture session ids (per agent)
#   2. necro-context.sh    — enrich with conversation previews
#   3. tmux-resurrect save — persist window/pane layout (if installed)
#   4. Pin the snapshot as the "next reboot" target via a stable pointer file
#
# Run from OUTSIDE the tmux server being snapshotted (a fresh terminal not
# attached). The interactive snapshot uses `tmux switch-client`.
#
# Usage:
#   necro-reboot-prep.sh                # snapshot (--idle-only) + enrich + save
#   necro-reboot-prep.sh --yes          # auto-exit every live agent and capture
#   necro-reboot-prep.sh --interactive  # prompt per live agent (default is idle-only)
#   necro-reboot-prep.sh --no-enrich    # skip context enrichment
#   necro-reboot-prep.sh --dry-run      # show plan, change nothing
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
RESURRECT_SAVE="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"

# Default to idle-only (zero disruption); --interactive / --yes opt into exits.
MODE="idle-only"; ENRICH=1; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --idle-only)   MODE="idle-only"; shift ;;
    --interactive) MODE="interactive"; shift ;;
    --yes|-y)      MODE="yes"; shift ;;
    --no-enrich)   ENRICH=0; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     sed -n '/^# =\{3,\}/,/^# =\{3,\}/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) necro_err "Unknown flag: $1"; exit 2 ;;
  esac
done

if [ -n "${TMUX:-}" ]; then
  necro_err "You're inside tmux (\$TMUX set). Run from a fresh terminal."
  exit 1
fi
command -v tmux >/dev/null || { necro_err "tmux not installed."; exit 1; }
tmux list-sessions >/dev/null 2>&1 || { necro_err "No tmux server running."; exit 1; }

necro_hr
necro_say "Necromancer reboot prep"
echo "  Mode:    $MODE"
echo "  Enrich:  $ENRICH"
echo "  Dry-run: $DRY_RUN"
echo "  Panes:   $(tmux list-panes -a 2>/dev/null | wc -l | tr -d ' ')"
necro_hr

# ── Phase 1: snapshot ───────────────────────────────────────────────────────
necro_say "Phase 1: necro-snapshot.sh"
snap_flags=()
case "$MODE" in
  idle-only) snap_flags+=(--idle-only) ;;
  yes)       snap_flags+=(--yes) ;;
esac
if (( DRY_RUN )); then
  necro_say "DRY-RUN: would run necro-snapshot.sh ${snap_flags[*]}"
  SNAPSHOT_FILE="<would-be-created>"
else
  "$SELF_DIR/necro-snapshot.sh" "${snap_flags[@]}"
  if [ "$MODE" = "idle-only" ]; then
    SNAPSHOT_FILE="$(/bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null | head -1)"
  else
    SNAPSHOT_FILE="$(/bin/ls -t "$SNAP_DIR"/*.jsonl 2>/dev/null | grep -v idle-only | grep -v enriched | head -1)"
  fi
  [ -f "$SNAPSHOT_FILE" ] || { necro_err "No snapshot produced."; exit 1; }
  necro_ok "Snapshot: $SNAPSHOT_FILE"
fi
necro_hr

# ── Phase 2: enrich ─────────────────────────────────────────────────────────
TARGET="$SNAPSHOT_FILE"
if (( ENRICH )) && [ "$DRY_RUN" = "0" ]; then
  necro_say "Phase 2: necro-context.sh"
  "$SELF_DIR/necro-context.sh" "$SNAPSHOT_FILE" || true
  enriched="${SNAPSHOT_FILE%.jsonl}.enriched.jsonl"
  [ -f "$enriched" ] && { TARGET="$enriched"; necro_ok "Enriched: $enriched"; }
  necro_hr
fi

# ── Phase 3: tmux-resurrect save (optional) ─────────────────────────────────
if [ -x "$RESURRECT_SAVE" ]; then
  necro_say "Phase 3: tmux-resurrect save"
  if (( DRY_RUN )); then necro_say "DRY-RUN: would run $RESURRECT_SAVE"
  else "$RESURRECT_SAVE" >/dev/null && necro_ok "Layout saved."; fi
  necro_hr
else
  necro_warn "tmux-resurrect not found — skipping layout save (sessions still restore via snapshot)."
fi

# ── Phase 4: pin pointer ────────────────────────────────────────────────────
necro_say "Phase 4: pin snapshot as latest-for-reboot"
if (( DRY_RUN )); then necro_say "DRY-RUN: would write $POINTER → $TARGET"
else ln -sfn "$TARGET" "$POINTER" && necro_ok "Pointer: $POINTER → $(readlink "$POINTER")"; fi
necro_hr

necro_ok "Reboot prep complete. Now: sudo reboot → then necro-reboot-resume.sh"
