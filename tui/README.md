# necromancer-tui

A terminal UI (Go + [Bubble Tea](https://github.com/charmbracelet/bubbletea))
for `tmux-ai-necromancer`. Walks the running tmux server, joins each pane
against the latest snapshot in the snapshot dir, and renders a table of
sessions, panes, agents, and captured session ids.

```bash
make run        # launch the viewer
make build      # -> ./necromancer-tui
make test       # unit tests
```

Snapshot dir resolution honors `$NECROMANCER_SNAPSHOT_DIR`, defaulting to
`~/.claude/tmux-snapshots`.

Capture mode can exit supported agents on demand (`claude` via `/exit`, `codex`
via `/quit`) and append a snapshot record for restore. Use `make run-dry` to
exercise that flow without sending keys to tmux.

## Debug logging

The TUI shares the plugin's opt-in debug controls: set
`@necromancer_debug` to `on`, or invoke it with `NECROMANCER_DEBUG=1`.
It appends JSONL lifecycle events to `~/.tmux-ai-necromancer-logs/tui.log`
(override with `@necromancer_log_dir` or `NECROMANCER_LOG_DIR`). Events cover
loading, review and exit actions, tmux calls, snapshot reads/writes, and Codex
session lookup. Scrollback and transcript bodies are never logged.
