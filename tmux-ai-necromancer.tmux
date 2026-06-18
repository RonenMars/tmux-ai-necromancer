#!/usr/bin/env bash
# tmux-ai-necromancer.tmux — TPM entrypoint.
#
# Loaded by tmux-plugins/tpm on tmux start. Wires the autosave trigger into
# status-right (mirroring tmux-continuum) and binds a restore key.
#
# User-tunable options (set BEFORE the run-shell that sources tpm, in tmux.conf):
#   @necromancer_interval        minutes between autosaves            (default 5)
#   @necromancer_max_snapshots   autosave files to keep               (default 20)
#   @necromancer_agents          space-separated agent list           (default "claude codex")
#   @necromancer_snapshot_dir    where snapshots live  (default ~/.claude/tmux-snapshots)
#   @necromancer_restore_key     prefix key to run restore            (default R)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set_default() {
  local opt="$1" def="$2"
  if [ -z "$(tmux show-option -gqv "$opt" 2>/dev/null)" ]; then
    tmux set-option -gq "$opt" "$def"
  fi
}

set_default "@necromancer_interval"      "5"
set_default "@necromancer_max_snapshots" "20"
set_default "@necromancer_agents"        "claude codex"
set_default "@necromancer_restore_key"   "R"

AUTOSAVE="$CURRENT_DIR/scripts/necro-autosave.sh"

# Append the autosave trigger to status-right if not already present. tmux
# evaluates #(...) on every status refresh; the script self-throttles to the
# configured interval, so this is cheap.
status_right="$(tmux show-option -gqv status-right 2>/dev/null)"
case "$status_right" in
  *necro-autosave.sh*) : ;;  # already wired
  *) tmux set-option -gq status-right "#($AUTOSAVE)$status_right" ;;
esac

# Bind <prefix> <restore_key> to the restore script in a popup.
restore_key="$(tmux show-option -gqv @necromancer_restore_key 2>/dev/null)"
[ -z "$restore_key" ] && restore_key="R"
tmux bind-key "$restore_key" run-shell "tmux display-popup -E '$CURRENT_DIR/scripts/necro-restore.sh; echo; echo Press enter to close; read'"
