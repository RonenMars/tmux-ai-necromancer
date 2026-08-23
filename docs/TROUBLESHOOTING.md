# Troubleshooting

## Start here: `necro-doctor.sh`

Before working through the entries below, run the health check:

```bash
scripts/necro-doctor.sh
```

It is strictly read-only — it sends no keys, kills nothing, and writes nothing —
so it is safe against a live server at any time, including from inside tmux. It
exits 1 if it found a problem (✗) and 0 if it only found warnings (⚠).

It checks dependencies, your *effective* configuration (resolved the way the
scripts resolve it, so it catches a `~/.tmux.conf` edit you never re-sourced),
both daemons, both work locks, adapter loading, how many live agent panes have
a pinned UUID, the newest snapshot's age and how many of its records are
actually resumable, and the reboot pointer.

For a worked example of a failure this catches — autosave silently stopped for
~12 of 13 days while every other signal reported healthy — see
[`docs/incidents/2026-07-autosave-lock-outage.md`](incidents/2026-07-autosave-lock-outage.md).

The two checks worth reading first are **the newest snapshot** and **live agent
panes**. A snapshot whose records carry no UUID will resurrect nothing however
healthy everything else looks, and agent panes without a pinned UUID mean the
watcher is falling back to filesystem guesses. Note that a daemon can be
running while doing no work — a wedged lock produces exactly that — so
"daemon running" alone is not a clean bill of health.

### Running it unattended

The 2026-07 outage was continuously visible for 4½ days; what was missing was
anyone looking. Doctor is built to be scheduled: it is read-only, it exits 1
only on a `✗`, and with **no tmux server running it reports warnings and still
exits 0** — so a timer that fires while tmux is down does not cry wolf.

That makes the whole unattended story "run it on a schedule and make a non-zero
exit interrupt you". On macOS, a `~/Library/LaunchAgents` job every 30 minutes:

```xml
<key>ProgramArguments</key>
<array>
  <string>/bin/sh</string>
  <string>-c</string>
  <string>PATH=/opt/homebrew/bin:/usr/bin:/bin ~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-doctor.sh || osascript -e 'display notification "necro-doctor found a problem" with title "necromancer"'</string>
</array>
<key>StartInterval</key><integer>1800</integer>
```

Set `PATH` explicitly — launchd does not inherit your shell's, and doctor needs
`tmux`, `jq` and `python3`. On Linux use a systemd timer or a cron entry the
same way.

Do **not** have it append to a file instead. An hourly sampler was already
tried, wrote `lock=present` on 23 of 24 samples during the outage, and lost
because nobody opened the file. Route failures somewhere that interrupts you,
or don't bother scheduling it.

## Sessions missing after reboot

**Symptom:** `necro-resume` restores only a handful of sessions; most are gone.

**Cause:** The autosave runs every 5 minutes. If you close sessions manually
before rebooting — or if macOS begins killing processes during shutdown — the
final autosave captures only whatever was still alive at that moment.

**Fix:** Use `safe-reboot` / `safe-shutdown` instead of the system menu:

```bash
safe-reboot    # necro-reboot-prep.sh (snapshot all live sessions) → sudo reboot
safe-shutdown  # necro-reboot-prep.sh → sudo shutdown -h now
```

These aliases run `necro-reboot-prep.sh` first, which snapshots every live
session while they are all still open, then hands off to the OS.

Add them once to your shell config (already in
`dotfiles/shell/zshrc.d/30-ux/10-aliases.zsh`).

**Manual recovery from an older snapshot:**

If you already rebooted without prep, use the interactive menu (easiest):

```bash
necro-menu   # option 2 → pick the snapshot just before the shutdown timestamp
```

Or restore directly:

```bash
ls -lt ~/.claude/tmux-snapshots/*.idle-only.jsonl | head -10
necro-restore.sh ~/.claude/tmux-snapshots/<timestamp>.idle-only.jsonl
```

Use the snapshot immediately *before* the shutdown timestamp — the one taken
at shutdown may be partial.

---

## `necro-resume` blocked: "You're inside tmux"

**Symptom:** Running `necro-resume` inside a tmux pane prints
`✗ You're inside tmux. Run from a fresh terminal.`

**Cause:** `necro-reboot-resume.sh` guards against running inside tmux to avoid
conflicts with an already-live server's session state during post-reboot restore.

**Fix:** Open a terminal emulator that is *not* inside tmux (e.g. a new iTerm2
or Tabby window not attached to a session), then run `necro-resume` there.

`necro-menu` does **not** have this restriction — it calls `necro-restore.sh`
directly (no `$TMUX` guard), so you can run it from inside or outside tmux.

Use `necro-restore.sh <snapshot>` when you already know which snapshot file to
restore. Use `necro-resume` when you want the post-reboot wrapper to pick the
pinned reboot snapshot and bring tmux back up first.

---

## `necro-resume` loops "no server running" / "unary operator expected"

**Symptom:** Right after a fresh reboot, `necro-resume` repeats
`no server running on /private/tmp/tmux-<uid>/default`, `error creating  (No
such file or directory)`, and
`.../tmux-resurrect/scripts/restore.sh: line ...: [: -ne: unary operator
expected` — once per window in the last resurrect save — and never actually
creates a session.

**Cause:** Two compounding bugs in Phase 1 (`necro-reboot-resume.sh`, "ensure
tmux server is up"):

1. `tmux start-server` alone doesn't persist a server with zero sessions —
   tmux's default `exit-empty on` tears it right back down, so the "is the
   server up yet" poll never succeeds and falls through to the resurrect
   fallback below on every headless run.
2. tmux-resurrect's `restore.sh` resolves its own socket via
   `tmux_socket() { echo $TMUX | cut -d',' -f1; }` — it reads the *env var*,
   never asks tmux directly. `necro-resume` must run outside tmux (see above),
   so `$TMUX` is unset there, and every `-S "$(tmux_socket)"` call in
   `restore.sh` gets an empty socket path.

**Fix:** Update to a version with the Phase 1 patch — it seeds a throwaway
placeholder session (so the server actually stays up) and synthesizes a valid
`$TMUX` for the resurrect fallback from the server's real socket path. If
you're stuck on an old checkout, work around it manually: `Ctrl-C` the stuck
`necro-resume`, then run `necro-restore.sh` directly (see the section above) —
it creates sessions with plain `tmux new-session`, which doesn't depend on
`$TMUX` at all.

---

## Resumed pane sits empty — agent never actually resumed

**Symptom:** `necro-restore.sh` reports `agents resumed: N`, but a pane it
just created is empty — no `claude`/`codex` prompt, just an idle shell.

**Cause:** A pane just created by `new-window`/`split-window`/`new-session`
isn't immediately ready for input — its shell is still starting (zsh init,
plugin managers, etc.) — and `tmux send-keys` sent too early is dropped
entirely, not queued.

**Fix:** `necro-restore.sh` now waits `@necromancer_resume_start_delay`
(default 1s) after creating a fresh pane before sending the resume command.
If it's still happening on a slow shell, raise it:

```bash
necro-restore.sh --resume-start-delay 3 <snapshot>
# or: export NECROMANCER_RESUME_START_DELAY=3
```

If you already hit this on a stuck resume, just retry it by hand — safe to
`tmux send-keys -t <pane> 'claude --resume <uuid>' Enter` (or the `codex`
equivalent) once the pane's prompt is actually up.

---

## Autosave shows only 3 records when many sessions are open

**Symptom:** `autosave.log` summary line shows `total=3` but you have 15+
sessions.

**Likely cause:** The autosave fired during or after a shutdown sequence, and
most sessions were already gone. See **Sessions missing after reboot** above.

**Other causes to rule out** — `scripts/necro-doctor.sh` reports all of these
at once:
- `@necromancer_agents` tmux option doesn't include your agent
  (`tmux show-option -gv @necromancer_agents`)
- Watcher daemon is not running — check
  `pgrep -lf necro-watch-daemon.sh`
- A **stale work lock**. `.autosave.lock` is taken by each snapshot run and
  released by a trap; if that run is killed the lock would survive and every
  later tick exit silently, with the daemon still reporting as running.
  Autosave now recovers this itself — the run stamps its pid inside the lock
  and a later run reclaims it once that pid is gone. Recovery happens on the
  next *due* autosave, not the next daemon tick: the interval throttle returns
  first, so healing takes up to one `@necromancer_interval` (5 minutes by
  default), not one `@necromancer_autosave_tick`.
  `necro-doctor.sh` still reports a lock held over 10 minutes; if you
  ever see one persist beyond that, clear it with
  `rmdir "$(tmux show-option -gv @necromancer_snapshot_dir)/.autosave.lock"`
  and please file a bug, because the recovery should have handled it.
- Sessions use a different shell command than registered adapters recognize
  (`necro_agent_for_cmd` in `lib/agents.sh`)

---

## No autosave right after a reboot

**Symptom:** The tmux server is back up but no new snapshot appears for the
first minute or two.

**Cause:** Deliberate. Autosave skips entirely during the first 90 seconds of
machine uptime, so a snapshot taken of a half-restored server can't overwrite
the good pre-reboot one before `necro-reboot-resume.sh` has run.

**Fix:** None needed — wait it out, or run `necro-snapshot.sh --idle-only`
by hand once your sessions are back.

---

## `necro-resume` restores nothing: "skip resume: missing agent or uuid"

**Symptom:** Resume runs clean, reports `Records: 1` and
`agents resumed: 0`, and the one record it read is
`{"agent":"","uuid":"","cwd":"$HOME"}`.

**Cause:** With no reboot pointer set, resume falls back to the *most recent*
autosave — and autosave kept running while the server was collapsing, so the
newest file describes an already-empty server. The 90-second uptime guard
above only covers a reboot; a server killed or drained while the machine
stays up has no such protection, and each 5-minute tick writes another
emptier snapshot.

**Fix:** Pick the last snapshot that still has your agents and pass it to
restore positionally. To find it:

```sh
cd "$(tmux show-option -gv @necromancer_snapshot_dir)"
for f in $(ls -1t *.jsonl | head -30 | tail -r); do
  printf '%s  panes=%-3s agents=%s\n' "${f%%.*}" \
    "$(wc -l < "$f" | tr -d ' ')" \
    "$(jq -r 'select(.agent != null and .agent != "") | .agent' "$f" | wc -l | tr -d ' ')"
done
```

Then dry-run it before running it for real:

```sh
scripts/necro-restore.sh ~/.claude/tmux-snapshots/<stamp>.idle-only.jsonl --dry-run
```

Restore is idempotent, so running it for real afterwards reuses whatever
sessions are already up and only adds the missing ones.

**Prevention:** Run `necro-reboot-prep.sh` before any planned teardown — it
pins a reboot pointer, and resume prefers that pointer over
newest-file-wins. `@necromancer_max_snapshots` is what buys you the recovery
window; at the default 288 files × 5 min that is a day of history, so lower
it only if you are willing to lose that.

---

## Restore adds 0 windows on second run (idempotency)

This is expected. Restore is keyed on a stable per-pane marker
(`@necro_id`). If the windows already exist from a previous restore run,
they are reused — no duplicates, no extra agents launched.

## New restore controls

- Claude resumes are skipped when the transcript is too large; pass
  `--force-large` or raise `@necromancer_max_claude_transcript_bytes` if that
  is intentional. **This guard is Claude-only** — see below.
- Restore skips unsafe debug cwd paths such as `/private/tmp/claude-*`,
  `*tmux-debug-build*`, and `*crashtest*`; pass `--allow-unsafe-cwd` only if
  you know the snapshot is safe. This one applies to every agent.

---

## Codex-specific behavior

### The transcript size guard doesn't apply

`@necromancer_max_claude_transcript_bytes` and `--force-large` only affect
Claude records — `necro-restore.sh` gates that check on `agent = claude`. A
Codex rollout of any size is always resumed. If a huge rollout makes a restore
crawl, remove that record from the snapshot before restoring, or resume the
session by hand.

### Only the 200 most-recent rollouts are searched

Codex sessions are not foldered by cwd — they live in one date-nested tree and
the working directory is recorded inside each rollout's first line. To resolve
a cwd the adapter scans rollouts newest-first and reads that line, bounded to
the **200 most recent across all projects**.

A Codex session older than your last 200 rollouts is therefore invisible to the
filesystem fallback. This only affects the fallback: a pane the watcher already
pinned (or one launched with `codex resume <id>`, which is read straight from
the process arguments) resolves regardless of age.

### The pane command may not look like `codex`

tmux reports the truncated basename of the native binary — `codex-aarch64-a`
rather than `codex` — so the adapter matches `codex-*` as well as `codex`. If
your pane shows some other command name entirely, see
[`docs/agents.md`](agents.md).

## A `@necromancer_*` option has no effect

First check where you typed it. Every option snippet in these docs is written
for `~/.tmux.conf`:

```tmux
set -g @necromancer_logs_scheduled_cleanup '7d'
```

Pasted at a **shell** prompt, that line does not reach tmux at all. `set` is
also a shell builtin, so bash and zsh happily accept it, set a shell option
nobody reads, and print nothing. There is no error to notice — the option
simply stays unset. At a shell prompt the command needs the `tmux` prefix:

```bash
tmux set -g @necromancer_logs_scheduled_cleanup '7d'
```

Confirm what the server actually holds:

```bash
tmux show-options -gv @necromancer_logs_scheduled_cleanup
```

`invalid option: …` means it was never set. `scripts/necro-doctor.sh` prints
the effective configuration under **Effective configuration**, which is the
faster way to check several at once.

Note the two forms differ in lifetime as well as in reaching tmux at all:
`tmux set -g` changes the running server only and is lost when the server
exits, while a line in `~/.tmux.conf` is re-applied on every server start.
Setting it both ways is the normal end state.

If the option *is* set and still has no effect, see
[Applying a config change later](CONFIGURATION.md#applying-a-config-change-later)
— most options are read on each script run, but the daemons read their tick
once at startup and need a restart.

---

## Debug logs

- Enable tracing with `set -g @necromancer_debug 'on'` (or
  `NECROMANCER_DEBUG=1` for one command). Logs are off by default.
- Each executable script then writes structured lifecycle and action events to
  `~/.tmux-ai-necromancer-logs/<script>.log`; override the location with
  `@necromancer_log_dir` or `NECROMANCER_LOG_DIR`.
- Shell logs include `event phase=<phase> action=<action>` records for major
  lifecycle transitions and mutations. The TUI appends equivalent JSONL events
  to `tui.log`, including its load, review, exit, tmux, and snapshot phases.
  Neither logger records scrollback or transcript content.
- Run `scripts/necro-clean-debug-logs.sh --dry-run` to preview cleanup, then
  rerun without the flag to remove the debug logs. Add `--older-than 7d` to
  keep the last week instead of removing everything.
- Nothing rotates these files, so leaving debug mode on costs roughly 20 MB a
  day. `@necromancer_logs_scheduled_cleanup` makes the autosave daemon clean
  them on a duration or cron schedule — see
  [Debug logging → Scheduled cleanup](DEBUG_LOGGING.md#scheduled-cleanup).

---

## `necro-restore.sh` exits with "duplicate session"

Should not happen in current versions. If it does, the `ensure_session`
function in `necro-restore.sh` is not correctly guarding the `tmux
new-session` call. File a bug with the output of `tmux list-sessions`.
