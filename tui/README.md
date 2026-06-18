# necromancer-tui

A read-only terminal UI (Go + [Bubble Tea](https://github.com/charmbracelet/bubbletea))
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

Read-only: it does not mutate tmux or send keys. Use the bash scripts
(`necro-restore.sh`, etc.) for actions.
