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
  rerun without the flag to remove the debug logs.

---

## `necro-restore.sh` exits with "duplicate session"

Should not happen in current versions. If it does, the `ensure_session`
function in `necro-restore.sh` is not correctly guarding the `tmux
new-session` call. File a bug with the output of `tmux list-sessions`.
