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
