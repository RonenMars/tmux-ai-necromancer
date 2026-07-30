#!/usr/bin/env bash
# tmux-ai-necromancer.tmux — TPM entrypoint.
#
# Loaded by tmux-plugins/tpm on tmux start. Starts the autosave and watcher
# daemons, removes legacy status-right hooks, and binds restore.
#
# User-tunable options (set BEFORE the run-shell that sources tpm, in tmux.conf):
#   @necromancer_interval        minutes between autosaves            (default 5)
#   @necromancer_max_snapshots   autosave files to keep               (default 20)
#   @necromancer_agents          space-separated agent list           (default "claude codex")
#   @necromancer_snapshot_dir    where snapshots live  (default ~/.claude/tmux-snapshots)
#   @necromancer_restore_key     prefix key to run restore            (default R)
#   @necromancer_log_dir         where script logs live              (default ~/.tmux-ai-necromancer-logs)
#   @necromancer_debug           write per-command debug logs        (default off)
#   @necromancer_autosave_tick   daemon polling interval in seconds   (default 60)
#   @necromancer_watch_tick      watcher polling interval in seconds  (default 1)
#   @necromancer_resume_delay      seconds to pause between resume batches (default 5)
#   @necromancer_resume_batch_size resumes launched per batch before pausing (default 1)
#   @necromancer_claude_commands   command names that mean Claude Code    (default "claude")
#
# Read by the scripts themselves, not defaulted here (in-code fallbacks):
#   @necromancer_resume_message       text sent into a pane after resume (default "continue")
#   @necromancer_resume_message_delay seconds to wait before that message  (default 8)
#   @necromancer_max_claude_transcript_bytes  resume size ceiling   (default 52428800)
#   @necromancer_unsafe_cwd_patterns  globs restore refuses to rebuild (see --help)

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
set_default "@necromancer_debug"           "off"
set_default "@necromancer_autosave_tick"   "60"
set_default "@necromancer_watch_tick"      "1"
set_default "@necromancer_resume_delay"       "5"
set_default "@necromancer_resume_batch_size"  "1"
necro_log_event "plugin" "configure_defaults" "debug=$(necro_tmux_option @necromancer_debug off)"

DAEMON="$CURRENT_DIR/scripts/necro-autosave-daemon.sh"
tmux run-shell -b "$DAEMON"
necro_log_event "plugin" "start_autosave_daemon" "script=$DAEMON"

WATCH_DAEMON="$CURRENT_DIR/scripts/necro-watch-daemon.sh"
tmux run-shell -b "$WATCH_DAEMON"
necro_log_event "plugin" "start_watch_daemon" "script=$WATCH_DAEMON"

# Remove hooks installed by older plugin versions. Both watcher and status are
# now scheduled by background daemons, so they must not run during status-bar
# rendering. The autosave hook is removed too because its daemon is independent.
status_right="$(tmux show-option -gqv status-right 2>/dev/null)"
clean_status_right="$(printf '%s' "$status_right" | sed -E 's@#[(][^)]*/necro-(status|watch|autosave)[.]sh[)]@@g')"
if [ "$clean_status_right" != "$status_right" ]; then
  tmux set-option -gq status-right "$clean_status_right"
  necro_log_event "plugin" "remove_legacy_status_hooks"
fi

# Bind <prefix> <restore_key> to the restore script in a popup.
restore_key="$(tmux show-option -gqv @necromancer_restore_key 2>/dev/null)"
[ -z "$restore_key" ] && restore_key="R"
tmux bind-key "$restore_key" run-shell "tmux display-popup -E '$CURRENT_DIR/scripts/necro-restore.sh; echo; echo Press enter to close; read'"
necro_log_event "plugin" "bind_restore" "key=$restore_key"
