# Usage

| Action | Command / key |
|---|---|
| Restore latest snapshot | `prefix + a i` (popup), or `necro-restore.sh` |
| Manual snapshot (no disruption, default) | `necro-snapshot.sh` |
| Manual snapshot (interactive exit-capture) | `necro-snapshot.sh --interactive` |
| Restore a specific snapshot | `necro-restore.sh <file.jsonl>` |
| Dry-run a restore | `necro-restore.sh --dry-run` |
| Before reboot | `necro-reboot-prep.sh` (or `safe-reboot` / `safe-shutdown` aliases) |
| After reboot | `necro-reboot-resume.sh` |
| Check the plugin's health | `necro-doctor.sh` (read-only) |
| Prune idle-shell windows | `necro-prune.sh` (`--dry-run` to preview) |
| Reorganize LIVE panes into sessions | `necro-apply.sh <file.jsonl>` (see note below) |
| Interactive menu | `necro-menu.sh` |
| Session viewer | `make -C tui run` |

Scripts live in `scripts/` inside the plugin dir
(`~/.tmux/plugins/tmux-ai-necromancer/scripts/`). Add it to `PATH` or alias the
ones you use.

`necro-restore.sh` restores a snapshot you choose explicitly. `necro-reboot-resume.sh`
is the reboot wrapper behind `necro-resume`; it finds the pinned reboot snapshot,
ensures tmux is up, then calls restore for you.

`necro-apply.sh` is different: it operates on **live** panes rather than
rebuilding dead ones, moving each recorded pane's window into a destination
session and resuming the agent in place. Use it to reorganize a sprawling
server. Destination comes from the record's `dest_session`, else a routing
table at the top of the script — that table ships with example globs and you
will want to edit it for your own projects before using it.

## Recommended shell aliases

Add these to your shell config (`~/.zshrc`, `~/.bashrc`, `config.fish`, etc.):

```sh
# post-reboot: restore all AI sessions from last snapshot
alias necro-resume='~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-reboot-resume.sh'

# interactive menu: browse/restore/cleanup snapshots, prep for reboot
alias necro-menu='~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-menu.sh'

# prune tmux windows where every pane is an idle shell (keeps agents/editors/builds)
alias necro-prune='~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-prune.sh'

# safe reboot/shutdown: snapshot all live sessions FIRST, then hand off to the OS.
# Use these instead of the Apple menu / system shutdown — see docs/TROUBLESHOOTING.md.
alias safe-reboot='~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-reboot-prep.sh && sudo reboot'
alias safe-shutdown='~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-reboot-prep.sh && sudo shutdown -h now'
```

> **Why `safe-reboot`?** The autosave runs every 5 minutes. If you close
> sessions manually before rebooting — or macOS starts killing processes during
> shutdown — the final autosave captures only what was still alive at that
> moment. `safe-reboot` runs `necro-reboot-prep.sh` first, snapshotting
> everything while all sessions are still open, then reboots. See
> [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) for details.
