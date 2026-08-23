# Configuration

**All optional** — the plugin defaults every one of these itself, so the single
`set -g @plugin` line from [Install](INSTALL.md#with-tpm-recommended) is enough on its own.
The values below are the defaults; pasting the block verbatim changes nothing.
Override only what you want to change, in `~/.tmux.conf` **before** the line that
loads TPM.

These lines belong in `~/.tmux.conf`, not in a shell. Pasted at a shell prompt
they hit bash's or zsh's own `set` builtin, which accepts them, does nothing
useful, and prints no error — the option stays unset with no sign of it. To set
one from a shell, prefix the command with `tmux` (`tmux set -g @necromancer_interval '5'`);
that applies to the running server only, so put it in `~/.tmux.conf` as well if
you want it to survive a restart. See
[Troubleshooting → A `@necromancer_*` option has no effect](TROUBLESHOOTING.md#a-necromancer_-option-has-no-effect).

```tmux
set -g @necromancer_interval         '5'             # minutes between autosaves
set -g @necromancer_max_snapshots    '288'           # snapshot files to keep (~24h at 5m interval)
set -g @necromancer_agents           'claude codex'  # which agents to track
set -g @necromancer_restore_key      'ai'            # prefix chord for restore popup (two letters → prefix+a then i; a single key name still works)
set -g @necromancer_snapshot_dir     '~/.claude/tmux-snapshots'  # where snapshots live
set -g @necromancer_log_dir         '~/.tmux-ai-necromancer-logs'  # script logs
set -g @necromancer_debug           'off'           # write per-command debug logs
set -g @necromancer_debug_log_max_bytes '20971520'  # 20 MiB — cap per debug log file before it rotates to .old (0 disables)
set -g @necromancer_autosave_tick   '60'            # autosave daemon polling interval in seconds
set -g @necromancer_watch_tick      '1'             # watcher daemon polling interval in seconds
set -g @necromancer_limit_check_interval '60'       # seconds between rate-limit auto-saves (0 disables; or NECROMANCER_LIMIT_CHECK_INTERVAL)
set -g @necromancer_claude_commands  'claude'        # space-separated command names for Claude Code (add aliases, e.g. 'claude cc')
set -g @necromancer_codex_commands   'codex codex-*' # same, for Codex; entries are globs (the default covers the truncated native binary)
set -g @necromancer_resume_delay        '5'  # seconds to pause between resume batches
set -g @necromancer_resume_batch_size   '1'  # resumes launched per batch before pausing
set -g @necromancer_resume_message      'continue'  # text sent into each pane after resume ('' disables)
set -g @necromancer_resume_message_delay '8'  # seconds to wait before sending that message
set -g @necromancer_resume_start_delay   '1'  # seconds to wait after creating a fresh pane before the resume command itself
set -g @necromancer_logs_scheduled_cleanup ''  # how often to clean debug logs: a duration (30m, 12h, 7d, 1d12h) or cron ('0 3 * * *'); empty/off = never
set -g @necromancer_logs_max_age           ''  # scheduled cleanup keeps logs younger than this duration; empty = remove them all
```

The two `logs_` options are the only ones that delete anything on a timer, and
both default to empty, so nothing is cleaned until you configure them. See
[Debug logging → Scheduled cleanup](DEBUG_LOGGING.md#scheduled-cleanup) for the
supported cron subset and the one-off `--older-than` flag.

Two more options govern restore safety —
`@necromancer_max_claude_transcript_bytes` and `@necromancer_unsafe_cwd_patterns`.
They're documented with their defaults in `necro-restore.sh --help` and under
[Troubleshooting](TROUBLESHOOTING.md).

## Applying a config change later

Editing `~/.tmux.conf` alone does nothing — tmux options only change when the
file is re-read. How much you need to reload depends on the option:

| Options | To apply |
|---|---|
| Everything except the two below | `tmux source-file ~/.tmux.conf` — scripts read these at each run |
| `@necromancer_restore_key` | Same, then re-run the plugin file (`prefix + I`, or restart tmux). The old key (and any previous chord's first key) stays bound until the server restarts. Two letters (`ai` or `a i`) bind a key-table chord; a single key name (`R`, `N`, `C-r`, …) binds the classic one-shot form. |
| `@necromancer_autosave_tick`, `@necromancer_watch_tick` | The daemons read their tick once at startup and a re-source is a no-op while they hold their lock. Restart them: `pkill -9 -f 'necro-.*-daemon\.sh'; tmux source-file ~/.tmux.conf` |

`-9` is deliberate in that last one. On a plain `TERM` the daemon's cleanup trap
is deferred until its in-flight `sleep` returns (up to a full tick), so the lock
is still held when you re-source and no new daemon starts. `SIGKILL` leaves a
stale lock instead, which the next daemon detects (the recorded pid no longer
matches a daemon process) and reclaims immediately.

`@necromancer_resume_delay` / `@necromancer_resume_batch_size` govern
`necro-restore.sh` and `necro-apply.sh`: launching several `claude --resume`
processes back-to-back (each reads a transcript and hits the API for initial
context) can spike CPU/memory enough to stall the machine on a large restore.
By default one resume launches, then the script pauses 5s before the next.
Raise `@necromancer_resume_batch_size` to let a few resumes fire together
before each pause, or override per-invocation with `--resume-delay N` /
`--resume-batch-size N` (or `NECROMANCER_RESUME_DELAY` /
`NECROMANCER_RESUME_BATCH_SIZE`).

After each resume, both scripts send a follow-up message into the pane —
`@necromancer_resume_message` (default `continue`) — so the resumed agent picks
up its in-progress task without you retyping anything. It waits
`@necromancer_resume_message_delay` seconds first (default 8) so the message
lands at the prompt, not on the agent's boot screen. Set the message to an empty
string (`''`, or `--resume-message ''`) to disable it. Caveat: if the last turn
ended by asking *you* a question, an auto-sent `continue` answers it blindly —
disable the message when that matters. Also configurable via `--resume-message` /
`--resume-message-delay` and `NECROMANCER_RESUME_MESSAGE` /
`NECROMANCER_RESUME_MESSAGE_DELAY`.

`necro-restore.sh` also waits `@necromancer_resume_start_delay` seconds
(default 1) after creating a fresh pane before sending the resume command
itself — the pane's shell (zsh init, plugin managers, etc.) isn't necessarily
ready for input the instant the pane exists, and keystrokes sent too early are
dropped rather than queued, leaving the pane empty with the agent never
resumed. Raise it on a slow shell via `--resume-start-delay N` or
`NECROMANCER_RESUME_START_DELAY`. `necro-apply.sh` doesn't need this option —
it resumes into panes that were already live before the script ran, not
freshly-spawned ones.

Rate-limit auto-save: the watcher scans for Claude "session limit" / Codex
"usage limit" banners at most once per `@necromancer_limit_check_interval`
seconds (default 60; set to `0` or `NECROMANCER_LIMIT_CHECK_INTERVAL=0` to
disable). Matching panes are written to a `*.rate-limited.jsonl` snapshot and
stamped `@necro_limit_saved` so the same event is not re-saved every minute.
Manual: `necro-snapshot.sh --rate-limited` or menu `[6]`.

These captures rotate like any other snapshot: they count toward
`@necromancer_max_snapshots` and age out with the rest, so a save from menu
`[6]` is not kept forever — at the default 288 / 5 min that is roughly 24 hours.
Pin one as the reboot target to exempt it, or copy it out of the snapshot dir if
you need it longer.

Snapshots also record each pane's `window_layout`, and restore replays it with
`select-layout` so a multi-pane window comes back with its original arrangement
and sizes — but only when the restored pane count matches the snapshot's, so a
partially-restored or user-modified window is never reshaped. The active pane,
the session's active window, and a zoomed pane (`zoomed` / `pane_active` /
`window_active` record flags) are restored the same way — only for windows the
run created, and zoom is re-applied after the layout replay since
`select-layout` unzooms.

The snapshot dir defaults to `~/.claude/tmux-snapshots` (so it stays compatible
with prior Claude-only setups). Override with the option above or the
`NECROMANCER_SNAPSHOT_DIR` env var.

Set `@necromancer_debug` to `on` while investigating a problem. Each script
then writes structured lifecycle and action events to
`~/.tmux-ai-necromancer-logs/<script>.log`. Override the log location with
`@necromancer_log_dir` or `NECROMANCER_LOG_DIR`; set
`NECROMANCER_DEBUG=1` to enable it for one command. Each log file is capped at
`@necromancer_debug_log_max_bytes` (default 20 MiB — `0` disables rotation)
so it can't grow unbounded even with no scheduled cleanup configured;
override with `NECROMANCER_DEBUG_LOG_MAX_BYTES`. See the
[debug logging guide](DEBUG_LOGGING.md) for cleanup, cross-platform use,
and expected disk usage — the growth estimate there scales worse than
linearly with pane count, so don't extrapolate it past a handful of panes.

The shell logs also include lifecycle records in the form
`event phase=<phase> action=<action>`, covering run startup, phases, records,
tmux mutations, skips, completions, and failures. The TUI writes matching
structured JSONL events to `~/.tmux-ai-necromancer-logs/tui.log` while debug
mode is enabled; it never writes scrollback or transcript contents.
