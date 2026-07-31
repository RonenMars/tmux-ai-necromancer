# Install

### With TPM (recommended)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'RonenMars/tmux-ai-necromancer'
```

Then press `prefix + I` to install. That's it — the autosave daemon starts immediately.

### Manual

```bash
git clone https://github.com/RonenMars/tmux-ai-necromancer \
  ~/.tmux/plugins/tmux-ai-necromancer
run-shell ~/.tmux/plugins/tmux-ai-necromancer/tmux-ai-necromancer.tmux  # in tmux.conf
```

### Dependencies

- `tmux` ≥ 3.0
- `python3` (JSON handling — ships with macOS)
- `jq` (restore/apply — `brew install jq`)
- `go` ≥ 1.21 (only to build the optional TUI)

### Windows (WSL2 only)

There is no native-Windows build. Every script reads its state from `tmux`
(`list-panes`, `set-option -p`, `send-keys`), so the plugin needs a real tmux
server — run it inside a WSL2 distro:

```bash
sudo apt install tmux jq python3
# then install via TPM as above
```

Launch `claude` / `codex` from inside a WSL tmux pane. Agents started in
Windows Terminal / PowerShell are invisible to the plugin: they aren't tmux
panes, and their transcripts live under `C:\Users\<you>\.claude\projects\`
while the adapters resolve `$HOME/.claude/projects` (the WSL home).

Two WSL-specific notes:

- Keep `@necromancer_snapshot_dir` on the WSL filesystem, not `/mnt/c`. The
  autosave and watcher locks rely on `mkdir` being atomic, which drvfs doesn't
  guarantee, and the pane walk is far slower across the mount.
- The menu's *Prep + shutdown* option runs `sudo shutdown -h now`, which halts
  the distro rather than Windows. Run `necro-reboot-prep.sh` on its own, reboot
  Windows, then start WSL → `tmux` → `necro-reboot-resume.sh`. The pinned
  snapshot survives on disk.

The one script that does run natively is `scripts/necro-clean-debug-logs.py`
(`py necro-clean-debug-logs.py`) — see
[`docs/DEBUG_LOGGING.md`](DEBUG_LOGGING.md).
