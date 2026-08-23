# Debug logging

Debug logging is opt-in. Enable it in tmux only while investigating a problem:

```tmux
set -g @necromancer_debug 'on'
```

Set it back to `off` when finished. The one-command alternative is
`NECROMANCER_DEBUG=1`; it does not change the tmux configuration.

## What is recorded

Shell scripts append structured `event phase=<phase> action=<action>` records
to `~/.tmux-ai-necromancer-logs/<script>.log`. The TUI appends structured JSONL
events to `~/.tmux-ai-necromancer-logs/tui.log`. These logs describe lifecycle,
phase, action, skip, completion, and failure events; they do not record pane
scrollback or agent transcripts.

The watcher's `pin_uuid` event also records `source=argv|scrollback|cursor-pop`
— which of the three resolvers produced the pinned id — and the `min_epoch`
stamp that was in effect (the pane's first-seen time, which the cursor-pop
fallback filters stale transcripts against). Without it, diagnosing a mispinned
session means reconstructing resolver order from transcript mtimes by hand.

Debug logging stays opt-in by design. Each log file is capped at
`@necromancer_debug_log_max_bytes` (default 20 MiB — see
[Automatic rotation](#automatic-rotation) below) so a forgotten `on` can't grow
one file without bound, but nothing deletes old generations on its own unless
you configure the [scheduled cleanup](#scheduled-cleanup). Turn debug mode on
when investigating, off when done.

Set `@necromancer_log_dir` or `NECROMANCER_LOG_DIR` to use a different log
directory. `autosave.log` remains in the snapshot directory, which defaults to
`~/.claude/tmux-snapshots` and can be overridden with
`NECROMANCER_SNAPSHOT_DIR`.

## Approximate daily growth

The table below assumes a 1-second watcher tick, a 5-minute autosave interval,
debug mode enabled, and **10 agent panes**. It excludes the TUI, whose usage
depends on how actively it is used.

| Log source | Approximate daily growth (10 panes) | What drives it |
| --- | ---: | --- |
| Pane watcher | ~3.5 MB | One structured pass per watcher tick |
| Autosave | ~2.5–3 MB | Snapshot eligibility and save events every 5 minutes |
| Snapshot and autosave summary | ~0.3 MB | Snapshot completion and summary records |
| **Total, without TUI** | **~6–7 MB/day** | Typical active tmux usage |

**This does not scale linearly with pane count — it scales worse.** The
watcher's per-tick cost grows with pane count (invariant 15 keeps it O(1) in
*tmux calls*, not in log bytes written per pane), and each additional pane
adds its own scrape/pin events every tick. Measured on a real server at 27
panes: `necro-watch.log` alone reached **158 MB in 38 minutes** — roughly
**6 GB/day**, about 285× the 10-pane total above. Don't extrapolate the table
linearly past a handful of panes; if you're running a large fleet of agent
panes with debug on, watch the actual file size (`ls -lh
~/.tmux-ai-necromancer-logs/`) rather than trusting this estimate.

## Automatic rotation

Regardless of pane count, each individual log file is capped at
`@necromancer_debug_log_max_bytes` bytes (default 20 MiB, checked once per
script invocation — once per watcher tick for `necro-watch.log`). Crossing the
cap renames the file to `<name>.log.old`, overwriting any previous `.old`, and
starts a fresh one — so a single log name never grows past roughly 2x the cap
even if you leave debug mode on and never configure scheduled cleanup.
`.old` files are ordinary files: `necro-clean-debug-logs.sh` /
`necro-clean-debug-logs.py` sweep them the same as the active log, and
[scheduled cleanup](#scheduled-cleanup) removes them by age too. Override the
cap with `NECROMANCER_DEBUG_LOG_MAX_BYTES` or
`@necromancer_debug_log_max_bytes`; `0` disables rotation entirely.

This bounds worst-case disk usage; it does not replace the growth estimate
above for planning how much history you'll actually have on disk at any given
moment — a busier watcher rotates more often and keeps less total history.

## Marking a repro

Before reproducing a bug, stamp a labelled separator into every log file so the
events that follow are easy to find later:

```bash
scripts/necro-log-divider.sh "scenario 3"
```

It appends `~~~~~~~ scenario 3 ~~~~~~~~` to every `*.log` in the log directory
plus `autosave.log` in the snapshot directory. With no argument it prompts for
the label. It refuses to run while debug logging is off.

## Cleanup

Use the shell helper when tmux is available:

```bash
scripts/necro-clean-debug-logs.sh --dry-run
scripts/necro-clean-debug-logs.sh
```

For Windows, Linux, or macOS, use the standalone Python 3 utility. It does not
require tmux or a Unix shell:

```bash
# macOS / Linux
python3 scripts/necro-clean-debug-logs.py --dry-run
python3 scripts/necro-clean-debug-logs.py

# Windows
py scripts/necro-clean-debug-logs.py --dry-run
py scripts/necro-clean-debug-logs.py
```

It removes `*.log` files from the configured debug-log directory and only
`autosave.log` from the configured snapshot directory. It never removes
snapshots or directories containing other files.

### Keeping recent logs

`--older-than <spec>` keeps anything younger than the given age and removes the
rest. `<spec>` is a duration built from `d`, `h`, `m`, and `s` parts:

```bash
scripts/necro-clean-debug-logs.sh --older-than 7d        # keep the last week
scripts/necro-clean-debug-logs.sh --older-than 12h
scripts/necro-clean-debug-logs.sh --older-than 1d12h30m  # parts combine
scripts/necro-clean-debug-logs.sh --older-than 7d --dry-run
```

Without the flag every log goes, which is the original behaviour. A malformed
spec is rejected and nothing is removed.

The Python utility takes the same flag with the same spec syntax:

```bash
python3 scripts/necro-clean-debug-logs.py --older-than 7d
py scripts/necro-clean-debug-logs.py --older-than 7d --dry-run
```

It has no `--scheduled` — that flag is the tmux daemon's gate, and the Python
utility exists for machines with no tmux. Schedule it with the platform's own
scheduler (`cron`, `launchd`, Task Scheduler) pointed at `--older-than`.

## Scheduled cleanup

Set `@necromancer_logs_scheduled_cleanup` and the autosave daemon runs the
cleanup for you. The value is either a duration ("every so often") or a
five-field cron expression ("at these times"):

```tmux
set -g @necromancer_logs_scheduled_cleanup '7d'         # every 7 days
set -g @necromancer_logs_scheduled_cleanup '12h'        # twice a day
set -g @necromancer_logs_scheduled_cleanup '90m'        # every 90 minutes
set -g @necromancer_logs_scheduled_cleanup '0 3 * * *'  # daily at 03:00
set -g @necromancer_logs_scheduled_cleanup '0 4 * * 0'  # Sundays at 04:00
set -g @necromancer_logs_scheduled_cleanup '*/30 * * * *'

set -g @necromancer_logs_max_age '3d'   # keep the last 3 days on each run
```

Those `set -g` lines go in `~/.tmux.conf`. At a shell prompt they silently reach
the shell's own `set` builtin instead, so prefix them with `tmux` there — see
[Troubleshooting → A `@necromancer_*` option has no effect](TROUBLESHOOTING.md#a-necromancer_-option-has-no-effect).

`@necromancer_logs_max_age` is the `--older-than` value scheduled runs use; leave
it unset and a scheduled run removes every log. The environment variables
`NECROMANCER_LOGS_SCHEDULED_CLEANUP` and `NECROMANCER_LOGS_MAX_AGE` override both
options for a single invocation.

Unset, `off`, or `0` disables scheduling — that is the default, so nothing is
deleted on a schedule until you ask for it.

Details worth knowing:

- The schedule is evaluated once per autosave-daemon tick
  (`@necromancer_autosave_tick`, 60s by default), so a cron expression finer than
  one minute gains nothing.
- The last run is recorded in `.last-cleanup` inside the log directory. The
  first tick after you configure a schedule writes that stamp and cleans
  nothing — the clock starts then, so enabling the option never deletes logs on
  the spot.
- Cron backlog is capped at 24 hours. If the machine was asleep across a
  scheduled time, the run happens at the next matching occurrence rather than
  immediately on wake.
- Supported cron syntax is `*`, `a-b`, `a,b,c`, and `*/n`, in the standard
  `minute hour day-of-month month day-of-week` order. Day-of-week accepts `0`
  and `7` for Sunday. Names (`MON`, `JAN`) and `@daily`-style shorthands are not
  supported — use a duration instead.
- Cleanup unlinks files that long-running daemons may still hold open. Those
  daemons keep writing to the removed inode until they restart, so the newest
  daemon-lifecycle events can be lost. Per-tick scripts (the watcher, snapshot,
  and autosave logs, which are all the large ones) reopen on every run and are
  unaffected.

To run the same cleanup outside tmux — from `cron`, `launchd`, or Task Scheduler
— call either script directly instead; `--scheduled` is only for the daemon:

```bash
scripts/necro-clean-debug-logs.sh --older-than 7d
python3 scripts/necro-clean-debug-logs.py --older-than 7d   # no tmux needed
```
