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

Set `@necromancer_log_dir` or `NECROMANCER_LOG_DIR` to use a different log
directory. `autosave.log` remains in the snapshot directory, which defaults to
`~/.claude/tmux-snapshots` and can be overridden with
`NECROMANCER_SNAPSHOT_DIR`.

## Approximate daily growth

The estimate below assumes a 1-second watcher tick, a 5-minute autosave
interval, and debug mode enabled. It excludes the TUI, whose usage
depends on how actively it is used.

| Log source | Approximate daily growth | What drives it |
| --- | ---: | --- |
| Pane watcher | ~3.5 MB | One structured pass per watcher tick |
| Autosave | ~2.5–3 MB | Snapshot eligibility and save events every 5 minutes |
| Snapshot and autosave summary | ~0.3 MB | Snapshot completion and summary records |
| **Total, without TUI** | **~6–7 MB/day** | Typical active tmux usage |

At that rate, leaving debug mode on without cleanup would use roughly
250–300 MB per month. The logs use disk space and a small amount of additional
file I/O only; they do not change snapshot contents, stop panes, or inspect
agent transcripts.

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
