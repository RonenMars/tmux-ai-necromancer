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

## Reboot runbook

### Do not start tmux first

`necro-reboot-resume.sh` runs `tmux start-server` itself, and refuses to run
when `$TMUX` is set. A bare `tmux` before it creates an empty session `0` and
puts you inside one, which trips that guard. So from a **plain shell, not
attached to tmux**:

```sh
necro-resume              # starts the server AND restores, in that order
tmux attach -t <session>  # only now attach
```

It prompts `Clean up idle tmux windows before resuming? [y/N]` — answer `N`
here; see [The cleanup prompt](#the-cleanup-prompt) below for why.

Ended up inside tmux anyway? `necro-menu` calls `necro-restore.sh` directly
with no `$TMUX` guard and works from either side.

### The cleanup prompt

Cleanup runs in **phase 1, before restore**, against whatever is on the server
at that moment.

**Post-reboot the answer is `N`.** The server is empty by then, so cleanup has
nothing to do — it is a no-op that only adds a chance to kill something you
wanted. The one case where it is not a no-op: if `tmux start-server` does not
bring sessions back, the script falls through to tmux-resurrect, and cleanup
would kill resurrect's freshly-spawned idle windows just before restore
rebuilds them. Harmless — restore claims unmarked resurrect panes anyway — but
pointless churn.

**`y` is for a populated server**, not a fresh one: you ran resume once, poked
around, and want a clean slate before re-running.

What it kills, so you can judge it yourself (`cleanup_empty_windows` in
`necro-reboot-resume.sh`): a window dies only when *every* pane's `pane_pid`
has zero children by `pgrep -P`. A running agent is a child of its shell, so
agent panes read busy and survive — likewise vim, builds, anything with a
child. A pane whose agent exited, leaving a bare prompt, reads idle and dies.
That is the intent.

The edge it gets wrong: a pane where a process *replaced* the shell
(`exec htop`) has no children, so it reads idle and is killed despite being
busy. Rare, but it is why `N` is the right default.

To actually clean up, do it separately where you get a preview:

```sh
necro-prune --dry-run
```

Same child-process logic, but it prints the kill list before acting. The
prompt inside `necro-resume` gives you no preview unless the whole run is
`--dry-run`.

### What a healthy run looks like

```
Records: 6
windows added: 4, reused: 0, agents resumed: 4, resume skipped: 2
```

`agents resumed` is the number that matters. `resume skipped` counts records
with no agent or no UUID — plain shells, which is correct and not a failure.
Budget a few seconds per agent: resumes are paced
`@necromancer_resume_delay` apart, each followed by the post-resume message.

### Rebooting without `safe-reboot`

Usually fine, because the autosave daemon is a **child of the tmux server** —
when the server dies at reboot the daemon dies with it and cannot write a
post-collapse snapshot. What you give up is bounded:

- the newest snapshot is up to `@necromancer_interval` (5 min) stale, so a
  session started inside that window is not in it
- no conversation-preview enrichment (that is `necro-reboot-prep.sh`'s
  `necro-context.sh` pass)
- the snapshot is not pinned, so rotation can eventually age it out — matters
  only if you leave the machine up for a day before resuming

Note what "stale" costs: a snapshot records *which* conversation lived *where*,
not the conversation itself. Transcripts are files under `~/.claude/projects/`
and survive reboot untouched, so five stale minutes lose five minutes of tmux
topology, not five minutes of work.

The genuinely dangerous case is the opposite one: **killing or draining
sessions while the machine stays up**. There the daemon is still alive and
keeps ticking, overwriting good history with progressively emptier snapshots —
see the empty-latest-autosave entry in
[docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md).

Before trusting newest-wins after an unprepped reboot:

```sh
ls -1t ~/.claude/tmux-snapshots/*.jsonl | head -1
```

If that stamp predates your shutdown by more than an interval, pass the good
file explicitly: `necro-restore.sh <file.jsonl>`.

Passing the file explicitly also sidesteps a race that opens the moment a
server exists: TPM restarts the autosave daemon, and more than 90 seconds after
boot the recent-boot guard no longer applies. An autosave firing *while restore
is still working* captures a half-rebuilt server — observed in practice as a
2-record snapshot written the same second a 6-record restore began. It is
harmless on its own, since the next tick records the finished server, but for
those few minutes the newest file is not representative, so do not run a bare
`necro-resume` in that window.

`necro-doctor.sh` will not warn you here: it checks that agent records carry
UUIDs, not that the snapshot reflects the whole server. Count the records
yourself.

```sh
ls -1t ~/.claude/tmux-snapshots/*.jsonl | head -1 | xargs wc -l
```
