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
#   @necromancer_log_dir         where script logs live              (default ~/.tmux-ai-necromancer-logs)
#   @necromancer_status          show status-right indicator          (default on)
#   @necromancer_status_label    label for status-right indicator     (default necro)
#   @necromancer_resume_delay      seconds to pause between resume batches (default 5)
#   @necromancer_resume_batch_size resumes launched per batch before pausing (default 1)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$CURRENT_DIR/lib/common.sh"
necro_init_log "$0"

set_default() {
  local opt="$1" def="$2"
  if [ -z "$(tmux show-option -gqv "$opt" 2>/dev/null)" ]; then
    tmux set-option -gq "$opt" "$def"
  fi
}

set_default "@necromancer_interval"        "5"
set_default "@necromancer_max_snapshots"   "20"
set_default "@necromancer_agents"          "claude codex"
set_default "@necromancer_claude_commands" "claude"
set_default "@necromancer_restore_key"     "R"
set_default "@necromancer_log_dir"         "~/.tmux-ai-necromancer-logs"
set_default "@necromancer_status"          "on"
set_default "@necromancer_status_label"    "necro"
set_default "@necromancer_resume_delay"       "5"
set_default "@necromancer_resume_batch_size"  "1"

AUTOSAVE="$CURRENT_DIR/scripts/necro-autosave.sh"

# Append the autosave trigger to status-right if not already present. tmux
# evaluates #(...) on every status refresh; the script self-throttles to the
# configured interval, so this is cheap.
status_right="$(tmux show-option -gqv status-right 2>/dev/null)"
case "$status_right" in
  *necro-autosave.sh*) : ;;  # already wired
  *) tmux set-option -gq status-right "#($AUTOSAVE)$status_right" ;;
esac

WATCHER="$CURRENT_DIR/scripts/necro-watch.sh"

status_right="$(tmux show-option -gqv status-right 2>/dev/null)"
case "$status_right" in
  *necro-watch.sh*) : ;;  # already wired
  *) tmux set-option -gq status-right "#($WATCHER)$status_right" ;;
esac

STATUS="$CURRENT_DIR/scripts/necro-status.sh"

status_right="$(tmux show-option -gqv status-right 2>/dev/null)"
case "$status_right" in
  *necro-status.sh*) : ;;  # already wired
  *) tmux set-option -gq status-right "#($STATUS)$status_right" ;;
esac

# Bind <prefix> <restore_key> to the restore script in a popup.
restore_key="$(tmux show-option -gqv @necromancer_restore_key 2>/dev/null)"
[ -z "$restore_key" ] && restore_key="R"
tmux bind-key "$restore_key" run-shell "tmux display-popup -E '$CURRENT_DIR/scripts/necro-restore.sh; echo; echo Press enter to close; read'"
